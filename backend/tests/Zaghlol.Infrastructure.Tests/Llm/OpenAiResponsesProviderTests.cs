using System.Net;
using System.Text.Json;
using WireMock.Server;
using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Llm;

namespace Zaghlol.Infrastructure.Tests.Llm;

public sealed class OpenAiResponsesProviderTests : IDisposable
{
    private readonly WireMockServer server = WireMockServer.Start();

    public void Dispose() => server.Dispose();

    private OpenAiResponsesProvider Provider(int attemptMs = 8000) =>
        LlmFixtures.Provider(LlmFixtures.Client(server.Urls[0]), LlmFixtures.OpenAi(server.Urls[0], attemptMs));

    // AC1
    [Fact]
    public async Task TheRequestIsStatelessStrictAndCarriesNoIdentifier()
    {
        LlmFixtures.Reply(server, 200, LlmFixtures.Read("openai-ok.json"));

        var result = await Provider().CompleteAsync(LlmFixtures.Call(maxOutputTokens: 123), CancellationToken.None);

        Assert.Equal(LlmOutcome.Ok, result.Outcome);
        var entry = Assert.Single(server.LogEntries);
        var request = entry.RequestMessage!;
        Assert.Equal("/v1/responses", request.Path);
        Assert.Null(request.RawQuery is { Length: > 0 } ? request.RawQuery : null);

        using var body = JsonDocument.Parse(request.Body!);
        var root = body.RootElement;
        Assert.Equal(["model", "input", "store", "text", "reasoning", "max_output_tokens"], root.EnumerateObject().Select(p => p.Name).ToArray());
        Assert.Equal("model-from-config", root.GetProperty("model").GetString());
        Assert.False(root.GetProperty("store").GetBoolean());
        Assert.Equal(123, root.GetProperty("max_output_tokens").GetInt32());
        Assert.Equal("none", root.GetProperty("reasoning").GetProperty("effort").GetString());
        var format = root.GetProperty("text").GetProperty("format");
        Assert.Equal("json_schema", format.GetProperty("type").GetString());
        Assert.True(format.GetProperty("strict").GetBoolean());
        Assert.False(format.GetProperty("schema").GetProperty("additionalProperties").GetBoolean());

        // Static prompt first, the question last.
        var input = root.GetProperty("input").EnumerateArray().ToArray();
        Assert.Equal(2, input.Length);
        Assert.Equal("system", input[0].GetProperty("role").GetString());
        Assert.Equal(TestPrompts.System, input[0].GetProperty("content").GetString());
        Assert.Equal("user", input[1].GetProperty("role").GetString());
        Assert.Equal(LlmFixtures.Marker, input[1].GetProperty("content").GetString());

        // Nothing identifying anywhere: only the bearer key, no install, account, IP, attestation or version.
        var everything = request.Body + string.Join("|", request.Headers!.Select(h => h.Key + "=" + string.Join(",", h.Value))) + request.Url + request.RawQuery;
        foreach (var word in new[] { "install", "account", "attest", "version", "x-forwarded", "zaghlol", "metadata", "prompt_cache_key", "safety_identifier" })
        {
            Assert.DoesNotContain(word, everything, StringComparison.OrdinalIgnoreCase);
        }

        Assert.Equal("Bearer " + TestKeys.Value, request.Headers!["Authorization"].Single());
    }

    // AC2
    [Fact]
    public async Task ValidJsonIsOkWithUsageIncludingCachedTokens()
    {
        LlmFixtures.Reply(server, 200, LlmFixtures.Read("openai-ok.json"));

        var result = await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        Assert.Equal(LlmOutcome.Ok, result.Outcome);
        Assert.Equal(new LlmUsage(2210, 2048, 31), result.Usage);
        using var json = JsonDocument.Parse(result.Json.Reveal());
        Assert.Equal("PL-SUGGEST", json.RootElement.GetProperty("plan").GetString());
    }

    [Fact]
    public async Task ARefusalIsRefused()
    {
        LlmFixtures.Reply(server, 200, LlmFixtures.Read("openai-refusal.json"));

        var result = await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        Assert.Equal(LlmOutcome.Refused, result.Outcome);
        Assert.Empty(result.Json.Reveal());
        Assert.Equal(9, result.Usage.OutputTokens);
    }

