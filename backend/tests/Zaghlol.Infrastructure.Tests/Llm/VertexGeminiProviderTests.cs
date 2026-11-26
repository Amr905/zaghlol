using System.Text.Json;
using WireMock.Server;
using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Llm;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Llm;

public sealed class VertexGeminiProviderTests : IDisposable
{
    private readonly WireMockServer server = WireMockServer.Start();
    private readonly FakeVertexTokenSource tokens = new();
    private readonly RuntimeKeys keys = new();

    public void Dispose() => server.Dispose();

    private VertexGeminiProvider Provider(int attemptMs = 8000) => AdapterFixtures.Vertex(server, tokens, keys, attemptMs);

    private void Reply(int status, string body) => AdapterFixtures.Reply(server, AdapterFixtures.VertexPath, status, body);

    // AC1
    [Fact]
    public async Task TheRequestCarriesTheSchemaAndTheCapAndNoGroundingCacheOrIdentifier()
    {
        Reply(200, LlmFixtures.Read("vertex-ok.json"));

        var result = await Provider().CompleteAsync(LlmFixtures.Call(maxOutputTokens: 123), CancellationToken.None);

        Assert.Equal(LlmOutcome.Ok, result.Outcome);
        var request = Assert.Single(server.LogEntries).RequestMessage!;
        Assert.Equal(AdapterFixtures.VertexPath, request.Path);
        Assert.True(string.IsNullOrEmpty(request.RawQuery));

        using var body = JsonDocument.Parse(request.Body!);
        var root = body.RootElement;
        Assert.Equal(["systemInstruction", "contents", "generationConfig"], root.EnumerateObject().Select(p => p.Name).ToArray());
        Assert.Equal(TestPrompts.System, root.GetProperty("systemInstruction").GetProperty("parts")[0].GetProperty("text").GetString());
        var contents = root.GetProperty("contents").EnumerateArray().ToArray();
        Assert.Single(contents);
        Assert.Equal(LlmFixtures.Marker, contents[0].GetProperty("parts")[0].GetProperty("text").GetString());

        var config = root.GetProperty("generationConfig");
        Assert.Equal(["responseMimeType", "responseJsonSchema", "maxOutputTokens", "thinkingConfig"], config.EnumerateObject().Select(p => p.Name).ToArray());
        Assert.Equal("application/json", config.GetProperty("responseMimeType").GetString());
        Assert.Equal(123, config.GetProperty("maxOutputTokens").GetInt32());
        Assert.Equal("MINIMAL", config.GetProperty("thinkingConfig").GetProperty("thinkingLevel").GetString());
        Assert.False(config.GetProperty("responseJsonSchema").GetProperty("additionalProperties").GetBoolean());

        var everything = request.Body + request.Url + request.RawQuery + string.Join("|", request.Headers!.Select(h => h.Key + "=" + string.Join(",", h.Value)));
        foreach (var word in new[] { "cachedContent", "tools", "grounding", "googleSearch", "labels", "install", "account", "attest", "version", "x-forwarded", "zaghlol", "metadata", "user" })
        {
            Assert.DoesNotContain(word, everything.Replace("\"role\":\"user\"", string.Empty, StringComparison.Ordinal), StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public async Task TheKeyGoesOnlyToTheTokenSourceAndTheBearerIsTheMintedTokenNeverInTheUrl()
    {
        Reply(200, LlmFixtures.Read("vertex-ok.json"));

        await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        var request = Assert.Single(server.LogEntries).RequestMessage!;
        Assert.Equal(1, tokens.Calls);
        Assert.Equal(keys.Value.Length, tokens.LastKeyLength);
        Assert.Equal("Bearer " + tokens.Token, request.Headers!["Authorization"].Single());
        Assert.DoesNotContain(keys.Value, request.Body + request.Url + string.Join("|", request.Headers.Select(h => string.Join(",", h.Value))), StringComparison.Ordinal);
    }

    // AC3 (the transform removes only annotations)
    [Fact]
    public async Task TheSentSchemaHasNoSchemaIdOrCommentAtTheRoot()
    {
        Reply(200, LlmFixtures.Read("vertex-ok.json"));
        var schema = JsonDocument.Parse("""{"$schema":"x","$id":"y","$comment":"z","type":"object"}""").RootElement.Clone();

        await Provider().CompleteAsync(LlmFixtures.Call() with { OutputSchema = schema }, CancellationToken.None);

        using var body = JsonDocument.Parse(server.LogEntries.Single().RequestMessage!.Body!);
        var sent = body.RootElement.GetProperty("generationConfig").GetProperty("responseJsonSchema");
        Assert.Equal(["type"], sent.EnumerateObject().Select(p => p.Name).ToArray());
    }

    // AC2
    [Fact]
    public async Task ValidJsonIsOkWithUsageIncludingCachedAndThinkingTokens()
    {
        Reply(200, LlmFixtures.Read("vertex-ok.json"));

        var result = await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        Assert.Equal(LlmOutcome.Ok, result.Outcome);
        Assert.Equal(new LlmUsage(2200, 2048, 34), result.Usage);
        using var json = JsonDocument.Parse(result.Json.Reveal());
        Assert.Equal("PL-SUGGEST", json.RootElement.GetProperty("plan").GetString());
    }

    [Theory]
    [InlineData("vertex-prompt-blocked.json")]
    [InlineData("vertex-safety.json")]
    public async Task ABlockedPromptOrCandidateIsRefused(string fixture)
    {
        Reply(200, LlmFixtures.Read(fixture));

        var result = await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        Assert.Equal(LlmOutcome.Refused, result.Outcome);
        Assert.Empty(result.Json.Reveal());
        Assert.Equal(2200, result.Usage.InputTokens);
    }

    [Theory]
    [InlineData("vertex-max-tokens.json")]
    [InlineData("vertex-malformed.json")]
    [InlineData("vertex-duplicate-property.json")]
    public async Task CutOffMalformedOrDuplicatePropertyRepliesAreInvalid(string fixture)
    {
        Reply(200, LlmFixtures.Read(fixture));

        Assert.Equal(LlmOutcome.Invalid, (await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None)).Outcome);
    }

    [Fact]
    public async Task ADuplicatePropertyInTheEnvelopeIsInvalid()
    {
        var ok = LlmFixtures.Read("vertex-ok.json");
        Reply(200, ok.Replace("\"modelVersion\"", "\"usageMetadata\": {}, \"modelVersion\"", StringComparison.Ordinal));

        Assert.Equal(LlmOutcome.Invalid, (await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None)).Outcome);
    }

    [Theory]
    [InlineData("<html>gateway</html>")]
    [InlineData("{}")]
    [InlineData("{\"candidates\":[]}")]
    public async Task AnUnexpectedEnvelopeIsInvalid(string body)
    {
        Reply(200, body);

        Assert.Equal(LlmOutcome.Invalid, (await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None)).Outcome);
    }

