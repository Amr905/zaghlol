using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using WireMock.RequestBuilders;
using WireMock.ResponseBuilders;
using WireMock.Server;
using Zaghlol.Application.Llm;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Llm;

namespace Zaghlol.Infrastructure.Tests.Llm;

/// <summary>A key source for tests; the value is a synthetic placeholder, not a credential.</summary>
internal sealed class TestKeys : ILlmApiKeyProvider
{
    public const string Value = "test-key-placeholder";

    public ValueTask<Sensitive<string>> GetKeyAsync(string providerId, CancellationToken cancellationToken) =>
        ValueTask.FromResult(new Sensitive<string>(Value));
}

internal sealed class TestPrompts : ILlmPromptCatalog
{
    public const string System = "STATIC SYSTEM PROMPT";

    public string GetSystemPrompt(string promptId) => System;
}

internal sealed class TestClock(DateTimeOffset start) : TimeProvider
{
    private DateTimeOffset now = start;

    public override DateTimeOffset GetUtcNow() => now;

    public void Advance(TimeSpan by) => now += by;
}

internal static class LlmFixtures
{
    public const string Marker = "ZZ-MARKER-QUESTION-9137";

    public static JsonElement Schema { get; } = JsonDocument.Parse("""{"type":"object","properties":{"v":{"type":"integer"}},"required":["v"],"additionalProperties":false}""").RootElement.Clone();

    public static LlmCall Call(string text = Marker, int maxOutputTokens = 300) =>
        new(LlmFeature.Ask, "ask-plan-v1", new Sensitive<string>(text), "ar", Schema, maxOutputTokens);

    public static string Read(string name) => File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Llm", "fixtures", name));

    public static LlmProviderOptions OpenAi(string baseUrl, int attemptMs = 8000) => new(
        "openai-test", LlmProviderKind.OpenAiResponses, "model-from-config", new Uri(baseUrl), null,
        TimeSpan.FromMilliseconds(attemptMs), 0.10m, 0.01m, 0.50m, null);

    public static LlmCallGuard Guard(TimeProvider? clock = null, LlmGuardOptions? options = null, ILogger? logger = null) =>
        new("openai-test", options ?? LlmGuardOptions.Default, clock ?? TimeProvider.System, logger ?? NullLogger.Instance);

    public static OpenAiResponsesProvider Provider(HttpClient http, LlmProviderOptions options, LlmCallGuard? guard = null) =>
        new(http, options, new TestKeys(), new TestPrompts(), guard ?? Guard(options: LlmGuardOptions.Default with { AttemptTimeout = options.AttemptTimeout }));

    public static HttpClient Client(string baseUrl) => new() { BaseAddress = new Uri(baseUrl.TrimEnd('/') + "/") };

    public static void Reply(WireMockServer server, int status, string body) =>
        server.Given(Request.Create().WithPath("/v1/responses").UsingPost())
            .RespondWith(Response.Create().WithStatusCode(status).WithHeader("Content-Type", "application/json").WithBody(body));
}

internal sealed class TestEnvironment(string name) : Microsoft.Extensions.Hosting.IHostEnvironment
{
    public string EnvironmentName { get; set; } = name;

    public string ApplicationName { get; set; } = "test";

    public string ContentRootPath { get; set; } = "/";

    public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = new Microsoft.Extensions.FileProviders.NullFileProvider();
}
