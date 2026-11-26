using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using WireMock.Server;
using Zaghlol.Application.Llm;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Llm;
using Zaghlol.Infrastructure.Tests.Observability;

namespace Zaghlol.Infrastructure.Tests.Llm;

/// <summary>AC4: the question text and the key stay out of ToString, JSON, the structured logger, exceptions and logs.</summary>
public sealed class LlmSensitiveScrubTests
{
    private const string Marker = LlmFixtures.Marker;

    [Fact]
    public void ToStringNeverShowsTheValue()
    {
        var call = LlmFixtures.Call();
        var result = new LlmResult(LlmOutcome.Ok, new LlmSensitive<byte[]>(Encoding.UTF8.GetBytes(Marker)), LlmUsage.None);

        Assert.DoesNotContain(Marker, new Sensitive<string>(Marker).ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(Marker, call.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(Marker, $"{call} {result} {call.UserText} {result.Json}", StringComparison.Ordinal);
        Assert.DoesNotContain(Marker, Convert.ToBase64String(Encoding.UTF8.GetBytes(result.ToString())), StringComparison.Ordinal);
    }

    [Fact]
    public void JsonSerialisationOfTheCallAndResultWritesTheFixedRedaction()
    {
        var call = LlmFixtures.Call();
        var result = new LlmResult(LlmOutcome.Ok, new LlmSensitive<byte[]>(Encoding.UTF8.GetBytes(Marker)), LlmUsage.None);

        var json = JsonSerializer.Serialize(call) + JsonSerializer.Serialize(result);

        Assert.DoesNotContain(Marker, json, StringComparison.Ordinal);
        Assert.DoesNotContain(Convert.ToBase64String(Encoding.UTF8.GetBytes(Marker)), json, StringComparison.Ordinal);
        Assert.Contains("\"UserText\":\"***\"", json, StringComparison.Ordinal);
        Assert.Contains("\"Json\":\"***\"", json, StringComparison.Ordinal);
    }

    [Fact]
    public void TheStructuredLoggerNeverDestructuresTheValue()
    {
        var call = LlmFixtures.Call();
        var result = new LlmResult(LlmOutcome.Ok, new LlmSensitive<byte[]>(Encoding.UTF8.GetBytes(Marker)), LlmUsage.None);

        var output = LogCapture.Run(log => log.Information("call {@Call} {Call} result {@Result} {Result} {@Text}", call, call, result, result, call.UserText));

        Assert.DoesNotContain(Marker, output, StringComparison.Ordinal);
    }

    [Fact]
    public async Task NoPathThroughTheProviderLeaksTheQuestionOrTheKeyIntoLogsExceptionsOrResults()
    {
        using var server = WireMockServer.Start();
        var logger = new CapturingLogger();
        var seen = new StringBuilder();

        // 500 echoing the question, a malformed 200 echoing it, a refusal echoing it, a timeout, a connection failure.
        var bodies = new[]
        {
            (500, "{\"error\":\"" + Marker + "\"}"),
            (200, "{\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"" + Marker + "\"}]}]}"),
            (200, "{\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"refusal\",\"refusal\":\"" + Marker + "\"}]}]}"),
        };
        foreach (var (status, body) in bodies)
        {
            server.Reset();
            LlmFixtures.Reply(server, status, body);
            var guard = LlmFixtures.Guard(logger: logger);
            var provider = LlmFixtures.Provider(LlmFixtures.Client(server.Urls[0]), LlmFixtures.OpenAi(server.Urls[0]), guard);
            var result = await provider.CompleteAsync(LlmFixtures.Call(), CancellationToken.None);
            seen.Append(result).Append(Encoding.UTF8.GetString(result.Json.Reveal()));
        }

        // Enough failures to open the circuit and log it.
        var failing = LlmFixtures.Guard(logger: logger);
        var failHandler = new ThrowingHandler();
        using var http = new HttpClient(failHandler) { BaseAddress = new Uri("https://llm.invalid/") };
        var broken = LlmFixtures.Provider(http, LlmFixtures.OpenAi("https://llm.invalid/"), failing);
        for (var i = 0; i < 6; i++)
        {
            seen.Append(await broken.CompleteAsync(LlmFixtures.Call(), CancellationToken.None));
        }

        Assert.Contains(logger.Lines, l => l.Contains("opened", StringComparison.Ordinal));
        var everything = seen + string.Join("\n", logger.Lines);
        Assert.DoesNotContain(Marker, everything, StringComparison.Ordinal);
        Assert.DoesNotContain(TestKeys.Value, everything, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ARequestThatThrowsInsideThePromptLookupDoesNotEchoTheQuestionInTheException()
    {
        var provider = new OpenAiResponsesProvider(
            new HttpClient(new ThrowingHandler()) { BaseAddress = new Uri("https://llm.invalid/") },
            LlmFixtures.OpenAi("https://llm.invalid/"),
            new TestKeys(),
            new ThrowingPrompts(),
            LlmFixtures.Guard());

        var e = await Assert.ThrowsAsync<InvalidOperationException>(() => provider.CompleteAsync(LlmFixtures.Call(), CancellationToken.None));

        Assert.DoesNotContain(Marker, e.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(TestKeys.Value, e.ToString(), StringComparison.Ordinal);
    }

    private sealed class ThrowingPrompts : ILlmPromptCatalog
    {
        public string GetSystemPrompt(string promptId) => throw new InvalidOperationException("unknown prompt");
    }

    private sealed class ThrowingHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            throw new HttpRequestException(HttpRequestError.ConnectionError, "connect failed");
    }

    private sealed class CapturingLogger : ILogger
    {
        public List<string> Lines { get; } = [];

        public IDisposable? BeginScope<TState>(TState state)
            where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
            Lines.Add(formatter(state, exception) + exception);
    }
}
