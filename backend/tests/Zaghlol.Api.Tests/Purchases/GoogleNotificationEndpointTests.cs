using System.Collections.Concurrent;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Npgsql;
using Zaghlol.Api.Endpoints.V1;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Purchases;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Purchases;

/// <summary>The purchases host plus <c>POST /v1/notifications/google</c> (T-133) on PostgreSQL, a fake Google issuer and the body spy.</summary>
public sealed class GoogleNotificationHostFixture : AppleNotificationHostFixture
{
    public FakeOidcIssuer Google { get; } = RtdnPushKit.NewGoogle();

    public ConcurrentDictionary<string, int> BodyReads { get; } = new(StringComparer.Ordinal);

    protected override IReadOnlyDictionary<string, string?> Settings
    {
        get
        {
            var settings = new Dictionary<string, string?>(base.Settings);
            foreach (var (key, value) in RtdnPushKit.Settings())
            {
                settings[key] = value;
            }

            return settings;
        }
    }

    public string Bearer() => "Bearer " + RtdnPushKit.Token(Google, Clock.GetUtcNow());

    public Task<HttpResponseMessage> PushAsync(JsonObject payload, string? messageId = null, Action<JsonObject>? envelope = null) =>
        RtdnPushKit.PostAsync(Client, RtdnPushKit.Envelope(payload, messageId ?? RtdnPushKit.NewMessageId(), Clock.GetUtcNow(), envelope).ToJsonString(), Bearer());

    /// <summary>The worker side (Worker login): the RTDN processor and jobs against the same database and Play stand-in.</summary>
    public ServiceProvider WorkerServices()
    {
        var settings = new Dictionary<string, string?>(Play.Settings()) { ["ConnectionStrings:Worker"] = Database.Worker };
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(settings).Build();
        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(configuration);
        services.AddSingleton<IHostEnvironment>(new TestingHost());
        services.AddSingleton<TimeProvider>(Clock);
        services.AddLogging();
        services.AddInfrastructure();
        services.AddZaghlolDatabase(DatabaseRole.Worker);
        services.AddZaghlolPlayNotificationWorker();
        return services.BuildServiceProvider();
    }

    public async Task<PlayProcessRun> ProcessAsync()
    {
        await using var services = WorkerServices();
        return await services.GetRequiredService<PlayNotificationProcessor>().RunOnceAsync(CancellationToken.None);
    }

    public async Task<List<object?[]>> QueryAsync(string sql, params (string Name, object Value)[] parameters)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        foreach (var (name, value) in parameters)
        {
            command.Parameters.AddWithValue(name, value);
        }

        await using var reader = await command.ExecuteReaderAsync();
        var rows = new List<object?[]>();
        while (await reader.ReadAsync())
        {
            var row = new object?[reader.FieldCount];
            for (var i = 0; i < reader.FieldCount; i++)
            {
                row[i] = reader.IsDBNull(i) ? null : reader.GetValue(i);
            }

            rows.Add(row);
        }

        return rows;
    }

    protected override void ConfigureServices(IServiceCollection services)
    {
        base.ConfigureServices(services);
        RtdnPushKit.Configure(services, Google);
    }

    protected override void UseBeforePipeline(WebApplication application) => RtdnPushKit.UseBodySpy(application, BodyReads);

    protected override void MapEndpoints(WebApplication application)
    {
        base.MapEndpoints(application);
        application.MapGoogleNotifications();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            Google.Dispose();
        }

        base.Dispose(disposing);
    }

    private sealed class TestingHost : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = "Testing";

        public string ApplicationName { get; set; } = "t";

        public string ContentRootPath { get; set; } = "/";

        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = null!;
    }
}

/// <summary>
/// T-133 end to end on PostgreSQL: the push stores exactly the extracted columns once, unusable pushes leave no row, unknown fields and
/// attributes reach no column, log or span (AC 4), and the worker turns a void into <c>refunded</c> (AC 1) with duplicates processed
/// once (AC 2).
/// </summary>
[Collection(ApiHostGroup.Name)]
public class GoogleNotificationEndpointTests(GoogleNotificationHostFixture fixture) : IClassFixture<GoogleNotificationHostFixture>
{
    private PlayWireMock Play => fixture.Play;

