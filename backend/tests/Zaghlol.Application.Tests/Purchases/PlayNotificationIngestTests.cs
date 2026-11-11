using System.Collections;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Purchases;

/// <summary>
/// T-133 design note §1 steps 4-7: the authenticated push is checked and only the extracted columns are stored; everything unusable is
/// acknowledged (204) without a row and counted.
/// </summary>
public class PlayNotificationIngestTests
{
    private const string Subscription = "projects/zaghlol-prod/subscriptions/rtdn-push";

    private readonly FixedClock clock = new(Play.Now);
    private readonly FakeInbox inbox = new();
    private readonly RecordingPlayTelemetry telemetry = new();

    private PlayNotificationIngest Ingest(string? subscription = null) =>
        new(Play.Catalog, new PlayRtdnSettings("https://api.zaghlol.test/v1/notifications/google", "push@zaghlol.iam.gserviceaccount.com", subscription), inbox, telemetry, clock);

    public static JsonObject Payload(Action<JsonObject>? edit = null, string token = "tok.abc-123_DEF", int type = 2)
    {
        var payload = new JsonObject
        {
            ["version"] = "1.0",
            ["packageName"] = Play.Package,
            ["eventTimeMillis"] = Play.Now.AddMinutes(-1).ToUnixTimeMilliseconds().ToString(System.Globalization.CultureInfo.InvariantCulture),
            ["subscriptionNotification"] = new JsonObject { ["version"] = "1.0", ["notificationType"] = type, ["purchaseToken"] = token, ["subscriptionId"] = Play.Yearly },
        };
        edit?.Invoke(payload);
        return payload;
    }

    public static PubSubPush Push(JsonObject payload, string? messageId = "1234567890", string? publishTime = null, string? subscription = Subscription) =>
        new(Convert.ToBase64String(Encoding.UTF8.GetBytes(payload.ToJsonString())), messageId, publishTime ?? "2026-11-11T11:59:00.123456789Z", subscription);

    [Fact]
    public async Task AGenuinePushStoresExactlyTheExtractedColumns()
    {
        var payload = Payload();
        var push = Push(payload);

        var outcome = await Ingest().IngestAsync(push, CancellationToken.None);

        Assert.Equal(PlayIngestOutcome.Stored, outcome);
        var record = Assert.Single(inbox.Rows.Values);
        Assert.Equal(PurchaseStore.GooglePlay, record.Store);
        Assert.Equal("1234567890", record.ExternalId);
        Assert.Equal("SUBSCRIPTION_RENEWED", record.Type);
        Assert.Null(record.Subtype);
        Assert.Null(record.ProductId);
        Assert.Equal("tok.abc-123_DEF", record.StoreKey!.Value.Reveal());
        Assert.Null(record.Environment);
        Assert.Equal(Play.Now.AddMinutes(-1), record.EventTime);
        Assert.Equal(SHA256.HashData(Encoding.UTF8.GetBytes(payload.ToJsonString())), record.PayloadDigest);
        Assert.False(record.Processed);
        Assert.Null(record.LastError);
        Assert.Equal(("subscription", "stored"), Assert.Single(telemetry.Ingests));
    }

    [Fact]
    public async Task TheSameMessageIdTwiceIsADuplicate()
    {
        Assert.Equal(PlayIngestOutcome.Stored, await Ingest().IngestAsync(Push(Payload()), CancellationToken.None));
        Assert.Equal(PlayIngestOutcome.Duplicate, await Ingest().IngestAsync(Push(Payload()), CancellationToken.None));
        Assert.Single(inbox.Rows);
    }

    public static TheoryData<int, string, bool> SubscriptionTypes => new()
    {
        { 1, "SUBSCRIPTION_RECOVERED", true }, { 2, "SUBSCRIPTION_RENEWED", true }, { 3, "SUBSCRIPTION_CANCELED", true },
        { 4, "SUBSCRIPTION_PURCHASED", true }, { 5, "SUBSCRIPTION_ON_HOLD", true }, { 6, "SUBSCRIPTION_IN_GRACE_PERIOD", true },
        { 7, "SUBSCRIPTION_RESTARTED", true }, { 8, "SUBSCRIPTION_PRICE_CHANGE_CONFIRMED", false }, { 9, "SUBSCRIPTION_DEFERRED", true },
        { 10, "SUBSCRIPTION_PAUSED", true }, { 11, "SUBSCRIPTION_PAUSE_SCHEDULE_CHANGED", false }, { 12, "SUBSCRIPTION_REVOKED", true },
        { 13, "SUBSCRIPTION_EXPIRED", true }, { 17, "SUBSCRIPTION_ITEMS_CHANGED", false }, { 18, "SUBSCRIPTION_CANCELLATION_SCHEDULED", false },
        { 19, "SUBSCRIPTION_PRICE_CHANGE_UPDATED", false }, { 20, "SUBSCRIPTION_PENDING_PURCHASE_CANCELED", true },
        { 22, "SUBSCRIPTION_PRICE_STEP_UP_CONSENT_UPDATED", false }, { 99, "SUBSCRIPTION_OTHER", true }, { 0, "SUBSCRIPTION_OTHER", true },
    };

