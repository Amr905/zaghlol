using System.Net;
using System.Text;
using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Llm;

namespace Zaghlol.LlmEval.Tests;

/// <summary>AC3 (the code side): keys from the environment only, never printed; FU-430 usage shapes; the shipped providers file is not runnable until set.</summary>
public sealed class LiveHarnessTests
{
    private static readonly System.Text.Json.JsonSerializerOptions SensitiveOptions = new() { Converters = { new LlmSensitiveJsonConverterFactory() } };

    [Theory]
    [InlineData("openai", "LLM_EVAL_KEY_OPENAI")]
    [InlineData("vertex", "LLM_EVAL_KEY_VERTEX")]
    [InlineData("my-prov.1", "LLM_EVAL_KEY_MY_PROV_1")]
    public void Key_variable_names_follow_the_provider_id(string id, string expected) => Assert.Equal(expected, EnvLlmApiKeys.EnvName(id));

    [Fact]
    public async Task Keys_are_read_from_the_environment_and_print_as_redacted()
    {
        const string sentinel = "SENTINEL-not-a-real-key-0001";
        var keys = new EnvLlmApiKeys(["openai", "vertex"], name => name == "LLM_EVAL_KEY_OPENAI" ? sentinel : null);
        Assert.True(keys.HasKey("openai"));
        Assert.False(keys.HasKey("vertex"));
        var key = await keys.GetKeyAsync("openai", CancellationToken.None);
        Assert.Equal(sentinel, key.Reveal());
        Assert.Equal("***", key.ToString());
        Assert.DoesNotContain(sentinel, System.Text.Json.JsonSerializer.Serialize(key, SensitiveOptions), StringComparison.Ordinal);
        await Assert.ThrowsAsync<LlmServicePausedException>(async () => await keys.GetKeyAsync("vertex", CancellationToken.None));
    }

    [Fact]
    public void The_shipped_providers_file_refuses_to_run_until_models_and_prices_are_set()
    {
        var json = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "providers.live.json"));
        var ex = Assert.Throws<LlmConfigurationException>(() => LiveProviders.ReadOptions(json));
        Assert.Contains("must be a positive decimal", ex.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void A_filled_providers_file_builds_the_real_adapters_and_an_unset_model_is_refused()
    {
        const string filled = """
            { "Providers": {
              "openai": { "Kind": "OpenAiResponses", "Model": "m-1", "Endpoint": "https://api.example.test", "PriceInPerMTok": "0.4", "PriceCachedPerMTok": "0.1", "PriceOutPerMTok": "1.6" },
              "vertex": { "Kind": "VertexGemini", "Model": "m-2", "Endpoint": "https://vertex.example.test", "Project": "p1", "Region": "r1", "PriceInPerMTok": "0.3", "PriceCachedPerMTok": "0.03", "PriceOutPerMTok": "2.5" },
              "anthropic": { "Kind": "AnthropicMessages", "Model": "UNSET", "Endpoint": "https://anthropic.example.test", "PriceInPerMTok": "1", "PriceCachedPerMTok": "0.1", "PriceOutPerMTok": "5" } } }
            """;
        var options = LiveProviders.ReadOptions(filled);
        var keys = new EnvLlmApiKeys([], _ => null);
        var byId = options.ToDictionary(o => o.Id, StringComparer.Ordinal);
        Assert.IsType<OpenAiResponsesProvider>(LiveProviders.Build(byId["openai"], keys).Adapter);
        Assert.IsType<VertexGeminiProvider>(LiveProviders.Build(byId["vertex"], keys).Adapter);
        Assert.Equal(0.4m, byId["openai"].PriceInPerMTok);
        Assert.Throws<LlmConfigurationException>(() => LiveProviders.Build(byId["anthropic"], keys));
    }

    [Fact]
    public void Usage_shapes_name_the_fields_and_kinds_and_never_a_value()
    {
        var openai = """{"id":"resp_x","usage":{"input_tokens":123456,"input_tokens_details":{"cached_tokens":7},"output_tokens":9,"total_tokens":3}}""";
        var vertex = """{"candidates":[{"x":1}],"usageMetadata":{"promptTokenCount":11,"cachedContentTokenCount":0,"candidatesTokenCount":5,"thoughtsTokenCount":0,"promptTokensDetails":[{"modality":"TEXT"}]}}""";
        var anthropic = """{"usage":{"input_tokens":1,"cache_creation_input_tokens":2,"cache_read_input_tokens":3,"output_tokens":4,"service_tier":"standard"}}""";

        var o = UsageShapeHandler.ShapesOf(Encoding.UTF8.GetBytes(openai));
        Assert.Contains("usage.input_tokens:number", o);
        Assert.Contains("usage.input_tokens_details.cached_tokens:number", o);
        var v = UsageShapeHandler.ShapesOf(Encoding.UTF8.GetBytes(vertex));
        Assert.Contains("usageMetadata.cachedContentTokenCount:number", v);
        Assert.Contains("usageMetadata.promptTokensDetails:array", v);
        var a = UsageShapeHandler.ShapesOf(Encoding.UTF8.GetBytes(anthropic));
        Assert.Contains("usage.cache_read_input_tokens:number", a);
        Assert.Contains("usage.service_tier:string", a);
        Assert.DoesNotContain(o.Concat(v).Concat(a), s => s.Contains("123456", StringComparison.Ordinal) || s.Contains("standard", StringComparison.Ordinal));
    }

    [Fact]
    public async Task The_handler_records_the_shape_and_leaves_the_response_readable()
    {
        var handler = new UsageShapeHandler(new StubHandler("""{"usage":{"input_tokens":5,"output_tokens":6}}"""));
        using var http = new HttpClient(handler);
        var body = await (await http.GetAsync(new Uri("https://llm.example.test/x"))).Content.ReadAsStringAsync();
        Assert.Contains("input_tokens", body, StringComparison.Ordinal);
        Assert.Equal(["usage.input_tokens:number", "usage.output_tokens:number"], handler.Shapes);
    }

    private sealed class StubHandler(string body) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") });
    }
}
