using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Zaghlol.Api.Endpoints.V1;
using Zaghlol.Infrastructure.Purchases;
using Zaghlol.Testing;
using ProblemAssert = Zaghlol.Api.Tests.Installs.Problems;

namespace Zaghlol.Api.Tests.Purchases;

/// <summary>The purchases host plus <c>POST /v1/notifications/apple</c> (T-134), with every activity of the process captured.</summary>
public class AppleNotificationHostFixture : PurchasesHostFixture
{
    private readonly ActivityListener listener;

    public AppleNotificationHostFixture()
    {
        listener = new ActivityListener
        {
            ShouldListenTo = _ => true,
            Sample = (ref ActivityCreationOptions<ActivityContext> _) => ActivitySamplingResult.AllDataAndRecorded,
            ActivityStopped = activity => Activities.Enqueue(Render(activity)),
        };
        ActivitySource.AddActivityListener(listener);
    }

    /// <summary>Every stopped activity as text: name, tags, events and their tags.</summary>
    public ConcurrentQueue<string> Activities { get; } = new();

    public async Task<HttpResponseMessage> PostAsync(string body, string contentType = "application/json", string? authorization = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, AppleNotificationEndpoints.Route);
        request.Content = new StringContent(body, Encoding.UTF8);
        request.Content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue(contentType);
        if (authorization is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", authorization);
        }

        return await Client.SendAsync(request);
    }

    public static string Body(string signedPayload) => new JsonObject { ["signedPayload"] = signedPayload }.ToJsonString();

    /// <summary>A genuinely signed REFUND-style notification for a fresh purchase, with its nested JWSs; returns the payload and IDs.</summary>
    public (string SignedPayload, string Uuid, string Original) Notification(
        string type = "REFUND",
        string? subtype = null,
        string environment = "Production",
        string productId = AppleWireMock.Yearly,
        DateTimeOffset? signedDate = null,
        Action<JsonObject>? outer = null,
        Action<JsonObject>? transaction = null,
        Action<JsonObject>? renewal = null,
        bool withTransaction = true,
        bool withData = true)
    {
        var original = AppleWireMock.NewTransactionId();
        string? signedTransaction = null;
        string? signedRenewal = null;
        if (withTransaction)
        {
            var tx = AppleTestPki.Transaction(AppleWireMock.BundleId, productId, AppleWireMock.NewTransactionId(), original, null, environment, signedDate: DateTimeOffset.UtcNow.AddMinutes(-1));
            transaction?.Invoke(tx);
            signedTransaction = Apple.Pki.Sign(tx);
            var ren = AppleTestPki.Renewal(original, productId, environment: environment);
            renewal?.Invoke(ren);
            signedRenewal = Apple.Pki.Sign(ren);
        }

        var uuid = Guid.NewGuid().ToString("D");
        var payload = AppleTestPki.Notification(type, subtype, AppleWireMock.BundleId, environment, signedTransaction, signedRenewal, signedDate ?? DateTimeOffset.UtcNow.AddMinutes(-1), uuid, withData: withData);
        outer?.Invoke(payload);
        return (Apple.Pki.Sign(payload), uuid, original);
    }

    public async Task<int> CountAsync(string uuid)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT count(*) FROM zaghlol.store_notifications WHERE external_id = @u", connection);
        command.Parameters.AddWithValue("u", uuid);
        return (int)(long)(await command.ExecuteScalarAsync())!;
    }

    public async Task<long> TotalAsync()
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT count(*) FROM zaghlol.store_notifications", connection);
        return (long)(await command.ExecuteScalarAsync())!;
    }

    /// <summary>Every text-like and bytea column of every table in the schema that contains <paramref name="needle"/>.</summary>
    public async Task<List<string>> FindInDatabaseAsync(string needle)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        var columns = new List<(string Table, string Column, string Type)>();
        await using (var list = new NpgsqlCommand(
            "SELECT c.table_name, c.column_name, c.data_type FROM information_schema.columns c JOIN information_schema.tables t "
            + "ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE' WHERE c.table_schema = 'zaghlol'",
            connection))
        await using (var reader = await list.ExecuteReaderAsync())
        {
            while (await reader.ReadAsync())
            {
                columns.Add((reader.GetString(0), reader.GetString(1), reader.GetString(2)));
            }
        }

        var hits = new List<string>();
        foreach (var (table, column, type) in columns)
        {
            var predicate = type == "bytea"
                ? $"position(convert_to(@n, 'UTF8') in \"{column}\") > 0"
                : $"position(@n in \"{column}\"::text) > 0";
            await using var probe = new NpgsqlCommand($"SELECT count(*) FROM zaghlol.\"{table}\" WHERE {predicate}", connection);
            probe.Parameters.AddWithValue("n", needle);
            if ((long)(await probe.ExecuteScalarAsync())! > 0)
            {
                hits.Add(table + "." + column);
            }
        }

        return hits;
    }

    protected override void ConfigureServices(IServiceCollection services)
    {
        base.ConfigureServices(services);
        services.AddZaghlolAppleNotificationIngest();
    }

    protected override void MapEndpoints(WebApplication application)
    {
        base.MapEndpoints(application);
        application.MapAppleNotifications();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            listener.Dispose();
        }

        base.Dispose(disposing);
    }

    private static string Render(Activity activity)
    {
        var text = new StringBuilder(activity.DisplayName).Append('|').Append(activity.OperationName);
        foreach (var tag in activity.TagObjects)
        {
            text.Append('|').Append(tag.Key).Append('=').Append(tag.Value);
        }

        foreach (var e in activity.Events)
        {
            text.Append("|event:").Append(e.Name);
            foreach (var tag in e.Tags)
            {
                text.Append('|').Append(tag.Key).Append('=').Append(tag.Value);
            }
        }

        return text.ToString();
    }
}

