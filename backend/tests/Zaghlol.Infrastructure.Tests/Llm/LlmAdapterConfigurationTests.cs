using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Llm;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Llm;

/// <summary>T-338 AC4: the Vertex and Anthropic entries come from configuration (decimal prices, no constants) and register as providers.</summary>
public sealed class LlmAdapterConfigurationTests
{
    private static IConfiguration Config(params (string Key, string? Value)[] values) =>
        new ConfigurationBuilder().AddInMemoryCollection(values.Select(v => new KeyValuePair<string, string?>(v.Key, v.Value))).Build();

    private static (string, string?)[] Gemini(string? project = "proj-1", string? region = "europe-west4") =>
    [
        ("Llm:Providers:gemini-flash-lite:DisplayNameAr", "جيمني"),
        ("Llm:Providers:gemini-flash-lite:DisplayNameEn", "Gemini"),
        ("Llm:Providers:gemini-flash-lite:Kind", "VertexGemini"),
        ("Llm:Providers:gemini-flash-lite:Model", "model-a"),
        ("Llm:Providers:gemini-flash-lite:Endpoint", "https://europe-west4-aiplatform.googleapis.com/"),
        ("Llm:Providers:gemini-flash-lite:Region", region),
        ("Llm:Providers:gemini-flash-lite:Project", project),
        ("Llm:Providers:gemini-flash-lite:PriceInPerMTok", "0.25"),
        ("Llm:Providers:gemini-flash-lite:PriceCachedPerMTok", "0.025"),
        ("Llm:Providers:gemini-flash-lite:PriceOutPerMTok", "1.50"),
    ];

    private static (string, string?)[] Claude() =>
    [
        ("Llm:Providers:claude-haiku:DisplayNameAr", "كلود"),
        ("Llm:Providers:claude-haiku:DisplayNameEn", "Claude"),
        ("Llm:Providers:claude-haiku:Kind", "AnthropicMessages"),
        ("Llm:Providers:claude-haiku:Model", "model-b"),
        ("Llm:Providers:claude-haiku:Endpoint", "https://api.anthropic.com/"),
        ("Llm:Providers:claude-haiku:PriceInPerMTok", "1.00"),
        ("Llm:Providers:claude-haiku:PriceCachedPerMTok", "0.10"),
        ("Llm:Providers:claude-haiku:PriceOutPerMTok", "5.00"),
    ];

    [Fact]
    public void BothEntriesReadModelRegionProjectAndDecimalPricesFromConfiguration()
    {
        var all = LlmProviderOptions.ReadAll(Config([.. Gemini(), .. Claude()]));

        var gemini = all.Single(p => p.Id == "gemini-flash-lite");
        Assert.Equal(LlmProviderKind.VertexGemini, gemini.Kind);
        Assert.Equal(("model-a", "europe-west4", "proj-1"), (gemini.Model, gemini.Region, gemini.Project));
        Assert.Equal(0.025m, gemini.PriceCachedPerMTok);
        var claude = all.Single(p => p.Id == "claude-haiku");
        Assert.Equal(LlmProviderKind.AnthropicMessages, claude.Kind);
        Assert.Equal(5.00m, claude.PriceOutPerMTok);
        Assert.IsType<decimal>(claude.PriceInPerMTok);
    }

    [Theory]
    [InlineData(null, "europe-west4")]
    [InlineData("proj-1", null)]
    [InlineData("a/b", "europe-west4")]
    [InlineData("proj-1", "eu:1")]
    public void AVertexEntryNeedsAPlainProjectAndRegion(string? project, string? region) =>
        Assert.Throws<LlmConfigurationException>(() => LlmProviderOptions.ReadAll(Config(Gemini(project, region))));

    [Fact]
    public void AModelIdThatCouldEscapeTheUrlPathIsRefused()
    {
        var bad = Gemini().Select(e => e.Item1.EndsWith(":Model", StringComparison.Ordinal) ? (e.Item1, (string?)"x:generate/../y") : e).ToArray();

        Assert.Throws<LlmConfigurationException>(() => LlmProviderOptions.ReadAll(Config(bad)));
    }

    [Fact]
    public async Task EveryKindRegistersAProviderWithItsConfiguredId()
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton<IHostEnvironment>(new TestEnvironment("Testing"));
        services.AddSingleton<ILlmApiKeyProvider, RuntimeKeys>();
        services.AddSingleton<ILlmPromptCatalog, TestPrompts>();
        services.AddSingleton<IVertexAccessTokenSource, FakeVertexTokenSource>();
        services.AddZaghlolLlm(Config([.. Gemini(), .. Claude(), ("Llm:ActiveProvider", "claude-haiku")]));
        await using var provider = services.BuildServiceProvider();

        var ids = provider.GetServices<ILlmProvider>().Select(p => (p.Id, p.GetType())).ToArray();

        Assert.Contains(("gemini-flash-lite", typeof(VertexGeminiProvider)), ids);
        Assert.Contains(("claude-haiku", typeof(AnthropicMessagesProvider)), ids);
        var known = provider.GetRequiredService<IKnownLlmProviderIds>();
        Assert.True(known.IsKnown("claude-haiku"));
        Assert.False(known.IsKnown("nope"));
    }
}
