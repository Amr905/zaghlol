using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>
/// The four fields of a Pub/Sub push envelope the server reads (T-133 design note §1 step 4): <c>message.data</c>,
/// <c>message.messageId</c>, <c>message.publishTime</c> and <c>subscription</c>. Nothing else of the envelope (<c>attributes</c>,
/// <c>orderingKey</c>, <c>deliveryAttempt</c>, unknown fields) is ever read, kept, stored or logged.
/// </summary>
public sealed record PubSubPush(string? Data, string? MessageId, string? PublishTime, string? Subscription)
{
    // Never render the payload (debuggers, accidental logging).
    public override string ToString() => nameof(PubSubPush);
}

/// <summary>
/// <c>Purchases:Google:Rtdn:*</c> (T-133 design note §1 step 2, deployment.md "RTDN push"): the push subscription's audience, its
/// push service account and, optionally, the subscription path. Values are configuration, never secrets, but never logged either.
/// </summary>
public sealed record PlayRtdnSettings(string? Audience, string? PushServiceAccount, string? Subscription)
{
    /// <summary>Both values the authentication handler needs are set (otherwise every push is 401; Production refuses to start).</summary>
    public bool IsConfigured => !string.IsNullOrEmpty(Audience) && !string.IsNullOrEmpty(PushServiceAccount);
}

/// <summary>How one authenticated push ended (<c>zaghlol.rtdn.ingest{outcome}</c>). Every outcome is answered 204.</summary>
public enum PlayIngestOutcome
{
    /// <summary>Inserted.</summary>
    Stored,

    /// <summary>The <c>messageId</c> was already stored: nothing written.</summary>
    Duplicate,

    /// <summary>The envelope or payload can't be used: acknowledged, not stored, alerted (warn).</summary>
    IgnoredMalformed,

    /// <summary><c>publishTime</c> outside <c>[now − 32 d, now + 5 min]</c>: acknowledged, not stored (warn).</summary>
    IgnoredStale,

    /// <summary>Another app's <c>packageName</c>: acknowledged, not stored, paged (configuration error).</summary>
    IgnoredPackage,

    /// <summary><c>subscription</c> differs from <c>Rtdn:Subscription</c>: acknowledged, not stored (warn).</summary>
    IgnoredSubscription,
}

/// <summary>
/// The RTDN type vocabulary (T-133 design note §1 step 6, §3): a fixed set of names, each matching the schema's
/// <c>^[A-Z0-9_]{1,64}$</c> CHECK, so nothing Google sends is ever written as a type.
/// </summary>
public static class PlayRtdnTypes
{
    public const string SubscriptionOther = "SUBSCRIPTION_OTHER";
    public const string OneTimePurchased = "ONE_TIME_PRODUCT_PURCHASED";
    public const string OneTimeCanceled = "ONE_TIME_PRODUCT_CANCELED";
    public const string OneTimeOther = "ONE_TIME_PRODUCT_OTHER";
    public const string VoidedPurchase = PlayStateMapping.VoidedPurchaseType;
    public const string Test = "TEST";
    public const string PendingRefundReview = "PENDING_REFUND_REVIEW";
    public const string SubscriptionRevoked = PlayStateMapping.SubscriptionRevokedType;
    public const string SubscriptionPendingPurchaseCanceled = "SUBSCRIPTION_PENDING_PURCHASE_CANCELED";

    /// <summary>The hourly expiry sweep's rows (never an RTDN; <c>external_id = sweep:…</c>).</summary>
    public const string ExpirySweep = "EXPIRY_SWEEP";