/// <summary>
/// T-134 end to end: <c>POST /v1/notifications/apple</c> through the real pipeline, a migrated PostgreSQL, the real JWS verifier over a
/// test PKI. Every forgery is a 401 with nothing written and no Apple call; the open envelope ignores unknown fields without storing
/// or logging them (AC 2, AC 3).
/// </summary>
[Collection(ApiHostGroup.Name)]
public class AppleNotificationEndpointTests(AppleNotificationHostFixture fixture) : IClassFixture<AppleNotificationHostFixture>
{
    private AppleWireMock Apple => fixture.Apple;

    [Fact]
    public async Task AGenuineNotificationIsStoredOnceAndAnsweredTwoHundredWithoutCallingApple()
    {
        var (payload, uuid, original) = fixture.Notification("REFUND");

        using var first = await fixture.PostAsync(AppleNotificationHostFixture.Body(payload));
        using var replay = await fixture.PostAsync(AppleNotificationHostFixture.Body(payload));

        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.Equal(HttpStatusCode.OK, replay.StatusCode);
        Assert.Empty(await first.Content.ReadAsByteArrayAsync());
        Assert.Equal(1, await fixture.CountAsync(uuid));
        Assert.Empty(Apple.Received());

        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "SELECT store, type, product_id, store_key, environment, payload_digest, processed_at, attempts FROM zaghlol.store_notifications WHERE external_id = @u",
            connection);
        command.Parameters.AddWithValue("u", uuid);
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        Assert.Equal("app_store", reader.GetString(0));
        Assert.Equal("REFUND", reader.GetString(1));
        Assert.Equal(AppleWireMock.Yearly, reader.GetString(2));
        Assert.Equal(original, reader.GetString(3));
        Assert.Equal("production", reader.GetString(4));
        Assert.Equal(SHA256.HashData(Encoding.UTF8.GetBytes(payload)), reader.GetFieldValue<byte[]>(5));
        Assert.True(reader.IsDBNull(6));
        Assert.Equal(0, reader.GetInt32(7));
    }

    [Fact]
    public async Task ATestNotificationIsStoredProcessed()
    {
        var (payload, uuid, _) = fixture.Notification("TEST", withTransaction: false);

        using var response = await fixture.PostAsync(AppleNotificationHostFixture.Body(payload));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT processed_at IS NOT NULL FROM zaghlol.store_notifications WHERE external_id = @u", connection);
        command.Parameters.AddWithValue("u", uuid);
        Assert.True((bool)(await command.ExecuteScalarAsync())!);
    }

    [Fact]
    public async Task NoDataOrAnUnknownProductIsTwoHundredAndNotStored()
    {
        var noData = fixture.Notification("RENEWAL_EXTENSION", "SUMMARY", withData: false);
        var unknown = fixture.Notification("DID_RENEW", productId: "some_other_product");

        using var a = await fixture.PostAsync(AppleNotificationHostFixture.Body(noData.SignedPayload));
        using var b = await fixture.PostAsync(AppleNotificationHostFixture.Body(unknown.SignedPayload));

        Assert.Equal(HttpStatusCode.OK, a.StatusCode);
        Assert.Equal(HttpStatusCode.OK, b.StatusCode);
        Assert.Equal(0, await fixture.CountAsync(noData.Uuid));
        Assert.Equal(0, await fixture.CountAsync(unknown.Uuid));
    }

    public static TheoryData<string> Forgeries => new()
    {
        "payload_byte", "signature_byte", "alg_none", "alg_hs256", "jwk_header", "two_certificates", "four_certificates",
        "leaf_without_oid", "self_made_root", "inner_tampered", "renewal_original", "environment_mismatch", "bundle", "version",
        "uuid", "too_old", "future", "too_long",
    };

    /// <summary>AC 2: an invalid signature (or any failed check) is 401 and nothing is stored.</summary>
    [Theory]
    [MemberData(nameof(Forgeries))]
    public async Task EveryForgeryIsUnauthorizedWithNothingStoredAndNoAppleCall(string forgery)
    {
        var before = await fixture.TotalAsync();
        var payload = Forge(forgery);

        using var response = await fixture.PostAsync(AppleNotificationHostFixture.Body(payload));

        var text = await ProblemAssert.AssertAsync(response, HttpStatusCode.Unauthorized, "UNAUTHORIZED");
        Assert.DoesNotContain("detail", text, StringComparison.Ordinal);
        Assert.Equal(before, await fixture.TotalAsync());
        Assert.Empty(Apple.Received());
    }

    [Theory]
    [InlineData("not json")]
    [InlineData("[]")]
    [InlineData("null")]
    [InlineData("{}")]
    [InlineData("{\"signedPayload\":42}")]
    [InlineData("{\"signedPayload\":\"\"}")]
    [InlineData("{\"signedPayload\":\"a.b.c\",\"signedPayload\":\"d.e.f\"}")]
    public async Task AnEnvelopeThatIsNotAnObjectWithOneStringSignedPayloadIsBadRequest(string body)
    {
        using var response = await fixture.PostAsync(body);

        await ProblemAssert.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
    }

    [Fact]
    public async Task TheBodyCapIs256KilobytesAndOnlyJsonIsAccepted()
    {
        var huge = "{\"signedPayload\":\"" + new string('a', 256 * 1024) + "\"}";

        using var tooLarge = await fixture.PostAsync(huge);
        using var notJson = await fixture.PostAsync(AppleNotificationHostFixture.Body("a.b.c"), "text/plain");

        await ProblemAssert.AssertAsync(tooLarge, HttpStatusCode.RequestEntityTooLarge, "PAYLOAD_TOO_LARGE");
        await ProblemAssert.AssertAsync(notJson, HttpStatusCode.UnsupportedMediaType, "UNSUPPORTED_MEDIA_TYPE");
    }

    [Fact]
    public async Task NoInstallTokenIsNeededAndOneSentIsIgnored()
    {
        var (payload, uuid, _) = fixture.Notification("DID_RENEW");

        using var response = await fixture.PostAsync(AppleNotificationHostFixture.Body(payload), authorization: "Bearer not-a-real-token");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(1, await fixture.CountAsync(uuid));
    }

    /// <summary>
    /// AC 3: sentinels as an unknown body field (name and value), inside the notification payload, inside <c>data</c> and inside the
    /// nested transaction payload reach no column of any table, no log line and no activity. Positive control: the row is stored.
    /// </summary>
    [Fact]
    public async Task UnknownFieldsAnywhereNeverReachTheDatabaseLogsOrSpans()
    {
        var sentinel = "ZGLSENTINEL" + Convert.ToHexString(RandomNumberGenerator.GetBytes(8));
        var (payload, uuid, _) = fixture.Notification(
            "DID_CHANGE_RENEWAL_STATUS",
            "AUTO_RENEW_DISABLED",
            outer: o =>
            {
                o["sentinelOuter"] = sentinel + "outer";
                o["data"]!["sentinelData"] = sentinel + "data";
            },
            transaction: t => t["sentinelTransaction"] = sentinel + "tx",
            renewal: r => r["sentinelRenewal"] = sentinel + "renewal");
        var body = new JsonObject
        {
            ["signedPayload"] = payload,
            ["unknownField"] = sentinel + "body",
            [sentinel + "Name"] = new JsonObject { ["nested"] = sentinel + "nested" },
        }.ToJsonString();

        using var response = await fixture.PostAsync(body);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(1, await fixture.CountAsync(uuid));
        Assert.Empty(await fixture.FindInDatabaseAsync(sentinel));
        Assert.DoesNotContain(fixture.LogSink.Entries, e => e.Contains(sentinel, StringComparison.Ordinal));
        Assert.DoesNotContain(fixture.Activities, a => a.Contains(sentinel, StringComparison.Ordinal));

        // The signed payload itself (and so the nested JWSs) is never logged or traced either.
        Assert.DoesNotContain(fixture.LogSink.Entries, e => e.Contains(payload.Split('.')[1], StringComparison.Ordinal));
        Assert.DoesNotContain(fixture.Activities, a => a.Contains(payload.Split('.')[1], StringComparison.Ordinal));
        Assert.NotEmpty(fixture.LogSink.Entries);
        Assert.NotEmpty(fixture.Activities);
    }

    private string Forge(string forgery)
    {
        var (genuine, _, _) = fixture.Notification("REFUND");
        var parts = genuine.Split('.');
        switch (forgery)
        {
            case "payload_byte":
                var body = parts[1].ToCharArray();
                body[20] = body[20] == 'A' ? 'B' : 'A';
                return parts[0] + "." + new string(body) + "." + parts[2];
            case "signature_byte":
                var signature = parts[2].ToCharArray();
                signature[3] = signature[3] == 'A' ? 'B' : 'A';
                return parts[0] + "." + parts[1] + "." + new string(signature);
            case "alg_none":
                return Resign(h => h["alg"] = "none");
            case "alg_hs256":
                return Resign(h => h["alg"] = "HS256");
            case "jwk_header":
                return Resign(h => h["jwk"] = new JsonObject { ["kty"] = "EC" });
            case "two_certificates":
                return Resign(h => h["x5c"] = new JsonArray(((JsonArray)h["x5c"]!).Take(2).Select(n => (JsonNode)n!.GetValue<string>()).ToArray()));
            case "four_certificates":
                return Resign(h =>
                {
                    var chain = ((JsonArray)h["x5c"]!).Select(n => n!.GetValue<string>()).ToList();
                    h["x5c"] = new JsonArray([.. chain.Append(chain[2]).Select(c => (JsonNode)c)]);
                });
            case "leaf_without_oid":
                return Other(AppleTestPki.Create(leafOid: false));
            case "self_made_root":
                return Other(AppleTestPki.Create(rootSubject: "CN=Zaghlol Test Root CA - G3, OU=Test Certification Authority, O=Zaghlol Tests, C=EG"));
            case "inner_tampered":
                return fixture.Notification("REFUND", outer: o =>
                {
                    var tx = o["data"]!["signedTransactionInfo"]!.GetValue<string>().Split('.');
                    var flipped = tx[2].ToCharArray();
                    flipped[4] = flipped[4] == 'A' ? 'B' : 'A';
                    o["data"]!["signedTransactionInfo"] = tx[0] + "." + tx[1] + "." + new string(flipped);
                }).SignedPayload;
            case "renewal_original":
                return fixture.Notification("REFUND", renewal: r => r["originalTransactionId"] = "2999999999999999").SignedPayload;
            case "environment_mismatch":
                return fixture.Notification("REFUND", transaction: t => t["environment"] = "Sandbox").SignedPayload;
            case "bundle":
                // Another app's genuine notification: data and transaction agree on the other bundle.
                return fixture.Notification("REFUND", outer: o => o["data"]!["bundleId"] = "com.other.app", transaction: t => t["bundleId"] = "com.other.app").SignedPayload;
            case "version":
                return fixture.Notification("REFUND", outer: o => o["version"] = "1.0").SignedPayload;
            case "uuid":
                return fixture.Notification("REFUND", outer: o => o["notificationUUID"] = "not-a-uuid").SignedPayload;
            case "too_old":
                return fixture.Notification("REFUND", signedDate: DateTimeOffset.UtcNow.AddDays(-10).AddMinutes(-1)).SignedPayload;
            case "future":
                return fixture.Notification("REFUND", signedDate: DateTimeOffset.UtcNow.AddMinutes(6)).SignedPayload;
            case "too_long":
                return genuine + new string('A', 65537 - genuine.Length);
            default:
                throw new ArgumentOutOfRangeException(nameof(forgery));
        }

        string Resign(Action<JsonObject> header)
        {
            var h = JsonNode.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(Pad(parts[0]))))!.AsObject();
            header(h);
            return Apple.Pki.Sign(h.ToJsonString(), Encoding.UTF8.GetString(Convert.FromBase64String(Pad(parts[1]))));
        }

        static string Other(AppleTestPki pki)
        {
            using (pki)
            {
                return pki.Sign(AppleTestPki.Notification("REFUND", null, AppleWireMock.BundleId));
            }
        }
    }

    private static string Pad(string base64Url)
    {
        var text = base64Url.Replace('-', '+').Replace('_', '/');
        return text + new string('=', (4 - (text.Length % 4)) % 4);
    }
}

