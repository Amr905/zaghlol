using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>The store a purchase belongs to (<c>purchases.store</c>).</summary>
public enum PurchaseStore
{
    GooglePlay,
    AppStore,
}

/// <summary><c>purchases.plan</c>.</summary>
public enum GoldPlan
{
    Monthly,
    Yearly,
    Lifetime,
}

/// <summary><c>purchases.environment</c>: a license-tester or StoreKit sandbox purchase is recorded as <see cref="Sandbox"/>.</summary>
public enum PurchaseEnvironment
{
    Production,
    Sandbox,
}

/// <summary><c>purchases.state</c> (backend-schema §2), the stored lifecycle state of a purchase.</summary>
public enum StoredPurchaseState
{
    Pending,
    Active,
    InGrace,
    OnHold,
    Paused,

    /// <summary>Cancelled by the user but paid until <c>expires_at</c>: still entitles (backend-api §4.3 step 3).</summary>
    CanceledActive,
    Expired,
    Refunded,
    Revoked,
}

/// <summary>The <c>status</c> of a verify answer (OpenAPI <c>PurchaseStatus</c>, verify subset).</summary>
public enum VerifyStatus
{
    Active,
    Pending,
    Expired,
    Refunded,
    Invalid,
}

/// <summary>
/// Whether the store-side binding (<see cref="StoreBindingRef"/>) must name the caller. <see cref="Skip"/> is used only by
/// restore (T-185), whose proof of ownership is device attestation, because the binding names the old install after a phone
/// change.
/// </summary>
public enum BindingCheck
{
    RequireCaller,
    Skip,
}

/// <summary>An Android purchase as the app sent it. The token is a bearer-like secret: never logged or put in a message.</summary>
public sealed record StorePurchaseRef(string ProductId, Sensitive<string> PurchaseToken);

/// <summary>
/// The outcome of a store verification (T-130 design note §0). Store failures are never a value: they throw
/// <see cref="StoreUnavailableException"/>.
/// </summary>
/// <param name="Status">The verify status; <see cref="VerifyStatus.Invalid"/> always carries <paramref name="ProblemCode"/>.</param>
/// <param name="ProblemCode"><c>PURCHASE_TOKEN_INVALID</c>, <c>PURCHASE_NOT_OWNED</c>, <c>PURCHASE_WRONG_APP</c> or <c>null</c>.</param>
/// <param name="PurchaseId">The upserted <c>purchases</c> row; <c>null</c> when nothing was written.</param>
/// <param name="PredecessorPurchaseId">The known purchase that Play's <c>linkedPurchaseToken</c> names (T-184's "new payment" rule).</param>
public sealed record StoreVerificationResult(
    VerifyStatus Status,
    string? ProblemCode,
    Guid? PurchaseId,
    GoldPlan Plan,
    DateTimeOffset? ExpiresAt,
    PurchaseEnvironment Environment,
    Guid? PredecessorPurchaseId,
    bool Acknowledged)
{
    public static StoreVerificationResult Rejected(string problemCode, GoldPlan plan = GoldPlan.Monthly) =>
        new(VerifyStatus.Invalid, problemCode, null, plan, null, PurchaseEnvironment.Production, null, false);
}

/// <summary>Verifies a purchase with one store. T-130 registers Google Play; T-131 adds the App Store.</summary>
public interface IStoreVerification
{
    PurchaseStore Store { get; }

    Task<StoreVerificationResult> VerifyAsync(StorePurchaseRef purchase, InstallId caller, BindingCheck binding, CancellationToken cancellationToken);
}

/// <summary>The caller of a verify, for the seat decision and the entitlement (T-132, T-184).</summary>
/// <param name="AccountToken">The <c>Zaghlol-Account</c> header, unverified; T-132 decides what it proves.</param>
public sealed record VerifyContext(InstallId Install, Sensitive<string>? AccountToken, DateTimeOffset Now);

/// <summary>The grant part of a verify 200 (OpenAPI <c>PurchaseVerifyResponse</c> minus <c>status</c>, time and nonce).</summary>
public sealed record VerifyGrantResult(Sensitive<string>? EntitlementToken, bool SeatHeldElsewhere, bool AccountRequired, DateTimeOffset? NextMoveAt)
{
    public static VerifyGrantResult None { get; } = new(null, false, false, null);
}

/// <summary>
/// Seat at verify and the signed entitlement (T-132 through T-184). Called only for a verified purchase that was written
/// (<see cref="StoreVerificationResult.PurchaseId"/> set); it must never turn a valid payment into an error (BR-GOLD-06).
/// </summary>
public interface IVerifyGrant
{
    Task<VerifyGrantResult> ComposeAsync(StoreVerificationResult verification, VerifyContext context, CancellationToken cancellationToken);
}