    /// <summary><c>subscriptionNotification.notificationType</c> numbers by RTDN name (Play "RTDN reference").</summary>
    public static IReadOnlyDictionary<int, string> SubscriptionTypes { get; } = new Dictionary<int, string>
    {
        [1] = "SUBSCRIPTION_RECOVERED",
        [2] = "SUBSCRIPTION_RENEWED",
        [3] = "SUBSCRIPTION_CANCELED",
        [4] = "SUBSCRIPTION_PURCHASED",
        [5] = "SUBSCRIPTION_ON_HOLD",
        [6] = "SUBSCRIPTION_IN_GRACE_PERIOD",
        [7] = "SUBSCRIPTION_RESTARTED",
        [8] = "SUBSCRIPTION_PRICE_CHANGE_CONFIRMED",
        [9] = "SUBSCRIPTION_DEFERRED",
        [10] = "SUBSCRIPTION_PAUSED",
        [11] = "SUBSCRIPTION_PAUSE_SCHEDULE_CHANGED",
        [12] = SubscriptionRevoked,
        [13] = "SUBSCRIPTION_EXPIRED",
        [17] = "SUBSCRIPTION_ITEMS_CHANGED",
        [18] = "SUBSCRIPTION_CANCELLATION_SCHEDULED",
        [19] = "SUBSCRIPTION_PRICE_CHANGE_UPDATED",
        [20] = SubscriptionPendingPurchaseCanceled,
        [22] = "SUBSCRIPTION_PRICE_STEP_UP_CONSENT_UPDATED",
    };

    /// <summary><c>oneTimeProductNotification.notificationType</c> numbers.</summary>
    public static IReadOnlyDictionary<int, string> OneTimeTypes { get; } = new Dictionary<int, string>
    {
        [1] = OneTimePurchased,
        [2] = OneTimeCanceled,
    };

    /// <summary>
    /// The types the worker re-reads from Play (T-133 §3): subscription 1-7, 9, 10, 12, 13, 20 and unknown numbers, the one-time
    /// types, <c>VOIDED_PURCHASE</c> and the expiry sweep. Every other type is recorded processed and ignored.
    /// </summary>
    public static IReadOnlySet<string> ReconcileSet { get; } = new HashSet<string>(StringComparer.Ordinal)
    {
        "SUBSCRIPTION_RECOVERED", "SUBSCRIPTION_RENEWED", "SUBSCRIPTION_CANCELED", "SUBSCRIPTION_PURCHASED", "SUBSCRIPTION_ON_HOLD",
        "SUBSCRIPTION_IN_GRACE_PERIOD", "SUBSCRIPTION_RESTARTED", "SUBSCRIPTION_DEFERRED", "SUBSCRIPTION_PAUSED", SubscriptionRevoked,
        "SUBSCRIPTION_EXPIRED", SubscriptionPendingPurchaseCanceled, SubscriptionOther, OneTimePurchased, OneTimeCanceled, OneTimeOther,
        VoidedPurchase, ExpirySweep,
    };

    /// <summary>
    /// The <c>type</c> metric tag: a reconcile-set name in lower case, <c>test</c> or <c>other</c> (never Google's raw values).
    /// </summary>
    public static string Tag(string? type) =>
        type is not null && ReconcileSet.Contains(type) ? type.ToLowerInvariant() : type == Test ? "test" : "other";

    public static IReadOnlyList<string> Tags { get; } =
        [.. ReconcileSet.Select(t => t.ToLowerInvariant()).Order(StringComparer.Ordinal), "test", "other"];
}

