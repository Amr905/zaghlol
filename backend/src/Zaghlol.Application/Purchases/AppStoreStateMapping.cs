namespace Zaghlol.Application.Purchases;

/// <summary>An Apple read mapped to what Zaghlol stores (T-131 design note §3 step 5).</summary>
/// <param name="State">The <c>purchases.state</c> to write; <c>null</c> when the read is outside the table: nothing is written, 502.</param>
/// <param name="ExpiresAt">The <c>expires_at</c> to write (<c>null</c> for lifetime).</param>
/// <param name="KeepStoredExpiry">Refunded or revoked: an update leaves the stored <c>expires_at</c> unchanged.</param>
public readonly record struct MappedAppleState(StoredPurchaseState? State, DateTimeOffset? ExpiresAt, bool KeepStoredExpiry)
{
    public static MappedAppleState Unknown => new(null, null, false);

    public bool IsKnown => State is not null;
}

/// <summary>
/// The one place where App Store answers become <c>purchases.state</c> (T-131 §3 step 5; T-134 reuses it). Only Apple's API copies
/// are mapped, never the app's JWS. Anything outside the table is <see cref="MappedAppleState.Unknown"/>: never a write, never a
/// grant. An entitling subscription row without its expiry is unknown too (the T-130 L-1 lesson: a NULL expiry would look like
/// lifetime).
/// </summary>
public static class AppStoreStateMapping
{
    /// <summary>Apple's subscription <c>status</c> values.</summary>
    public const int StatusActive = 1;
    public const int StatusExpired = 2;
    public const int StatusBillingRetry = 3;
    public const int StatusBillingGracePeriod = 4;
    public const int StatusRevoked = 5;

    /// <param name="status">The <c>lastTransactions[]</c> item's <c>status</c>.</param>
    /// <param name="latest">That item's verified <c>signedTransactionInfo</c> (the subscription's latest transaction).</param>
    /// <param name="renewal">That item's verified <c>signedRenewalInfo</c>.</param>
    public static MappedAppleState MapSubscription(int? status, AppleTransaction latest, AppleRenewalInfo renewal)
    {
        ArgumentNullException.ThrowIfNull(latest);
        ArgumentNullException.ThrowIfNull(renewal);

        if (status == StatusRevoked || latest.RevocationDate is not null)
        {
            // A refund carries revocationReason; a revocation without one (for example Family Sharing withdrawn) is "revoked".
            var state = latest.RevocationReason is not null ? StoredPurchaseState.Refunded : StoredPurchaseState.Revoked;
            return new(state, latest.ExpiresDate, KeepStoredExpiry: true);
        }

        return status switch
        {
            StatusActive when latest.ExpiresDate is { } expires && renewal.AutoRenewStatus == 1 => new(StoredPurchaseState.Active, expires, false),
            StatusActive when latest.ExpiresDate is { } expires && renewal.AutoRenewStatus == 0 => new(StoredPurchaseState.CanceledActive, expires, false),
            StatusBillingGracePeriod when renewal.GracePeriodExpiresDate is { } grace => new(StoredPurchaseState.InGrace, grace, false),
            StatusBillingRetry when latest.ExpiresDate is { } expires => new(StoredPurchaseState.OnHold, expires, false),
            StatusExpired when latest.ExpiresDate is { } expires => new(StoredPurchaseState.Expired, expires, false),
            _ => MappedAppleState.Unknown,
        };
    }

    /// <summary>A lifetime (non-consumable) purchase, from the verified <c>Get Transaction Info</c> copy.</summary>
    public static MappedAppleState MapLifetime(AppleTransaction transaction)
    {
        ArgumentNullException.ThrowIfNull(transaction);

        return transaction.RevocationDate is null
            ? new(StoredPurchaseState.Active, null, false)
            : new(StoredPurchaseState.Refunded, null, false);
    }
}