/// <summary>AC 4 as code: the envelope DTO lists only <c>signedPayload</c>; no catch-all member of any kind (no database needed).</summary>
[Collection(ApiHostGroup.Name)]
public class AppleNotificationEnvelopeTests
{
    [Fact]
    public void TheEnvelopeDtoHasExactlyOneStringMemberAndNoCatchAll()
    {
        var properties = typeof(AppleNotificationRequest).GetProperties(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);

        var only = Assert.Single(properties);
        Assert.Equal("SignedPayload", only.Name);
        Assert.Equal(typeof(string), only.PropertyType);
        Assert.Null(only.GetCustomAttribute<JsonExtensionDataAttribute>());
        Assert.DoesNotContain(
            typeof(AppleNotificationRequest).GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic),
            f => !f.Name.Contains("k__BackingField", StringComparison.Ordinal));
    }

    [Fact]
    public void TheEnvelopeContextSkipsUnknownMembersAndRefusesDuplicates()
    {
        var parsed = JsonSerializer.Deserialize("{\"x\":{\"y\":[1,2]},\"signedPayload\":\"a.b.c\",\"z\":null}", AppleNotificationJsonContext.Default.AppleNotificationRequest);

        Assert.Equal("a.b.c", parsed!.SignedPayload);
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize("{\"signedPayload\":\"a\",\"signedPayload\":\"b\"}", AppleNotificationJsonContext.Default.AppleNotificationRequest));
        Assert.Null(JsonSerializer.Deserialize("{\"SignedPayload\":\"a.b.c\"}", AppleNotificationJsonContext.Default.AppleNotificationRequest)!.SignedPayload);
        Assert.Equal(nameof(AppleNotificationRequest), parsed.ToString());
    }
}