    /// <summary>§1 step 6 and §3: a fixed vocabulary; types outside the reconcile set are stored processed.</summary>
    [Theory]
    [MemberData(nameof(SubscriptionTypes))]
    public async Task SubscriptionNumbersMapToAFixedVocabulary(int number, string type, bool reconcile)
    {
        await Ingest().IngestAsync(Push(Payload(type: number)), CancellationToken.None);

        var record = Assert.Single(inbox.Rows.Values);
        Assert.Equal(type, record.Type);
        Assert.Equal(!reconcile, record.Processed);
        Assert.Equal(reconcile, PlayRtdnTypes.ReconcileSet.Contains(type));
    }

    [Theory]
    [InlineData(1, "ONE_TIME_PRODUCT_PURCHASED", Play.Lifetime, Play.Lifetime)]
    [InlineData(2, "ONE_TIME_PRODUCT_CANCELED", "some_other_sku", null)]
    [InlineData(7, "ONE_TIME_PRODUCT_OTHER", Play.Lifetime, Play.Lifetime)]
    public async Task OneTimeNotificationsKeepOnlyACatalogSku(int number, string type, string sku, string? productId)
    {
        var payload = Payload(p =>
        {
            p.Remove("subscriptionNotification");
            p["oneTimeProductNotification"] = new JsonObject { ["version"] = "1.0", ["notificationType"] = number, ["purchaseToken"] = "tok.one", ["sku"] = sku };
        });

        Assert.Equal(PlayIngestOutcome.Stored, await Ingest().IngestAsync(Push(payload), CancellationToken.None));

        var record = Assert.Single(inbox.Rows.Values);
        Assert.Equal(type, record.Type);
        Assert.Equal(productId, record.ProductId);
        Assert.False(record.Processed);
    }

    [Fact]
    public async Task AVoidedPurchaseNotificationIsStoredForReRead()
    {
        var payload = Payload(p =>
        {
            p.Remove("subscriptionNotification");
            p["voidedPurchaseNotification"] = new JsonObject { ["purchaseToken"] = "tok.void", ["orderId"] = "GPA.1-2", ["productType"] = 1, ["refundType"] = 1 };
        });

        await Ingest().IngestAsync(Push(payload), CancellationToken.None);

        var record = Assert.Single(inbox.Rows.Values);
        Assert.Equal("VOIDED_PURCHASE", record.Type);
        Assert.Equal("tok.void", record.StoreKey!.Value.Reveal());
        Assert.Equal(("voided", "stored"), Assert.Single(telemetry.Ingests));
    }

    [Theory]
    [InlineData("testNotification", "TEST", "test")]
    [InlineData("pendingRefundReviewNotification", "PENDING_REFUND_REVIEW", "refund_review")]
    public async Task TestAndRefundReviewAreStoredProcessedWithoutAToken(string member, string type, string kind)
    {
        var payload = Payload(p =>
        {
            p.Remove("subscriptionNotification");
            p[member] = new JsonObject { ["version"] = "1.0", ["purchaseToken"] = "tok.never-stored" };
        });

        await Ingest().IngestAsync(Push(payload), CancellationToken.None);

        var record = Assert.Single(inbox.Rows.Values);
        Assert.Equal(type, record.Type);
        Assert.Null(record.StoreKey);
        Assert.True(record.Processed);
        Assert.Equal((kind, "stored"), Assert.Single(telemetry.Ingests));
    }

    public static TheoryData<string> Malformed => new()
    {
        "no_message_id", "message_id_with_colon", "message_id_too_long", "no_publish_time", "publish_time_no_zone", "no_data", "data_not_base64",
        "data_too_large", "data_not_json", "data_array", "two_kinds", "no_kind", "no_event_time", "event_time_negative", "no_notification_type",
        "token_with_slash", "token_missing", "token_too_long", "duplicate_member", "notification_type_string",
    };

