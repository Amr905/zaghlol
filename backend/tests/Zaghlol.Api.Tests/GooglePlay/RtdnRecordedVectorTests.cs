using System.Net;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Logging.Abstractions;
using Zaghlol.Api.Auth;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Api.Tests.GooglePlay;

/// <summary>Reports <b>skipped</b> until a recorded Play Console test notification is checked in (T-133 §9, PO question 5).</summary>
public sealed class RecordedRtdnFactAttribute : FactAttribute
{
    public RecordedRtdnFactAttribute()
    {
        if (!File.Exists(RtdnRecordedVectorTests.VectorPath))
        {
            Skip = "No recorded RTDN test notification yet (GooglePlay/fixtures/recorded-rtdn-test-notification.json; T-133 PO question 5).";
        }
    }
}

/// <summary>
/// T-133 §9: a Play Console "Send test notification" push captured once on staging, verified offline at its capture time against the
/// JWKS snapshot taken with it, through the real validator and ingest. The fixture is a JSON object of strings: <c>authorization</c>
/// (the header as received), <c>body</c> (the request body as received), <c>jwks</c> (Google's JWKS at capture), <c>capturedAt</c>
/// (RFC 3339), <c>audience</c>, <c>pushServiceAccount</c> and <c>packageName</c> (staging configuration). A <c>TEST</c> notification
/// carries no purchase data; the test checks in the shared test fixture directory of the Api tests (the validator is internal to the
/// API). No value is printed.
/// </summary>
[Trait("live", "googleplay")]
public sealed class RtdnRecordedVectorTests
{
    public static string VectorPath => Path.Combine(AppContext.BaseDirectory, "GooglePlay", "fixtures", "recorded-rtdn-test-notification.json");

    [RecordedRtdnFact]
    public async Task TheRecordedTestNotificationAuthenticatesAndIsIngestedAsTest()
    {
        var vector = JsonNode.Parse(await File.ReadAllTextAsync(VectorPath))!.AsObject();
        string Get(string name) => vector[name]!.GetValue<string>();
        var capturedAt = DateTimeOffset.Parse(Get("capturedAt"), System.Globalization.CultureInfo.InvariantCulture);
        var clock = new At(capturedAt);
        var settings = new PlayRtdnSettings(Get("audience"), Get("pushServiceAccount"), null);
        using var keys = new GoogleKeyCache(new SnapshotClients(Get("jwks")), clock, NullLogger<GoogleKeyCache>.Instance);
        var validator = new PubSubPushTokenValidator(keys, settings, clock);

        Assert.Equal(RtdnTags.Auth.Ok, await validator.ValidateAsync(new Microsoft.Extensions.Primitives.StringValues(Get("authorization")), CancellationToken.None));

        var envelope = JsonNode.Parse(Get("body"))!.AsObject();
        var message = envelope["message"]!.AsObject();
        var inbox = new Inbox();
        var catalog = new PlayProductCatalog(Get("packageName"), new Dictionary<string, PlayProductDefinition>());
        var ingest = new PlayNotificationIngest(catalog, settings, inbox, new NoTelemetry(), clock);
        var outcome = await ingest.IngestAsync(
            new PubSubPush(message["data"]?.GetValue<string>(), message["messageId"]?.GetValue<string>(), message["publishTime"]?.GetValue<string>(), envelope["subscription"]?.GetValue<string>()),
            CancellationToken.None);

        Assert.Equal(PlayIngestOutcome.Stored, outcome);
        Assert.Equal("TEST", Assert.Single(inbox.Records).Type);
    }

    private sealed class At(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class SnapshotClients(string jwks) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new(new Handler(jwks));

        private sealed class Handler(string jwks) : HttpMessageHandler
        {
            protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            {
                var body = request.RequestUri!.AbsoluteUri.EndsWith("/.well-known/openid-configuration", StringComparison.Ordinal)
                    ? new JsonObject { ["issuer"] = GoogleKeyCache.GoogleIssuer, ["jwks_uri"] = "https://www.googleapis.com/oauth2/v3/certs" }.ToJsonString()
                    : jwks;
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") });
            }
        }
    }

    private sealed class Inbox : IStoreNotificationInbox
    {
        public List<StoreNotificationRecord> Records { get; } = [];

        public Task<bool> TryInsertAsync(StoreNotificationRecord record, CancellationToken cancellationToken)
        {
            Records.Add(record);
            return Task.FromResult(true);
        }
    }

    private sealed class NoTelemetry : IPlayNotificationTelemetry
    {
        public void Ingested(string kind, string outcome)
        {
        }

        public void Processed(string type, string outcome)
        {
        }

        public void Lag(TimeSpan lag)
        {
        }

        public void DeadLettered()
        {
        }

        public void SetBacklog(long lessThan1h, long atLeast1h)
        {
        }

        public void BacklogFailed()
        {
        }

        public void Reconciled(string job, string outcome)
        {
        }

        public void Recovered(int count)
        {
        }

        public void RefundNotReflected()
        {
        }

        public void Heartbeat()
        {
        }
    }
}