/// <summary>
/// The T-130 placeholder: no entitlement and no seat change, like T-128's <c>NullSyncEntitlementBlock</c>. Production refuses
/// to start while it is registered (<c>PurchasesStartupCheck</c>), so verify can't ship without T-132.
/// </summary>
public sealed class NullVerifyGrant : IVerifyGrant
{
    public Task<VerifyGrantResult> ComposeAsync(StoreVerificationResult verification, VerifyContext context, CancellationToken cancellationToken) =>
        Task.FromResult(VerifyGrantResult.None);
}

/// <summary>Which answer a store failure gets.</summary>
public enum StoreFailureKind
{
    /// <summary>The store failed, timed out, refused our credential or the circuit is open: <c>502 STORE_UNAVAILABLE</c>.</summary>
    Store,

    /// <summary>Our own outbound budget is exhausted: <c>503 UPSTREAM_UNAVAILABLE</c>.</summary>
    Budget,
}

/// <summary>A store call failed in a way that says nothing about the purchase. Nothing was granted or written.</summary>
public sealed class StoreUnavailableException : SafeException
{
    public const string DefaultMessage = "The store could not be reached or answered with an error; nothing was granted.";

    public StoreUnavailableException()
        : this(StoreFailureKind.Store, 30)
    {
    }

    public StoreUnavailableException(StoreFailureKind kind, int retryAfterSeconds, Exception? innerException = null)
        : base(DefaultMessage, innerException!)
    {
        Kind = kind;
        RetryAfterSeconds = Math.Max(1, retryAfterSeconds);
    }

    public StoreUnavailableException(string message)
        : base(message)
    {
    }

    public StoreUnavailableException(string message, Exception innerException)
        : base(message, innerException)
    {
    }

    public StoreFailureKind Kind { get; }

    public int RetryAfterSeconds { get; } = 30;
}

/// <summary>Metric tag values of purchases (fixed sets; never a token, order ID, install ID or product text).</summary>
public static class PurchaseTags
{
    public const string GooglePlay = "google_play";
    public const string AppStore = "app_store";

    public const string Success = "success";
    public const string Failure = "failure";
    public const string NoCode = "none";

    public const string ChannelVerify = "verify";
    public const string ChannelSweeper = "sweeper";

    public const string AckAcked = "acked";
    public const string AckAlready = "already";
    public const string AckFailed = "failed";
    public const string AckNotAckable = "not_ackable";

    public const string PathOrders = "orders";
    public const string PathFallback = "fallback";

    public static IReadOnlyList<string> Stores { get; } = [GooglePlay, AppStore];

    public static IReadOnlyList<string> VerifyOutcomes { get; } = [Success, Failure];

    public static IReadOnlyList<string> AckChannels { get; } = [ChannelVerify, ChannelSweeper];

    public static IReadOnlyList<string> AckOutcomes { get; } = [AckAcked, AckAlready, AckFailed, AckNotAckable];

    public static IReadOnlyList<string> OwnershipPaths { get; } = [PathOrders, PathFallback];

    public static string StoreName(PurchaseStore store) => store == PurchaseStore.GooglePlay ? GooglePlay : AppStore;
}

/// <summary>Purchase metrics and the 48 h alert, as the Application sees them (implemented over <c>ZaghlolMetrics</c>).</summary>
public interface IPurchaseTelemetry
{
    /// <param name="code">An <c>ErrorCodes</c> constant or <see cref="PurchaseTags.NoCode"/>.</param>
    void Verified(string store, string outcome, string code);

    /// <param name="channel"><see cref="PurchaseTags.ChannelVerify"/> or <see cref="PurchaseTags.ChannelSweeper"/>.</param>
    /// <param name="outcome">One of <see cref="PurchaseTags.AckOutcomes"/>.</param>
    void Acknowledged(string channel, string outcome);

    void TimeToAck(TimeSpan sincePurchase);

    /// <summary>The unacknowledged-purchase gauge, recomputed by each sweeper run.</summary>
    void SetUnacked(long lessThan48h, long atLeast48h, TimeSpan oldestAge);

    /// <summary>One <c>audit_alert</c> for a purchase unacknowledged for 48 h or more (purchase UUID only).</summary>
    void UnackedOver48h(Guid purchaseId);

    /// <param name="path"><see cref="PurchaseTags.PathOrders"/> or <see cref="PurchaseTags.PathFallback"/>.</param>
    void OwnershipChecked(string path, OwnershipOutcome outcome);
}

/// <summary>The support ownership check result (backend-api §5.3 <c>ownership_outcome</c>).</summary>
public enum OwnershipOutcome
{
    Pass,
    Fail,
    Unavailable,
}