    /// <summary>§1 step 3: every unusable authenticated message is acknowledged (no row) and counted, never 4xx.</summary>
    [Theory]
    [MemberData(nameof(Malformed))]
    public async Task AnUnusablePushIsIgnoredWithoutARow(string defect)
    {
        var push = defect switch
        {
            "no_message_id" => Push(Payload(), messageId: null),
            "message_id_with_colon" => Push(Payload(), messageId: "voided:abc"),
            "message_id_too_long" => Push(Payload(), messageId: new string('1', 101)),
            "no_publish_time" => Push(Payload()) with { PublishTime = null },
            "publish_time_no_zone" => Push(Payload(), publishTime: "2026-11-11T11:59:00"),
            "no_data" => Push(Payload()) with { Data = null },
            "data_not_base64" => Push(Payload()) with { Data = "%%%" },
            "data_too_large" => Push(Payload()) with { Data = Convert.ToBase64String(new byte[(16 * 1024) + 1]) },
            "data_not_json" => Push(Payload()) with { Data = Convert.ToBase64String("not json"u8.ToArray()) },
            "data_array" => Push(Payload()) with { Data = Convert.ToBase64String("[1,2]"u8.ToArray()) },
            "two_kinds" => Push(Payload(p => p["testNotification"] = new JsonObject())),
            "no_kind" => Push(Payload(p => p.Remove("subscriptionNotification"))),
            "no_event_time" => Push(Payload(p => p.Remove("eventTimeMillis"))),
            "event_time_negative" => Push(Payload(p => p["eventTimeMillis"] = "-5")),
            "no_notification_type" => Push(Payload(p => ((JsonObject)p["subscriptionNotification"]!).Remove("notificationType"))),
            "token_with_slash" => Push(Payload(token: "tok/../x")),
            "token_missing" => Push(Payload(p => ((JsonObject)p["subscriptionNotification"]!).Remove("purchaseToken"))),
            "token_too_long" => Push(Payload(token: new string('t', 513))),
            "duplicate_member" => Push(Payload()) with { Data = Convert.ToBase64String(Encoding.UTF8.GetBytes("{\"packageName\":\"app.zaghlol\",\"packageName\":\"app.zaghlol\",\"eventTimeMillis\":\"1\",\"testNotification\":{}}")) },
            "notification_type_string" => Push(Payload(p => ((JsonObject)p["subscriptionNotification"]!)["notificationType"] = "2")),
            _ => throw new ArgumentOutOfRangeException(nameof(defect)),
        };

        var outcome = await Ingest().IngestAsync(push, CancellationToken.None);

        Assert.Equal(PlayIngestOutcome.IgnoredMalformed, outcome);
        Assert.Empty(inbox.Rows);
        Assert.Equal(RtdnTags.IgnoredMalformed, Assert.Single(telemetry.Ingests).Outcome);
    }

    [Theory]
    [InlineData(-32 * 24 * 60 - 1, PlayIngestOutcome.IgnoredStale)]
    [InlineData(-32 * 24 * 60 + 1, PlayIngestOutcome.Stored)]
    [InlineData(4, PlayIngestOutcome.Stored)]
    [InlineData(6, PlayIngestOutcome.IgnoredStale)]
    public async Task ThePublishTimeWindowIsMinus32DaysToPlus5Minutes(int minutes, PlayIngestOutcome expected)
    {
        var time = Play.Now.AddMinutes(minutes).UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", System.Globalization.CultureInfo.InvariantCulture);

        Assert.Equal(expected, await Ingest().IngestAsync(Push(Payload(), publishTime: time), CancellationToken.None));
    }

    [Fact]
    public void TheAcceptanceWindowCoversPubSubRetentionAndStaysInsideOurs()
    {
        // FU-098 nit 5: the window is compared with the purger's own constant, not a copy.
        Assert.True(PlayNotificationIngest.MaxAge > TimeSpan.FromDays(31));
        Assert.True(PlayNotificationIngest.MaxAge < StoreNotificationSchedule.Retention);
        Assert.True(AppleNotificationIngest.MaxAge < StoreNotificationSchedule.Retention);
        Assert.Equal(TimeSpan.FromDays(Zaghlol.Application.Retention.RetentionAges.StoreNotificationsDays), StoreNotificationSchedule.Retention);
    }

    [Fact]
    public async Task AnotherPackageIsIgnoredAndPaged()
    {
        var outcome = await Ingest().IngestAsync(Push(Payload(p => p["packageName"] = "com.other.app")), CancellationToken.None);

        Assert.Equal(PlayIngestOutcome.IgnoredPackage, outcome);
        Assert.Empty(inbox.Rows);
        Assert.Equal(RtdnTags.IgnoredPackage, Assert.Single(telemetry.Ingests).Outcome);
    }

    [Fact]
    public async Task AConfiguredSubscriptionMustMatchExactly()
    {
        var ingest = Ingest(Subscription);

        Assert.Equal(PlayIngestOutcome.IgnoredSubscription, await ingest.IngestAsync(Push(Payload(), subscription: Subscription + "x"), CancellationToken.None));
        Assert.Equal(PlayIngestOutcome.IgnoredSubscription, await ingest.IngestAsync(Push(Payload(), subscription: null), CancellationToken.None));
        Assert.Equal(PlayIngestOutcome.Stored, await ingest.IngestAsync(Push(Payload()), CancellationToken.None));
    }

