using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Llm;

namespace Zaghlol.Infrastructure.Tests.Llm;

/// <summary>B97-m3 (FU-443) and B97-m4: the refusals around the provider display names, and the key check failing closed.</summary>
public sealed class LlmProviderNameRefusalTests
{
    private static IConfiguration Config(params (string Key, string? Value)[] values) =>
        new ConfigurationBuilder().AddInMemoryCollection(values.Select(v => new KeyValuePair<string, string?>(v.Key, v.Value))).Build();

    private static (string, string?)[] Provider(string? ar = "مساعد", string? en = "Helper") =>
    [
        ("Llm:ActiveProvider", "p1"),
        ("Llm:Providers:p1:DisplayNameAr", ar),
        ("Llm:Providers:p1:DisplayNameEn", en),
        ("Llm:Providers:p1:Kind", "OpenAiResponses"),
        ("Llm:Providers:p1:Model", "some-model"),
        ("Llm:Providers:p1:Endpoint", "https://llm.example.test/"),
        ("Llm:Providers:p1:PriceInPerMTok", "0.10"),
        ("Llm:Providers:p1:PriceCachedPerMTok", "0.005"),
        ("Llm:Providers:p1:PriceOutPerMTok", "0.50"),
    ];

    private static ServiceProvider Build(string environment, bool withKeys, params (string, string?)[] values)
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton<IHostEnvironment>(new TestEnvironment(environment));
        if (withKeys)
        {
            services.AddSingleton<ILlmApiKeyProvider, TestKeys>();
        }

        services.AddSingleton<ILlmPromptCatalog, TestPrompts>();
        services.AddZaghlolLlm(Config(values));
        return services.BuildServiceProvider();
    }

    [Theory]
    [InlineData("Production", true)]
    [InlineData("Production", false)]
    [InlineData("Testing", true)]
    [InlineData("Testing", false)]
    public async Task AProviderWithoutBothDisplayNamesStopsTheHost(string environment, bool missingArabic)
    {
        await using var provider = Build(environment, true, missingArabic ? Provider(ar: null) : Provider(en: null));
        var check = provider.GetServices<IHostedService>().Single(h => h.GetType().Name == "LlmStartupCheck");

        await Assert.ThrowsAsync<LlmConfigurationException>(() => check.StartAsync(CancellationToken.None));
    }

    [Theory]
    [InlineData("two\nlines")]
    [InlineData("name@host")]
    public void ADisplayNameOutsideThePatternIsRefused(string name) =>
        Assert.Throws<LlmConfigurationException>(() => LlmProviderOptions.ReadAll(Config(Provider(en: name))));

    [Fact]
    public void ADisplayNameOf65CharactersIsRefusedAndOf64IsAccepted()
    {
        Assert.Throws<LlmConfigurationException>(() => LlmProviderOptions.ReadAll(Config(Provider(en: new string('a', 65)))));
        Assert.Equal(64, LlmProviderOptions.ReadAll(Config(Provider(en: new string('a', 64)))).Single().DisplayNameEn!.Length);
    }

    [Fact]
    public void NamesAreNullUnlessBothAreSet()
    {
        var fallback = new ConfiguredActiveLlmProviderId(Config(("Llm:ActiveProvider", "a")));
        var identity = new ConfiguredLlmProviderIdentity(
            fallback,
            [Options("a", "أ", "A"), Options("b", "ب", null), Options("c", null, "C"), Options("d", "", "D")]);

        Assert.NotNull(identity.Names("a"));
        Assert.Null(identity.Names("b"));
        Assert.Null(identity.Names("c"));
        Assert.Null(identity.Names("d"));
        Assert.Null(identity.Names("unknown"));
    }

    // B97-m4: no key provider registered, or no key for this id: not known (fail closed).
    [Fact]
    public async Task AProviderIsKnownOnlyWithBothNamesAndAKey()
    {
        await using var withKey = Build("Testing", true, Provider());
        Assert.True(withKey.GetRequiredService<IKnownLlmProviderIds>().IsKnown("p1"));

        await using var noNames = Build("Testing", true, Provider(en: null));
        Assert.False(noNames.GetRequiredService<IKnownLlmProviderIds>().IsKnown("p1"));

        var keys = new RuntimeKeys { Present = false };
        var noKeyServices = new ServiceCollection();
        noKeyServices.AddLogging();
        noKeyServices.AddSingleton<IHostEnvironment>(new TestEnvironment("Testing"));
        noKeyServices.AddSingleton<ILlmApiKeyProvider>(keys);
        noKeyServices.AddSingleton<ILlmPromptCatalog, TestPrompts>();
        noKeyServices.AddZaghlolLlm(Config(Provider()));
        await using var noKey = noKeyServices.BuildServiceProvider();
        Assert.False(noKey.GetRequiredService<IKnownLlmProviderIds>().IsKnown("p1"));
    }

    [Fact]
    public void WithNoKeyProviderRegisteredNoProviderIsKnown()
    {
        var ids = new ConfiguredLlmProviderIds([Options("p1", "أ", "A")], new ServiceCollection().BuildServiceProvider());

        Assert.False(ids.IsKnown("p1"));
    }

    private static LlmProviderOptions Options(string id, string? ar, string? en) =>
        new(id, LlmProviderKind.OpenAiResponses, "m", null, null, TimeSpan.FromSeconds(1), 1m, 0m, 1m, null, ar, en);
}
