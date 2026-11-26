using Microsoft.Extensions.Logging.Abstractions;
using WireMock.RequestBuilders;
using WireMock.ResponseBuilders;
using WireMock.Server;
using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Llm;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Llm;

/// <summary>A key source whose value is built at run time (no secret-looking literal in the source).</summary>
internal sealed class RuntimeKeys : ILlmApiKeyProvider
{
    public string Value { get; } = "k-" + Guid.NewGuid().ToString("N");

    public bool Present { get; set; } = true;

    public bool HasKey(string providerId) => Present;

    public ValueTask<LlmSensitive<string>> GetKeyAsync(string providerId, CancellationToken cancellationToken) =>
        Present ? ValueTask.FromResult(new LlmSensitive<string>(Value)) : ValueTask.FromException<LlmSensitive<string>>(new LlmServicePausedException());
}

internal static class AdapterFixtures
{
    public const string VertexPath = "/v1/projects/proj-1/locations/europe-west4/publishers/google/models/model-from-config:generateContent";
    public const string AnthropicPath = "/v1/messages";

    public static LlmProviderOptions Vertex(string baseUrl, int attemptMs = 8000) => new(
        "gemini-test", LlmProviderKind.VertexGemini, "model-from-config", new Uri(baseUrl), "europe-west4",
        TimeSpan.FromMilliseconds(attemptMs), 0.25m, 0.025m, 1.50m, "proj-1");

    public static LlmProviderOptions Anthropic(string baseUrl, int attemptMs = 8000) => new(
        "claude-test", LlmProviderKind.AnthropicMessages, "model-from-config", new Uri(baseUrl), null,
        TimeSpan.FromMilliseconds(attemptMs), 1.00m, 0.10m, 5.00m);

    private static LlmCallGuard Guard(LlmProviderOptions options) =>
        new(options.Id, LlmGuardOptions.Default with { AttemptTimeout = options.AttemptTimeout }, TimeProvider.System, NullLogger.Instance);

    public static VertexGeminiProvider Vertex(WireMockServer server, FakeVertexTokenSource tokens, RuntimeKeys keys, int attemptMs = 8000)
    {
        var options = Vertex(server.Urls[0], attemptMs);
        return new VertexGeminiProvider(LlmFixtures.Client(server.Urls[0]), options, keys, tokens, new TestPrompts(), Guard(options));
    }

    public static AnthropicMessagesProvider Anthropic(WireMockServer server, RuntimeKeys keys, int attemptMs = 8000)
    {
        var options = Anthropic(server.Urls[0], attemptMs);
        return new AnthropicMessagesProvider(LlmFixtures.Client(server.Urls[0]), options, keys, new TestPrompts(), Guard(options));
    }

    public static void Reply(WireMockServer server, string path, int status, string body) =>
        server.Given(Request.Create().WithPath(path).UsingPost())
            .RespondWith(Response.Create().WithStatusCode(status).WithHeader("Content-Type", "application/json").WithBody(body));

    public static void Slow(WireMockServer server, string path) =>
        server.Given(Request.Create().WithPath(path).UsingPost())
            .RespondWith(Response.Create().WithStatusCode(200).WithDelay(TimeSpan.FromSeconds(5)).WithBody("{}"));
}
