using System.Net;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Zaghlol.Application.Flags;
using Zaghlol.Infrastructure.Flags;

namespace Zaghlol.Infrastructure.Tests.Flags;

public class WebhookOpsNotifierTests
{
    private const string Url = "https://chat.example.test/hooks/secret-path-9f3a";

    private static readonly FlagState State = new("zakah", true, new FlagRules(["android"], "1.4.0", 10), 3, DateTimeOffset.UnixEpoch);

    private static IConfiguration Config(string? url) =>
        new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> { [WebhookOpsNotifier.UrlSetting] = url }).Build();

    [Fact]
    public async Task PostsTheChangeToTheConfiguredWebhook()
    {
        using var handler = new RecordingHandler(HttpStatusCode.OK);
        using var notifier = new WebhookOpsNotifier(Config(Url), NullLogger<WebhookOpsNotifier>.Instance, handler);

        await notifier.FlagChangedAsync(State, CancellationToken.None);

        var request = Assert.Single(handler.Requests);
        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal(Url, request.Uri);
        Assert.Contains("zakah", request.Body, StringComparison.Ordinal);
        Assert.Contains("ON", request.Body, StringComparison.Ordinal);
        Assert.Contains("version 3", request.Body, StringComparison.Ordinal);
        Assert.Contains("rolloutPercent=10", request.Body, StringComparison.Ordinal);
    }

    [Fact]
    public async Task WithoutAUrlNothingIsSent()
    {
        using var handler = new RecordingHandler(HttpStatusCode.OK);
        using var notifier = new WebhookOpsNotifier(Config(null), NullLogger<WebhookOpsNotifier>.Instance, handler);

        await notifier.FlagChangedAsync(State, CancellationToken.None);

        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task AFailingChannelNeverThrowsAndTheUrlIsNeverLogged()
    {
        var logger = new CapturingLogger();
        using var failing = new RecordingHandler(HttpStatusCode.InternalServerError);
        using var throwing = new RecordingHandler(new HttpRequestException("could not reach " + Url));
        using var first = new WebhookOpsNotifier(Config(Url), logger, failing);
        using var second = new WebhookOpsNotifier(Config(Url), logger, throwing);

        await first.FlagChangedAsync(State, CancellationToken.None);
        await second.FlagChangedAsync(State, CancellationToken.None);

        Assert.Equal(2, logger.Messages.Count);
        Assert.DoesNotContain(logger.Messages, m => m.Contains("secret-path", StringComparison.Ordinal) || m.Contains("example.test", StringComparison.Ordinal));
    }

    [Theory]
    [InlineData("http://chat.example.test/hook")]
    [InlineData("not a url")]
    [InlineData("/relative")]
    public void AMalformedOrInsecureUrlStopsStartupWithoutEchoingIt(string url)
    {
        var error = Assert.Throws<InvalidOperationException>(() => new WebhookOpsNotifier(Config(url), NullLogger<WebhookOpsNotifier>.Instance));

        Assert.DoesNotContain(url, error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void TheMessageHasNoOperatorOrInstallData()
    {
        var message = WebhookOpsNotifier.Message(State);

        Assert.Equal("Feature flag `zakah` is now ON (version 3). Rules: platforms=android, minAppVersion=1.4.0, rolloutPercent=10.", message);
    }

    private sealed record Recorded(HttpMethod Method, string Uri, string Body);

    private sealed class RecordingHandler : HttpMessageHandler
    {
        private readonly HttpStatusCode status;
        private readonly Exception? failure;

        public RecordingHandler(HttpStatusCode status) => this.status = status;

        public RecordingHandler(Exception failure) => this.failure = failure;

        public List<Recorded> Requests { get; } = [];

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var body = request.Content is null ? string.Empty : await request.Content.ReadAsStringAsync(cancellationToken);
            Requests.Add(new Recorded(request.Method, request.RequestUri!.ToString(), body));
            return failure is null ? new HttpResponseMessage(status) : throw failure;
        }
    }

    private sealed class CapturingLogger : ILogger<WebhookOpsNotifier>
    {
        public List<string> Messages { get; } = [];

        public IDisposable? BeginScope<TState>(TState state)
            where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
        {
            Messages.Add(formatter(state, exception) + (exception?.Message ?? string.Empty));
        }
    }
}