    [Fact]
    public async Task ANumericEventTimeIsAcceptedToo()
    {
        var millis = Play.Now.AddMinutes(-3).ToUnixTimeMilliseconds();

        await Ingest().IngestAsync(Push(Payload(p => p["eventTimeMillis"] = millis)), CancellationToken.None);

        Assert.Equal(Play.Now.AddMinutes(-3), Assert.Single(inbox.Rows.Values).EventTime);
    }

    /// <summary>AC 4 (unit level): sentinels in unknown payload members never reach the record.</summary>
    [Fact]
    public async Task UnknownPayloadMembersNeverReachTheRecord()
    {
        const string Sentinel = "ZGLSENTINELINGEST";
        var payload = Payload(p =>
        {
            p[Sentinel + "Top"] = Sentinel + "top";
            ((JsonObject)p["subscriptionNotification"]!)["extra"] = Sentinel + "inner";
        });

        await Ingest().IngestAsync(Push(payload), CancellationToken.None);

        var record = Assert.Single(inbox.Rows.Values);
        var text = string.Join("|", record.ExternalId, record.Type, record.Subtype, record.ProductId, record.StoreKey?.Reveal(), record.LastError);
        Assert.DoesNotContain(Sentinel, text, StringComparison.Ordinal);
    }

    /// <summary>AC 5: the payload DTOs list exactly the fields read and have no catch-all member of any kind.</summary>
    [Theory]
    [InlineData(typeof(DeveloperNotificationDto))]
    [InlineData(typeof(RtdnSubscriptionDto))]
    [InlineData(typeof(RtdnOneTimeDto))]
    [InlineData(typeof(RtdnVoidedDto))]
    [InlineData(typeof(RtdnPresenceDto))]
    [InlineData(typeof(PubSubPush))]
    public void ThePayloadDtosHaveNoCatchAllMember(Type type) => NoCatchAll.Assert(type);

    [Fact]
    public void ThePayloadDtosReadExactlyTheDesignedFields()
    {
        Assert.Equal(
            ["EventTimeMillis", "OneTimeProductNotification", "PackageName", "PendingRefundReviewNotification", "SubscriptionNotification", "TestNotification", "VoidedPurchaseNotification"],
            NoCatchAll.Names(typeof(DeveloperNotificationDto)));
        Assert.Equal(["NotificationType", "PurchaseToken"], NoCatchAll.Names(typeof(RtdnSubscriptionDto)));
        Assert.Equal(["NotificationType", "PurchaseToken", "Sku"], NoCatchAll.Names(typeof(RtdnOneTimeDto)));
        Assert.Equal(["PurchaseToken"], NoCatchAll.Names(typeof(RtdnVoidedDto)));
        Assert.Empty(NoCatchAll.Names(typeof(RtdnPresenceDto)));
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize("{\"packageName\":\"a\",\"packageName\":\"b\"}", RtdnJsonContext.Default.DeveloperNotificationDto));
        Assert.Null(JsonSerializer.Deserialize("{\"PackageName\":\"a\"}", RtdnJsonContext.Default.DeveloperNotificationDto)!.PackageName);
    }
}

/// <summary>The AC 5 reflection check, shared by the Google DTO tests.</summary>
internal static class NoCatchAll
{
    public static void Assert(Type type)
    {
        foreach (var property in type.GetProperties(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic))
        {
            Xunit.Assert.Null(property.GetCustomAttribute<JsonExtensionDataAttribute>());
            var t = Nullable.GetUnderlyingType(property.PropertyType) ?? property.PropertyType;
            Xunit.Assert.NotEqual(typeof(object), t);
            Xunit.Assert.NotEqual(typeof(JsonElement), t);
            Xunit.Assert.False(typeof(JsonNode).IsAssignableFrom(t), type.Name + "." + property.Name);
            Xunit.Assert.False(typeof(IDictionary).IsAssignableFrom(t), type.Name + "." + property.Name);
            Xunit.Assert.False(
                t.IsGenericType && t.GetInterfaces().Concat([t]).Any(i => i.IsGenericType && i.GetGenericTypeDefinition() == typeof(IDictionary<,>)),
                type.Name + "." + property.Name);
        }

        Xunit.Assert.DoesNotContain(
            type.GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic),
            f => !f.Name.Contains("k__BackingField", StringComparison.Ordinal) && !f.Name.StartsWith('<'));
    }

    public static string[] Names(Type type) =>
        [.. type.GetProperties(BindingFlags.Instance | BindingFlags.Public).Select(p => p.Name).Where(n => n != "EqualityContract").Order(StringComparer.Ordinal)];
}