/// <summary>
/// The Google RTDN ingest (T-133 design note §1 steps 4-7), called by <c>POST /v1/notifications/google</c> only after the Pub/Sub
/// OIDC token was verified. Each step only if the previous passed; nothing is written before step 7, and nothing but the extracted
/// columns is written then. Every outcome is answered 204 (a nack would back off the whole subscription); only a database failure
/// propagates (503). The ingest never calls Play: a stolen push token can only enqueue re-reads of tokens we already store.
/// </summary>
public sealed partial class PlayNotificationIngest(
    PlayProductCatalog catalog,
    PlayRtdnSettings settings,
    IStoreNotificationInbox inbox,
    IPlayNotificationTelemetry telemetry,
    TimeProvider clock)
{
    /// <summary>
    /// The oldest acceptable <c>publishTime</c>: longer than Pub/Sub's 31-day maximum retention, so every redelivery is accepted, and
    /// shorter than the 90-day <c>store_notifications</c> retention, so every accepted redelivery still hits the dedupe key.
    /// </summary>
    public static readonly TimeSpan MaxAge = TimeSpan.FromDays(32);

    /// <summary>The furthest a <c>publishTime</c> may lie in the future.</summary>
    public static readonly TimeSpan MaxFuture = TimeSpan.FromMinutes(5);

    /// <summary>The largest decoded <c>message.data</c> (a <c>DeveloperNotification</c> is well under 1 KB).</summary>
    public const int MaxDataBytes = 16 * 1024;

    /// <summary><c>messageId</c>: no <c>:</c>, so it can never collide with the <c>voided:</c> and <c>sweep:</c> job keys.</summary>
    public const string MessageIdPattern = @"^[A-Za-z0-9_-]{1,100}\z";

    private const int MaxEncodedDataChars = ((MaxDataBytes + 2) / 3) * 4;

    /// <summary><c>zaghlol.rtdn.ingest{kind}</c> values.</summary>
    public static class Kinds
    {
        public const string Subscription = "subscription";
        public const string OneTime = "one_time";
        public const string Voided = "voided";
        public const string Test = "test";
        public const string RefundReview = "refund_review";
        public const string None = "none";

        public static IReadOnlyList<string> All { get; } = [Subscription, OneTime, Voided, Test, RefundReview, None];
    }

    public async Task<PlayIngestOutcome> IngestAsync(PubSubPush push, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(push);

        var (outcome, kind, record) = Check(push, clock.GetUtcNow());
        if (record is not null)
        {
            outcome = await inbox.TryInsertAsync(record, cancellationToken) ? PlayIngestOutcome.Stored : PlayIngestOutcome.Duplicate;
        }

        telemetry.Ingested(kind, Tag(outcome));
        return outcome;
    }

    /// <summary>An authenticated push whose body can't even be read as an envelope (too large, not JSON).</summary>
    public void Malformed() => telemetry.Ingested(Kinds.None, Tag(PlayIngestOutcome.IgnoredMalformed));

    public static string Tag(PlayIngestOutcome outcome) => outcome switch
    {
        PlayIngestOutcome.Stored => RtdnTags.Stored,
        PlayIngestOutcome.Duplicate => RtdnTags.Duplicate,
        PlayIngestOutcome.IgnoredStale => RtdnTags.IgnoredStale,
        PlayIngestOutcome.IgnoredPackage => RtdnTags.IgnoredPackage,
        PlayIngestOutcome.IgnoredSubscription => RtdnTags.IgnoredSubscription,
        _ => RtdnTags.IgnoredMalformed,
    };

    /// <summary>SHA-256 of the decoded <c>message.data</c> bytes: stable across redeliveries (the body differs by <c>deliveryAttempt</c>).</summary>
    public static byte[] Digest(ReadOnlySpan<byte> data) => SHA256.HashData(data);

    /// <summary>RFC 3339 with a <c>T</c>, seconds and a zone; up to nine fractional digits (Pub/Sub sends nanoseconds).</summary>
    internal static bool TryParsePublishTime(string? text, out DateTimeOffset value)
    {
        value = default;
        if (text is null || text.Length > 40 || !PublishTimeRegex().IsMatch(text))
        {
            return false;
        }

        // .NET reads at most seven fractional digits: drop the rest (sub-100 ns precision is irrelevant to a 32-day window).
        var dot = text.IndexOf('.', StringComparison.Ordinal);
        if (dot > 0)
        {
            var end = dot + 1;
            while (end < text.Length && char.IsAsciiDigit(text[end]))
            {
                end++;
            }

            if (end - dot - 1 > 7)
            {
                text = string.Concat(text.AsSpan(0, dot + 8), text.AsSpan(end));
            }
        }

        return DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out value);
    }

    private (PlayIngestOutcome Outcome, string Kind, StoreNotificationRecord? Record) Check(PubSubPush push, DateTimeOffset now)
    {
        var malformed = (PlayIngestOutcome.IgnoredMalformed, Kinds.None, (StoreNotificationRecord?)null);

        // 4. The envelope.
        if (push.MessageId is not { } messageId || !MessageIdRegex().IsMatch(messageId))
        {
            return malformed;
        }

        if (!TryParsePublishTime(push.PublishTime, out var publishTime))
        {
            return malformed;
        }

        if (publishTime < now - MaxAge || publishTime > now + MaxFuture)
        {
            return (PlayIngestOutcome.IgnoredStale, Kinds.None, null);
        }

        if (settings.Subscription is { Length: > 0 } expected && !string.Equals(push.Subscription, expected, StringComparison.Ordinal))
        {
            return (PlayIngestOutcome.IgnoredSubscription, Kinds.None, null);
        }

        // 5. The payload.
        if (push.Data is not { Length: > 0 and <= MaxEncodedDataChars } data)
        {
            return malformed;
        }

        var buffer = new byte[MaxDataBytes];
        if (!Convert.TryFromBase64String(data, buffer, out var length) || length == 0)
        {
            return malformed;
        }

        var bytes = buffer.AsSpan(0, length);
        DeveloperNotificationDto? notification;
        try
        {
            notification = JsonSerializer.Deserialize(bytes, RtdnJsonContext.Default.DeveloperNotificationDto);
        }
        catch (JsonException)
        {
            return malformed;
        }

        if (notification is null)
        {
            return malformed;
        }

        if (catalog.PackageName.Length == 0 || !string.Equals(notification.PackageName, catalog.PackageName, StringComparison.Ordinal))
        {
            return (PlayIngestOutcome.IgnoredPackage, Kinds.None, null);
        }

        var kinds = (notification.SubscriptionNotification is null ? 0 : 1)
            + (notification.OneTimeProductNotification is null ? 0 : 1)
            + (notification.VoidedPurchaseNotification is null ? 0 : 1)
            + (notification.TestNotification is null ? 0 : 1)
            + (notification.PendingRefundReviewNotification is null ? 0 : 1);
        if (kinds != 1 || notification.EventTimeMillis is not { } eventMillis
            || eventMillis is <= 0 or > 253402300799999L)
        {
            return malformed;
        }

        // 6. The type (a fixed vocabulary) and the purchase token.
        string kind;
        string type;
        string? token;
        string? productId = null;
        if (notification.SubscriptionNotification is { } subscription)
        {
            kind = Kinds.Subscription;
            if (subscription.NotificationType is not { } number)
            {
                return (PlayIngestOutcome.IgnoredMalformed, kind, null);
            }

            type = PlayRtdnTypes.SubscriptionTypes.TryGetValue(number, out var name) ? name : PlayRtdnTypes.SubscriptionOther;
            token = subscription.PurchaseToken;
        }
        else if (notification.OneTimeProductNotification is { } oneTime)
        {
            kind = Kinds.OneTime;
            if (oneTime.NotificationType is not { } number)
            {
                return (PlayIngestOutcome.IgnoredMalformed, kind, null);
            }

            type = PlayRtdnTypes.OneTimeTypes.TryGetValue(number, out var name) ? name : PlayRtdnTypes.OneTimeOther;
            token = oneTime.PurchaseToken;

            // Only a product of our table is ever written; anything else stays NULL (never a drop reason: the worker reads the
            // product from the stored purchase, not from the payload).
            productId = oneTime.Sku is { } sku && catalog.TryGet(sku, out _) ? sku : null;
        }
        else if (notification.VoidedPurchaseNotification is { } voided)
        {
            kind = Kinds.Voided;
            type = PlayRtdnTypes.VoidedPurchase;
            token = voided.PurchaseToken;
        }
        else if (notification.TestNotification is not null)
        {
            kind = Kinds.Test;
            type = PlayRtdnTypes.Test;
            token = null;
        }
        else
        {
            // Provisional, PO to confirm (T-133 PO question 4): a chargeback review is recorded and never answered (no ReviewRefund
            // call, which would send usage data about the user), so Google decides alone.
            kind = Kinds.RefundReview;
            type = PlayRtdnTypes.PendingRefundReview;
            token = null;
        }

        if (kind is Kinds.Subscription or Kinds.OneTime or Kinds.Voided
            && (token is null || !PlayStateMapping.IsWellFormedToken(new Sensitive<string>(token))))
        {
            return (PlayIngestOutcome.IgnoredMalformed, kind, null);
        }

        // 7. The extracted columns only.
        var reconcile = PlayRtdnTypes.ReconcileSet.Contains(type);
        var record = new StoreNotificationRecord(
            Guid.CreateVersion7(),
            PurchaseStore.GooglePlay,
            messageId,
            type,
            null,
            productId,
            token is null ? null : new Sensitive<string>(token),
            null,
            DateTimeOffset.FromUnixTimeMilliseconds(eventMillis),
            Digest(bytes),
            Processed: !reconcile,
            LastError: null);
        return (PlayIngestOutcome.Stored, kind, record);
    }

    [GeneratedRegex(MessageIdPattern, RegexOptions.CultureInvariant)]
    private static partial Regex MessageIdRegex();

    [GeneratedRegex(@"^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?([Zz]|[+-][0-9]{2}:[0-9]{2})\z", RegexOptions.CultureInvariant)]
    private static partial Regex PublishTimeRegex();
}