    [Theory]
    [InlineData("openai-malformed.json")]
    [InlineData("openai-incomplete.json")]
    public async Task MalformedOrCutOffReplyIsInvalid(string fixture)
    {
        LlmFixtures.Reply(server, 200, LlmFixtures.Read(fixture));

        var result = await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        Assert.Equal(LlmOutcome.Invalid, result.Outcome);
    }

    [Fact]
    public async Task ANonJsonEnvelopeIsInvalid()
    {
        LlmFixtures.Reply(server, 200, "<html>gateway</html>");

        Assert.Equal(LlmOutcome.Invalid, (await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None)).Outcome);
    }

    [Theory]
    [InlineData(500)]
    [InlineData(503)]
    [InlineData(429)]
    [InlineData(401)]
    public async Task ErrorStatusesAreUpstream(int status)
    {
        LlmFixtures.Reply(server, status, "{\"error\":{\"message\":\"" + LlmFixtures.Marker + "\"}}");

        var result = await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        Assert.Equal(LlmOutcome.Upstream, result.Outcome);
        Assert.DoesNotContain(LlmFixtures.Marker, result.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task ASlowProviderIsATimeout()
    {
        server.Given(WireMock.RequestBuilders.Request.Create().WithPath("/v1/responses").UsingPost())
            .RespondWith(WireMock.ResponseBuilders.Response.Create().WithStatusCode(200).WithDelay(TimeSpan.FromSeconds(5)).WithBody(LlmFixtures.Read("openai-ok.json")));

        var result = await Provider(attemptMs: 300).CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        Assert.Equal(LlmOutcome.Timeout, result.Outcome);
    }

    [Fact]
    public async Task TheCallersCancellationIsRethrownNotMappedToTimeout()
    {
        server.Given(WireMock.RequestBuilders.Request.Create().WithPath("/v1/responses").UsingPost())
            .RespondWith(WireMock.ResponseBuilders.Response.Create().WithStatusCode(200).WithDelay(TimeSpan.FromSeconds(5)).WithBody("{}"));
        using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(200));

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Provider().CompleteAsync(LlmFixtures.Call(), cts.Token));
    }

    [Fact]
    public async Task AnOversizedReplyIsInvalidNotBuffered()
    {
        LlmFixtures.Reply(server, 200, new string('x', OpenAiResponsesProvider.MaxResponseBytes + 10));

        Assert.Equal(LlmOutcome.Invalid, (await Provider().CompleteAsync(LlmFixtures.Call(), CancellationToken.None)).Outcome);
    }

    [Fact]
    public async Task AConnectionFailureIsRetriedOnceThenUpstream()
    {
        var handler = new CountingFailHandler();
        using var http = new HttpClient(handler) { BaseAddress = new Uri("https://llm.invalid/") };
        var provider = LlmFixtures.Provider(http, LlmFixtures.OpenAi("https://llm.invalid/"));

        var result = await provider.CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        Assert.Equal(LlmOutcome.Upstream, result.Outcome);
        Assert.Equal(2, handler.Calls);
    }

    [Fact]
    public async Task AFailureAfterTheRequestWasSentIsNotRetried()
    {
        var handler = new CountingFailHandler(HttpRequestError.ConnectionError, connectOnly: false);
        using var http = new HttpClient(handler) { BaseAddress = new Uri("https://llm.invalid/") };
        var provider = LlmFixtures.Provider(http, LlmFixtures.OpenAi("https://llm.invalid/"));

        var result = await provider.CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        Assert.Equal(LlmOutcome.Upstream, result.Outcome);
        Assert.Equal(1, handler.Calls);
    }

    private sealed class CountingFailHandler(HttpRequestError error = HttpRequestError.ConnectionError, bool connectOnly = true) : HttpMessageHandler
    {
        public int Calls { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            // connectOnly = false models a read failure after the send (a plain HttpRequestException).
            throw connectOnly ? new HttpRequestException(error, "connect failed") : new HttpRequestException(HttpRequestError.ResponseEnded, "reset");
        }
    }
}
