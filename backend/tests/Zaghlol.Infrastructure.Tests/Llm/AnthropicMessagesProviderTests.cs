using System.Text.Json;
using WireMock.Server;
using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Llm;

namespace Zaghlol.Infrastructure.Tests.Llm;

public sealed class AnthropicMessagesProviderTests : IDisposable
{
    private readonly WireMockServer server = WireMockServer.Start();
    private readonly RuntimeKeys keys = new();

    public void Dispose() => server.Dispose();

    private AnthropicMessagesProvider Provider(int attemptMs = 8000) => AdapterFixtures.Anthropic(server, keys, attemptMs);

    private void Reply(int status, string body) => AdapterFixtures.Reply(server, AdapterFixtures.AnthropicPath, status, body);

    // AC1
    [Fact]
    public async Task TheRequestForcesOneNonStrictToolWithTheSchemaAndCarriesNoIdentifier()
    {
        Reply(200, LlmFixtures.Read("anthropic-ok.json"));

        var result = await Provider().CompleteAsync(LlmFixtures.Call(maxOutputTokens: 123), CancellationToken.None);

        Assert.Equal(LlmOutcome.Ok, result.Outcome);
        var request = Assert.Single(server.LogEntries).RequestMessage!;
        Assert.Equal(AdapterFixtures.AnthropicPath, request.Path);
        Assert.True(string.IsNullOrEmpty(request.RawQuery));

        using var body = JsonDocument.Parse(request.Body!);
        var root = body.RootElement;
        Assert.Equal(["model", "max_tokens", "system", "messages", "tools", "tool_choice"], root.EnumerateObject().Select(p => p.Name).ToArray());
        Assert.Equal("model-from-config", root.GetProperty("model").GetString());
        Assert.Equal(123, root.GetProperty("max_tokens").GetInt32());
        Assert.Equal(TestPrompts.System, root.GetProperty("system").GetString());
        var messages = root.GetProperty("messages").EnumerateArray().ToArray();
        Assert.Single(messages);
        Assert.Equal(LlmFixtures.Marker, messages[0].GetProperty("content").GetString());

        var tool = Assert.Single(root.GetProperty("tools").EnumerateArray().ToArray());
        Assert.False(tool.TryGetProperty("strict", out _));
        Assert.False(tool.GetProperty("input_schema").GetProperty("additionalProperties").GetBoolean());
        var choice = root.GetProperty("tool_choice");
        Assert.Equal("tool", choice.GetProperty("type").GetString());
        Assert.Equal(tool.GetProperty("name").GetString(), choice.GetProperty("name").GetString());

        // Only the key and the API version beyond the standard headers; no identifier anywhere.
        var customHeaders = request.Headers!.Keys.Where(k => k.StartsWith("x-", StringComparison.OrdinalIgnoreCase) || k.StartsWith("anthropic", StringComparison.OrdinalIgnoreCase)).Order().ToArray();
        Assert.Equal(["anthropic-version", "x-api-key"], customHeaders);
        Assert.Equal(AnthropicMessagesProvider.ApiVersion, request.Headers["anthropic-version"].Single());
        Assert.Equal(keys.Value, request.Headers["x-api-key"].Single());
        Assert.DoesNotContain(keys.Value, request.Body + request.Url + request.RawQuery, StringComparison.Ordinal);
        var everything = request.Body + request.Url + request.RawQuery + string.Join("|", request.Headers.Where(h => h.Key is not ("anthropic-version" or "x-api-key")).Select(h => h.Key + "=" + string.Join(",", h.Value)));
        foreach (var word in new[] { "metadata", "user_id", "install", "account", "attest", "version", "x-forwarded", "zaghlol" })
        {
            Assert.DoesNotContain(word, everything, StringComparison.OrdinalIgnoreCase);
        }
    }

    // AC2
    [Fact]
    public async Task ToolInputIsOkWithUsageCountingCacheReadsInTheInput()
    {
        Reply(200, LlmFixtures.Read("anthropic-ok.json"));

        var result = await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        Assert.Equal(LlmOutcome.Ok, result.Outcome);
        Assert.Equal(new LlmUsage(2198, 2048, 40), result.Usage);
        using var json = JsonDocument.Parse(result.Json.Reveal());
        Assert.Equal("PL-SUGGEST", json.RootElement.GetProperty("plan").GetString());
    }

    [Fact]
    public async Task ARefusalStopReasonIsRefused()
    {
        Reply(200, LlmFixtures.Read("anthropic-refusal.json"));

        var result = await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        Assert.Equal(LlmOutcome.Refused, result.Outcome);
        Assert.Empty(result.Json.Reveal());
        Assert.Equal(7, result.Usage.OutputTokens);
    }

    [Theory]
    [InlineData("anthropic-max-tokens.json")]
    [InlineData("anthropic-prose.json")]
    [InlineData("anthropic-duplicate-property.json")]
    public async Task CutOffProseOrDuplicatePropertyRepliesAreInvalid(string fixture)
    {
        Reply(200, LlmFixtures.Read(fixture));

        Assert.Equal(LlmOutcome.Invalid, (await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None)).Outcome);
    }

    [Theory]
    [InlineData("<html>gateway</html>")]
    [InlineData("[]")]
    [InlineData("{\"stop_reason\":\"tool_use\",\"content\":[]}")]
    public async Task AnUnexpectedEnvelopeIsInvalid(string body)
    {
        Reply(200, body);

        Assert.Equal(LlmOutcome.Invalid, (await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None)).Outcome);
    }

    [Theory]
    [InlineData(500)]
    [InlineData(529)]
    [InlineData(429)]
    [InlineData(401)]
    public async Task ErrorStatusesAreUpstream(int status)
    {
        Reply(status, "{\"type\":\"error\",\"error\":{\"message\":\"" + LlmFixtures.Marker + "\"}}");

        var result = await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        Assert.Equal(LlmOutcome.Upstream, result.Outcome);
        Assert.DoesNotContain(LlmFixtures.Marker, result.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task ASlowProviderIsATimeout()
    {
        AdapterFixtures.Slow(server, AdapterFixtures.AnthropicPath);

        Assert.Equal(LlmOutcome.Timeout, (await Provider(attemptMs: 300).CompleteAsync(LlmFixtures.Call(), CancellationToken.None)).Outcome);
    }

    [Fact]
    public async Task NoKeyMeansPausedBeforeAnyCall()
    {
        keys.Present = false;

        await Assert.ThrowsAsync<LlmServicePausedException>(() => Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None));

        Assert.Empty(server.LogEntries);
    }
}