    [Theory]
    [InlineData(500)]
    [InlineData(503)]
    [InlineData(429)]
    [InlineData(401)]
    public async Task ErrorStatusesAreUpstream(int status)
    {
        Reply(status, "{\"error\":{\"message\":\"" + LlmFixtures.Marker + "\"}}");

        var result = await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        Assert.Equal(LlmOutcome.Upstream, result.Outcome);
        Assert.DoesNotContain(LlmFixtures.Marker, result.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task AFailedTokenExchangeIsUpstreamAndSendsNothing()
    {
        tokens.Fail = true;

        var result = await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        Assert.Equal(LlmOutcome.Upstream, result.Outcome);
        Assert.Empty(server.LogEntries);
    }

    [Fact]
    public async Task ASlowProviderIsATimeout()
    {
        AdapterFixtures.Slow(server, AdapterFixtures.VertexPath);

        Assert.Equal(LlmOutcome.Timeout, (await Provider(attemptMs: 300).CompleteAsync(LlmFixtures.Call(), CancellationToken.None)).Outcome);
    }

    [Fact]
    public async Task NoKeyMeansPausedBeforeAnyCall()
    {
        keys.Present = false;

        await Assert.ThrowsAsync<LlmServicePausedException>(() => Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None));

        Assert.Equal(0, tokens.Calls);
        Assert.Empty(server.LogEntries);
    }

    [Theory]
    [InlineData("proj/../x")]
    [InlineData("a:b")]
    [InlineData("")]
    public void ProjectRegionAndModelMustBePlainPathParts(string value) =>
        Assert.DoesNotMatch(VertexGeminiProvider.PathPart(), value);
}