    [Fact]
    public async Task AGenuinePushIsStoredOnceWithExactlyTheExtractedColumns()
    {
        var token = PurchasesHostFixture.NewPlayToken();
        var payload = RtdnPushKit.Payload(token, 4, fixture.Clock.GetUtcNow().AddSeconds(-30));
        var id = RtdnPushKit.NewMessageId();

        using var first = await fixture.PushAsync(payload, id);
        using var replay = await fixture.PushAsync(payload, id, e => e["deliveryAttempt"] = 2);

        Assert.Equal(HttpStatusCode.NoContent, first.StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, replay.StatusCode);
        Assert.Equal(1, await fixture.CountAsync(id));
        Assert.Equal(0, Play.CountContaining("GET", token));
        var row = Assert.Single(await fixture.QueryAsync(
            "SELECT store, type, subtype, product_id, store_key, environment, event_time, payload_digest, processed_at, attempts, last_error FROM zaghlol.store_notifications WHERE external_id = @id",
            ("id", id)));
        Assert.Equal("google_play", row[0]);
        Assert.Equal("SUBSCRIPTION_PURCHASED", row[1]);
        Assert.Null(row[2]);
        Assert.Null(row[3]);
        Assert.Equal(token, row[4]);
        Assert.Null(row[5]);
        Assert.Equal(fixture.Clock.GetUtcNow().AddSeconds(-30).ToUnixTimeMilliseconds(), new DateTimeOffset((DateTime)row[6]!).ToUnixTimeMilliseconds());
        Assert.Equal(SHA256.HashData(Encoding.UTF8.GetBytes(payload.ToJsonString())), row[7]);
        Assert.Null(row[8]);
        Assert.Equal(0, row[9]);
        Assert.Null(row[10]);
    }

    [Fact]
    public async Task TwoConcurrentDeliveriesOfOneMessageStoreOneRow()
    {
        var payload = RtdnPushKit.Payload(PurchasesHostFixture.NewPlayToken());
        var id = RtdnPushKit.NewMessageId();

        var responses = await Task.WhenAll(fixture.PushAsync(payload, id), fixture.PushAsync(payload, id));

        Assert.All(responses, r => Assert.Equal(HttpStatusCode.NoContent, r.StatusCode));
        Assert.Equal(1, await fixture.CountAsync(id));
        foreach (var response in responses)
        {
            response.Dispose();
        }
    }

    [Fact]
    public async Task ATestNotificationIsStoredProcessedWithoutAToken()
    {
        var id = RtdnPushKit.NewMessageId();
        var payload = RtdnPushKit.Payload("unused", edit: p =>
        {
            p.Remove("subscriptionNotification");
            p["testNotification"] = new JsonObject { ["version"] = "1.0" };
        });

        using var response = await fixture.PushAsync(payload, id);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        var row = Assert.Single(await fixture.QueryAsync("SELECT type, store_key, processed_at IS NOT NULL FROM zaghlol.store_notifications WHERE external_id = @id", ("id", id)));
        Assert.Equal("TEST", row[0]);
        Assert.Null(row[1]);
        Assert.Equal(true, row[2]);
    }

    [Fact]
    public async Task UnusablePushesAre204WithNoRow()
    {
        var before = await fixture.TotalAsync();

        using var package = await fixture.PushAsync(RtdnPushKit.Payload("tok.pkg", edit: p => p["packageName"] = "com.other"));
        using var stale = await RtdnPushKit.PostAsync(fixture.Client, RtdnPushKit.Envelope(RtdnPushKit.Payload("tok.old"), RtdnPushKit.NewMessageId(), fixture.Clock.GetUtcNow().AddDays(-40)).ToJsonString(), fixture.Bearer());
        using var junk = await RtdnPushKit.PostAsync(fixture.Client, "{\"message\":42}", fixture.Bearer());

        Assert.All(new[] { package, stale, junk }, r => Assert.Equal(HttpStatusCode.NoContent, r.StatusCode));
        Assert.Equal(before, await fixture.TotalAsync());
    }

