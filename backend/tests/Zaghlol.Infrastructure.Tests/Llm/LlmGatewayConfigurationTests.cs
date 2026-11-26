using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Llm;

namespace Zaghlol.Infrastructure.Tests.Llm;

public sealed class LlmGatewayConfigurationTests
{
    private static IConfiguration Config(params (string Key, string? Value)[] values) =>
        new ConfigurationBuilder().AddInMemoryCollection(values.Select(v => new KeyValuePair<string, string?>(v.Key, v.Value))).Build();

    private static (string, string?)[] OpenAi(string id = "p1", string kind = "OpenAiResponses") =>
    [
        ($"Llm:Providers:{id}:Kind", kind),
        ($"Llm:Providers:{id}:Model", "some-model"),
        ($"Llm:Providers:{id}:Endpoint", "https://llm.example.test/"),
        ($"Llm:Providers:{id}:PriceInPerMTok", "0.10"),
        ($"Llm:Providers:{id}:PriceCachedPerMTok", "0.005"),
        ($"Llm:Providers:{id}:PriceOutPerMTok", "0.50"),
    ];

    private static ServiceProvider Build(string environment, params (string, string?)[] values)
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton<IHostEnvironment>(new TestEnvironment(environment));
        services.AddSingleton<ILlmApiKeyProvider, TestKeys>();
        services.AddSingleton<ILlmPromptCatalog, TestPrompts>();
        services.AddZaghlolLlm(Config(values));
        return services.BuildServiceProvider();
    }

    private static Task Start(ServiceProvider provider) =>
        provider.GetServices<IHostedService>().Single(h => h.GetType().Name == "LlmStartupCheck").StartAsync(CancellationToken.None);

    // AC6
    [Fact]
    public void ModelEndpointAndPricesComeOnlyFromConfigurationAsDecimals()
    {
        var all = LlmProviderOptions.ReadAll(Config(OpenAi()));

        var p = Assert.Single(all);
        Assert.Equal("some-model", p.Model);
        Assert.Equal(new Uri("https://llm.example.test/"), p.Endpoint);
        Assert.Equal(0.10m, p.PriceInPerMTok);
        Assert.Equal(0.005m, p.PriceCachedPerMTok);
        Assert.Equal(0.50m, p.PriceOutPerMTok);
        Assert.IsType<decimal>(p.PriceInPerMTok);
    }

    [Theory]
    [InlineData("Model")]
    [InlineData("Endpoint")]
    [InlineData("PriceInPerMTok")]
    [InlineData("PriceCachedPerMTok")]
    [InlineData("PriceOutPerMTok")]
    [InlineData("Kind")]
    public void AMissingSettingFailsClosed(string missing)
    {
        var values = OpenAi().Where(v => !v.Item1.EndsWith(":" + missing, StringComparison.Ordinal)).ToArray();

        Assert.Throws<LlmConfigurationException>(() => LlmProviderOptions.ReadAll(Config(values)));
    }

    [Theory]
    [InlineData("PriceInPerMTok", "-1")]
    [InlineData("PriceInPerMTok", "1e3")]
    [InlineData("PriceInPerMTok", "abc")]
    [InlineData("Endpoint", "https://user:pw@llm.example.test/")]
    [InlineData("Endpoint", "https://llm.example.test/?key=1")]
    [InlineData("Endpoint", "ftp://llm.example.test/")]
    [InlineData("TimeoutMs", "20000")]
    public void MalformedSettingsAreRefused(string name, string value)
    {
        var values = OpenAi().Where(v => !v.Item1.EndsWith(":" + name, StringComparison.Ordinal)).Append(($"Llm:Providers:p1:{name}", (string?)value)).ToArray();

        var e = Assert.Throws<LlmConfigurationException>(() => LlmProviderOptions.ReadAll(Config(values)));
        Assert.DoesNotContain("pw@", e.Message, StringComparison.Ordinal);
    }

    // AC5
    [Fact]
    public async Task TheFakeProviderRefusesToStartOutsideDevelopmentAndTesting()
    {
        var values = new[] { ("Llm:Providers:fake:Kind", (string?)"Fake"), ("Llm:Providers:fake:Model", "m"), ("Llm:Providers:fake:PriceInPerMTok", "0"), ("Llm:Providers:fake:PriceCachedPerMTok", "0"), ("Llm:Providers:fake:PriceOutPerMTok", "0"), ("Llm:ActiveProvider", "fake") };

        foreach (var env in new[] { "Production", "Staging" })
        {
            await using var refused = Build(env, values);
            await Assert.ThrowsAsync<LlmConfigurationException>(() => Start(refused));
        }

        foreach (var env in new[] { "Development", "Testing" })
        {
            await using var allowed = Build(env, values);
            await Start(allowed);
            Assert.IsType<FakeLlmProvider>(allowed.GetRequiredService<ILlmProviderRegistry>().Active);
        }
    }

    [Fact]
    public async Task ProductionNeedsHttpsEndpointsAndAnActiveProviderThatExists()
    {
        var http = OpenAi().Select(v => v.Item1.EndsWith("Endpoint", StringComparison.Ordinal) ? (v.Item1, (string?)"http://llm.example.test/") : v).Append(("Llm:ActiveProvider", (string?)"p1")).ToArray();
        await using (var plain = Build("Production", http))
        {
            await Assert.ThrowsAsync<LlmConfigurationException>(() => Start(plain));
        }

        await using var wrongActive = Build("Production", OpenAi().Append(("Llm:ActiveProvider", (string?)"other")).ToArray());
        await Assert.ThrowsAsync<LlmConfigurationException>(() => Start(wrongActive));

        await using var fine = Build("Production", OpenAi().Append(("Llm:ActiveProvider", (string?)"p1")).ToArray());
        await Start(fine);
        Assert.Equal("p1", fine.GetRequiredService<ILlmProviderRegistry>().Active.Id);
    }

    [Fact]
    public async Task TheRegistryFollowsTheActiveIdAndFailsClosedOnAnUnknownOne()
    {
        var active = new MutableActive("a");
        var a = new FakeLlmProvider("a", []);
        var b = new FakeLlmProvider("b", []);
        var registry = new LlmProviderRegistry([a, b], active);

        Assert.Same(a, registry.Active);
        active.Current = "b";
        Assert.Same(b, registry.Active);
        active.Current = "zzz";
        Assert.Throws<LlmConfigurationException>(() => registry.Active);
        await Task.CompletedTask;
    }

    private sealed class MutableActive(string id) : IActiveLlmProviderId
    {
        public string Current { get; set; } = id;
    }
}
