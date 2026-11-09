using System.Net.Http.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Flags;

namespace Zaghlol.Infrastructure.Flags;

/// <summary>
/// Posts a flag change to the ops channel through an incoming webhook (<c>OpsChannel:WebhookUrl</c>, a secret: set it from the
/// secrets manager, never a file in the repository). The body is <c>{"text": "..."}</c>, which Slack, Google Chat and Teams
/// incoming webhooks accept. Best effort: a missing URL turns it off, a failure or a timeout is logged as a status or a one-word reason only
/// (the URL is a credential and exception messages can contain it) and never fails the change, which is already committed
/// and audited. The message holds the flag key, its new value, version and rules; no operator name and no install data.
/// </summary>
internal sealed partial class WebhookOpsNotifier : IOpsNotifier, IDisposable
{
    public const string UrlSetting = "OpsChannel:WebhookUrl";

    private static readonly TimeSpan PostTimeout = TimeSpan.FromSeconds(3);

    private readonly Uri? webhook;
    private readonly HttpClient client;
    private readonly ILogger<WebhookOpsNotifier> logger;

    public WebhookOpsNotifier(IConfiguration configuration, ILogger<WebhookOpsNotifier> logger, HttpMessageHandler? handler = null)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(logger);

        this.logger = logger;
        var url = configuration[UrlSetting];
        if (!string.IsNullOrWhiteSpace(url))
        {
            // Fail at startup on a malformed value, without echoing it.
            if (!Uri.TryCreate(url, UriKind.Absolute, out var parsed) || parsed.Scheme != Uri.UriSchemeHttps)
            {
                throw new InvalidOperationException($"{UrlSetting} must be an absolute https URL.");
            }

            webhook = parsed;
        }

        client = handler is null
            ? new HttpClient(new SocketsHttpHandler { AllowAutoRedirect = false, ConnectTimeout = PostTimeout })
            : new HttpClient(handler, disposeHandler: false);
        client.Timeout = PostTimeout;
    }

    /// <summary>The channel message for a change.</summary>
    public static string Message(FlagState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        return $"Feature flag `{state.Key}` is now {(state.Value ? "ON" : "OFF")} (version {state.Version}). Rules: {FlagRulesJson.Describe(state.Rules)}.";
    }

    public async Task FlagChangedAsync(FlagState state, CancellationToken cancellationToken)
    {
        if (webhook is null)
        {
            return;
        }

        try
        {
            using var response = await client.PostAsJsonAsync(webhook, new Dictionary<string, string> { ["text"] = Message(state) }, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                ChannelRefused(logger, (int)response.StatusCode);
            }
        }
        catch (HttpRequestException)
        {
            PostFailed(logger, "unreachable");
        }
        catch (OperationCanceledException)
        {
            PostFailed(logger, "timeout");
        }
    }

    public void Dispose() => client.Dispose();

    // Property names and shapes follow the log allow-list (LogFieldPolicy): status is a number, reason a lowercase word.
    [LoggerMessage(Level = LogLevel.Warning, Message = "The ops channel answered {status} to a flag-change post.")]
    private static partial void ChannelRefused(ILogger logger, int status);

    [LoggerMessage(Level = LogLevel.Warning, Message = "The ops channel post for a flag change failed ({reason}).")]
    private static partial void PostFailed(ILogger logger, string reason);
}