/// <summary>
/// The decoded <c>message.data</c> (Play "RTDN reference"). Exactly the fields read; no <c>[JsonExtensionData]</c>,
/// <c>JsonElement</c>, <c>JsonNode</c>, <c>object</c> or dictionary member (T-133 AC 5), so nothing else is ever kept. <c>version</c>
/// is not read: the worker re-reads Play and never depends on payload semantics.
/// </summary>
public sealed class DeveloperNotificationDto
{
    public string? PackageName { get; init; }

    /// <summary>Google sends a string ("long"); a JSON number is accepted too.</summary>
    [JsonNumberHandling(JsonNumberHandling.AllowReadingFromString)]
    public long? EventTimeMillis { get; init; }

    public RtdnSubscriptionDto? SubscriptionNotification { get; init; }

    public RtdnOneTimeDto? OneTimeProductNotification { get; init; }

    public RtdnVoidedDto? VoidedPurchaseNotification { get; init; }

    /// <summary>Presence only.</summary>
    public RtdnPresenceDto? TestNotification { get; init; }

    /// <summary>Presence only (chargeback review; never answered).</summary>
    public RtdnPresenceDto? PendingRefundReviewNotification { get; init; }

    public override string ToString() => nameof(DeveloperNotificationDto);
}

public sealed class RtdnSubscriptionDto
{
    public int? NotificationType { get; init; }