    /// <summary>
    /// AC 4 (T-134 deviation 2 method): sentinels as an unknown top-level field, inside <c>message</c>, as an attribute key and value,
    /// in <c>orderingKey</c>, in <c>message_id</c>, inside the payload and inside <c>subscriptionNotification</c> reach no text or
    /// bytea column of any table, no log line and no activity. Positive control: the row is stored. The bearer token is never logged.
    /// </summary>
    [Fact]
    public async Task UnknownFieldsAndAttributesNeverReachTheDatabaseLogsOrSpans()
    {
        var sentinel = "ZGLSENTINEL" + Convert.ToHexString(RandomNumberGenerator.GetBytes(8));
        var id = RtdnPushKit.NewMessageId();
        var payload = RtdnPushKit.Payload(PurchasesHostFixture.NewPlayToken(), edit: p =>
        {
            p[sentinel + "Top"] = sentinel + "payload";
            ((JsonObject)p["subscriptionNotification"]!)["sentinelInner"] = sentinel + "inner";
        });
        var bearer = fixture.Bearer();
        var body = RtdnPushKit.Envelope(payload, id, fixture.Clock.GetUtcNow(), e =>
        {
            e["unknownTop"] = sentinel + "top";
            e["message"]!["sentinelInMessage"] = sentinel + "message";
            e["message"]!["attributes"] = new JsonObject { [sentinel + "Key"] = sentinel + "value" };
            e["message"]!["orderingKey"] = sentinel + "ordering";
            e["message"]!["message_id"] = sentinel + "snake";
        }).ToJsonString();

        using var response = await RtdnPushKit.PostAsync(fixture.Client, body, bearer);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Equal(1, await fixture.CountAsync(id));
        Assert.Empty(await fixture.FindInDatabaseAsync(sentinel));
        Assert.DoesNotContain(fixture.LogSink.Entries, e => e.Contains(sentinel, StringComparison.Ordinal));
        Assert.DoesNotContain(fixture.Activities, a => a.Contains(sentinel, StringComparison.Ordinal));
        var tokenBody = bearer.Split('.')[1];
        Assert.DoesNotContain(fixture.LogSink.Entries, e => e.Contains(tokenBody, StringComparison.Ordinal));
        Assert.DoesNotContain(fixture.Activities, a => a.Contains(tokenBody, StringComparison.Ordinal));
        Assert.NotEmpty(fixture.LogSink.Entries);
        Assert.NotEmpty(fixture.Activities);
    }

