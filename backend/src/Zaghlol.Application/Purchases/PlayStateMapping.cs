using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>A Play read mapped to what Zaghlol stores and answers (T-130 design note §1 step 4).</summary>
/// <param name="State">The <c>purchases.state</c> to write; <c>null</c> when nothing may be written.</param>
/// <param name="Status">The verify status.</param>
/// <param name="Outcome">Whether the read is usable.</param>
public readonly record struct MappedPlayState(StoredPurchaseState? State, VerifyStatus Status, PlayReadOutcome Outcome);

public enum PlayReadOutcome
{
    /// <summary>A known state: write <see cref="MappedPlayState.State"/>.</summary>
    Known,

    /// <summary><c>SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED</c>: the pending payment never completed.</summary>
    PendingPurchaseCanceled,

    /// <summary>An unknown or unspecified state: never written, never a grant (<c>502</c>).</summary>
    Unknown,
}

/// <summary>The one place where Play states become <c>purchases.state</c> and a verify status (shared by verify and the sweeper).</summary>
public static partial class PlayStateMapping
{
    /// <summary>
    /// The token shape the server accepts before any Play call (the <c>store_key</c> limit is 512). At least one letter or digit,
    /// so a token can never be a <c>.</c> or <c>..</c> path segment (escaping leaves dots as they are).
    /// </summary>
    public const string TokenPattern = @"^(?=[A-Za-z0-9._-]*[A-Za-z0-9])[A-Za-z0-9._-]{1,512}\z";

    /// <summary>Play order IDs (<c>GPA.1234-5678-9012-34567</c>, renewals <c>..0</c>): a conservative shape, checked before any call.</summary>
    public const string OrderIdPattern = @"^(?=[A-Za-z0-9._-]*[A-Za-z0-9])[A-Za-z0-9._-]{1,64}\z";

    public const int MaxTokenLength = 512;

    public static bool IsWellFormedToken(Sensitive<string> token) =>
        token.Reveal() is { Length: > 0 and <= MaxTokenLength } text && Token().IsMatch(text);

    public static bool IsWellFormedOrderId(Sensitive<string> orderId) => orderId.Reveal() is { } text && OrderId().IsMatch(text);

    /// <remarks>
    /// An active, in-grace or cancelled subscription without a readable <c>expiryTime</c> is <see cref="PlayReadOutcome.Unknown"/>
    /// (502, nothing written): a subscription row with a NULL expiry would look like a lifetime purchase (T-130 security L-1).
    /// </remarks>
    public static MappedPlayState Map(PlaySubscriptionState state, DateTimeOffset? expiryTime, DateTimeOffset now) => state switch
    {
        PlaySubscriptionState.Active when expiryTime is not null => Known(StoredPurchaseState.Active, VerifyStatus.Active),
        PlaySubscriptionState.InGracePeriod when expiryTime is not null => Known(StoredPurchaseState.InGrace, VerifyStatus.Active),

        // Cancelled but paid until expiryTime: keeps Gold until then (backend-api §4.3 step 3, Lead decision 2026-11-11).
        PlaySubscriptionState.Canceled when expiryTime is { } expiry && expiry > now => Known(StoredPurchaseState.CanceledActive, VerifyStatus.Active),
        PlaySubscriptionState.Canceled when expiryTime is not null => Known(StoredPurchaseState.Expired, VerifyStatus.Expired),
        PlaySubscriptionState.Active or PlaySubscriptionState.InGracePeriod or PlaySubscriptionState.Canceled => new(null, VerifyStatus.Invalid, PlayReadOutcome.Unknown),
        PlaySubscriptionState.Pending => Known(StoredPurchaseState.Pending, VerifyStatus.Pending),
        PlaySubscriptionState.OnHold => Known(StoredPurchaseState.OnHold, VerifyStatus.Expired),
        PlaySubscriptionState.Paused => Known(StoredPurchaseState.Paused, VerifyStatus.Expired),
        PlaySubscriptionState.Expired => Known(StoredPurchaseState.Expired, VerifyStatus.Expired),
        PlaySubscriptionState.PendingPurchaseCanceled => new(null, VerifyStatus.Invalid, PlayReadOutcome.PendingPurchaseCanceled),
        _ => new(null, VerifyStatus.Invalid, PlayReadOutcome.Unknown),
    };

    public static MappedPlayState Map(PlayProductState state) => state switch
    {
        PlayProductState.Purchased => Known(StoredPurchaseState.Active, VerifyStatus.Active),
        PlayProductState.Pending => Known(StoredPurchaseState.Pending, VerifyStatus.Pending),
        PlayProductState.Cancelled => Known(StoredPurchaseState.Refunded, VerifyStatus.Refunded),
        _ => new(null, VerifyStatus.Invalid, PlayReadOutcome.Unknown),
    };