    public string? PurchaseToken { get; init; }

    public override string ToString() => nameof(RtdnSubscriptionDto);
}

public sealed class RtdnOneTimeDto
{
    public int? NotificationType { get; init; }

    public string? PurchaseToken { get; init; }

    public string? Sku { get; init; }

    public override string ToString() => nameof(RtdnOneTimeDto);
}

public sealed class RtdnVoidedDto
{
    public string? PurchaseToken { get; init; }

    public override string ToString() => nameof(RtdnVoidedDto);
}

/// <summary>A notification kind read for its presence only: no member at all.</summary>
public sealed class RtdnPresenceDto
{
    public override string ToString() => nameof(RtdnPresenceDto);
}

/// <summary>
/// The payload's own context (T-133 §1 step 5): unknown members skipped, duplicate members refused, case-sensitive names, numbers
/// strict except where a property allows strings.
/// </summary>
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    UnmappedMemberHandling = JsonUnmappedMemberHandling.Skip,
    NumberHandling = JsonNumberHandling.Strict,
    AllowDuplicateProperties = false,
    PropertyNameCaseInsensitive = false,
    MaxDepth = 16)]
[JsonSerializable(typeof(DeveloperNotificationDto))]
public sealed partial class RtdnJsonContext : JsonSerializerContext;