    /// <summary>
    /// AC 1: a voided lifetime purchase and a voided subscription (Play reads EXPIRED) end <c>refunded</c> within one processor run, with a
    /// <c>purchase_events</c> row; a later verify that reads EXPIRED keeps <c>refunded</c> (label rule in the writer), and AC 2: the
    /// same message twice is one row and one Play read.
    /// </summary>
    [Fact]
    public async Task AVoidedPurchaseEndsRefundedAndALaterExpiredVerifyKeepsTheLabel()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        var lifetime = PurchasesHostFixture.NewPlayToken();
        var yearly = PurchasesHostFixture.NewPlayToken();
        var bound = StoreBindingRef.Compute(InstallId.Parse(installId));
        Play.Get(PlayWireMock.ProductPath(lifetime), 200, PlayWireMock.ProductBody(bound, acknowledged: true));
        Play.Get(PlayWireMock.SubscriptionPath(yearly), 200, PlayWireMock.SubscriptionBody(bound, acknowledged: true));
        using (await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Lifetime, lifetime)))
        using (await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, yearly)))
        {
        }

        Assert.Equal("active", (await fixture.RowAsync(lifetime))!.Value.State);
        fixture.Clock.Advance(TimeSpan.FromSeconds(1));
        Play.Get(PlayWireMock.ProductPath(lifetime), 200, PlayWireMock.ProductBody(bound, "CANCELLED", acknowledged: true));
        Play.Get(PlayWireMock.SubscriptionPath(yearly), 200, PlayWireMock.SubscriptionBody(bound, "SUBSCRIPTION_STATE_EXPIRED", expiry: DateTimeOffset.UtcNow.AddMinutes(-1), acknowledged: true));
        var voidedId = RtdnPushKit.NewMessageId();
        JsonObject Voided(string token) => RtdnPushKit.Payload(token, edit: p =>
        {
            p.Remove("subscriptionNotification");
            p["voidedPurchaseNotification"] = new JsonObject { ["purchaseToken"] = token, ["orderId"] = "GPA.0000-0000-0000-00000", ["productType"] = 2, ["refundType"] = 1 };
        });
        using (await fixture.PushAsync(Voided(lifetime), voidedId))
        using (await fixture.PushAsync(Voided(lifetime), voidedId))
        using (await fixture.PushAsync(Voided(yearly)))
        {
        }

        var run = await fixture.ProcessAsync();

        Assert.Equal(2, run.Applied);
        Assert.Equal("refunded", (await fixture.RowAsync(lifetime))!.Value.State);
        Assert.Equal("refunded", (await fixture.RowAsync(yearly))!.Value.State);
        Assert.Equal(2, Play.Count("GET", PlayWireMock.ProductPath(lifetime)));
        Assert.Equal(
            2,
            (await fixture.QueryAsync("SELECT count(*) FROM zaghlol.purchase_events WHERE cause = 'rtdn:VOIDED_PURCHASE' AND to_state = 'refunded' AND purchase_id IN (SELECT id FROM zaghlol.purchases WHERE store_key IN (@a, @b))", ("a", lifetime), ("b", yearly)))[0][0] is long n ? (int)n : -1);

        // The writer's label rule: verify reading EXPIRED keeps 'refunded'; an entitling read wins (Gold depends only on Play).
        fixture.Clock.Advance(TimeSpan.FromSeconds(1));
        using (await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, yearly)))
        {
        }

        Assert.Equal("refunded", (await fixture.RowAsync(yearly))!.Value.State);
        fixture.Clock.Advance(TimeSpan.FromSeconds(1));
        Play.Get(PlayWireMock.SubscriptionPath(yearly), 200, PlayWireMock.SubscriptionBody(bound, acknowledged: true));
        using (await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, yearly)))
        {
        }

        Assert.Equal("active", (await fixture.RowAsync(yearly))!.Value.State);
    }

    /// <summary>
    /// FU-092 item 9: a successor's SUBSCRIPTION_PURCHASED that beats verify is NO_PURCHASE with no Play call and no row, so verify still
    /// inserts the successor and reports a new payment.
    /// </summary>
    [Fact]
    public async Task ANotificationFirstSuccessorLeavesTheNewPaymentToVerify()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        var bound = StoreBindingRef.Compute(InstallId.Parse(installId));
        var original = PurchasesHostFixture.NewPlayToken();
        var successor = PurchasesHostFixture.NewPlayToken();
        Play.Get(PlayWireMock.SubscriptionPath(original), 200, PlayWireMock.SubscriptionBody(bound, acknowledged: true));
        using (await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, original)))
        {
        }

        var id = RtdnPushKit.NewMessageId();
        using (await fixture.PushAsync(RtdnPushKit.Payload(successor, 4), id))
        {
        }

        await fixture.ProcessAsync();

        Assert.Equal("NO_PURCHASE", (await fixture.QueryAsync("SELECT last_error FROM zaghlol.store_notifications WHERE external_id = @id", ("id", id)))[0][0]);
        Assert.Equal(0, Play.Count("GET", PlayWireMock.SubscriptionPath(successor)));
        Assert.Null(await fixture.RowAsync(successor));

        Play.Get(PlayWireMock.SubscriptionPath(successor), 200, PlayWireMock.SubscriptionBody(bound, acknowledged: true, linkedPurchaseToken: original));
        while (fixture.Grant.Results.TryDequeue(out _))
        {
        }

        using (await fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, successor)))
        {
        }

        Assert.Contains(fixture.Grant.Results, r => r.IsNewPayment && r.PredecessorPurchaseId is not null);
    }

    [Fact]
    public async Task TheRtdnBucketIsSeparateFromTheGeneralPerNetworkOne()
    {
        // The host sets notifications-google to 100 000 a minute; the general bucket is not charged by pushes (its own partition).
        for (var i = 0; i < 3; i++)
        {
            using var response = await RtdnPushKit.PostAsync(fixture.Client, "{}", fixture.Bearer());
            Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        }
    }
}