    /// <summary>The RTDN type whose <c>expired</c> read is labelled <c>refunded</c> (T-133 §3 step 6).</summary>
    public const string VoidedPurchaseType = "VOIDED_PURCHASE";

    /// <summary>The RTDN type whose <c>expired</c> read is labelled <c>revoked</c> (T-133 §3 step 6).</summary>
    public const string SubscriptionRevokedType = "SUBSCRIPTION_REVOKED";

    /// <summary>
    /// The Google label rule (T-133 design note §3 step 6, backend-schema <c>purchases.state</c>), applied under the row lock by every
    /// Google writer (RTDN worker, verify, restore, the acknowledge sweeper). Play never says "refunded" for a subscription, so:
    /// <list type="bullet">
    /// <item>any read other than <c>expired</c> (an entitling one in particular) is written as read: Gold depends only on Play;</item>
    /// <item>an <c>expired</c> read becomes <c>refunded</c> for a <c>VOIDED_PURCHASE</c> and <c>revoked</c> for a
    /// <c>SUBSCRIPTION_REVOKED</c>;</item>
    /// <item>otherwise an <c>expired</c> read keeps a stored <c>refunded</c>/<c>revoked</c>, so a later plain read can't erase the label.</item>
    /// </list>
    /// The label only chooses between two non-entitling states.
    /// <para>Provisional, PO to confirm (T-133 PO question 3): a refund without revoke keeps Gold until Play ends the subscription, and
    /// Gold returns when Play later reports the purchase entitling again. This method and the processor's refund floor are the
    /// decision points.</para>
    /// </summary>
    /// <param name="stored">The locked row's state, or <c>null</c> for an insert.</param>
    /// <param name="read">Play's mapped answer.</param>
    /// <param name="notificationType">The RTDN type that triggered the read, or <c>null</c> (verify, restore, sweeper).</param>
    public static StoredPurchaseState Settle(StoredPurchaseState? stored, StoredPurchaseState read, string? notificationType)
    {
        if (read != StoredPurchaseState.Expired)
        {
            return read;
        }

        return notificationType switch
        {
            VoidedPurchaseType => StoredPurchaseState.Refunded,
            SubscriptionRevokedType => StoredPurchaseState.Revoked,
            _ when stored is StoredPurchaseState.Refunded or StoredPurchaseState.Revoked => stored.Value,
            _ => StoredPurchaseState.Expired,
        };
    }

    /// <summary>The states that grant Gold (<c>v_entitlements</c>).</summary>
    public static bool IsEntitling(StoredPurchaseState state) =>
        state is StoredPurchaseState.Active or StoredPurchaseState.InGrace or StoredPurchaseState.CanceledActive;

    /// <summary>The verify status a stored state stands for (used when a newer read already updated the row).</summary>
    public static VerifyStatus StatusOf(StoredPurchaseState state) => state switch
    {
        StoredPurchaseState.Active or StoredPurchaseState.InGrace or StoredPurchaseState.CanceledActive => VerifyStatus.Active,
        StoredPurchaseState.Pending => VerifyStatus.Pending,
        StoredPurchaseState.Refunded or StoredPurchaseState.Revoked => VerifyStatus.Refunded,
        _ => VerifyStatus.Expired,
    };

    /// <summary>The states in which a Google purchase must be acknowledged (pending ones start their 3-day clock later).</summary>
    public static bool IsAckable(StoredPurchaseState state) =>
        state is StoredPurchaseState.Active or StoredPurchaseState.InGrace or StoredPurchaseState.CanceledActive;

    /// <summary>Constant-time equality of two values of possibly different length (only the length leaks).</summary>
    public static bool FixedTimeEquals(string? left, string? right)
    {
        if (left is null || right is null)
        {
            return false;
        }

        var a = Encoding.UTF8.GetBytes(left);
        var b = Encoding.UTF8.GetBytes(right);
        return a.Length == b.Length && CryptographicOperations.FixedTimeEquals(a, b);
    }

    private static MappedPlayState Known(StoredPurchaseState state, VerifyStatus status) => new(state, status, PlayReadOutcome.Known);

    [GeneratedRegex(TokenPattern, RegexOptions.CultureInvariant)]
    private static partial Regex Token();

    [GeneratedRegex(OrderIdPattern, RegexOptions.CultureInvariant)]
    private static partial Regex OrderId();
}
