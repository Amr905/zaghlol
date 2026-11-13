namespace Zaghlol.Application.Purchases.Restore;

/// <summary>
/// The per-purchase restore limit (backend-api §1 "Rate limits"): 10 attempts per rolling 24 h for one purchase across all installs,
/// keyed by SHA-256 of the Play token or the App Store <c>originalTransactionId</c>. The key is never logged.
/// </summary>
public interface IRestoreAttemptLimiter
{
    public const int AttemptsPerDay = 10;

    /// <summary>Counts one attempt and returns true while the purchase is within its limit; a refused attempt isn't counted.</summary>
    bool TryAcquire(ReadOnlySpan<byte> purchaseKey);
}

/// <summary>Restore metrics: fixed tag words only (no IDs, tokens or hashes).</summary>
public interface IRestoreTelemetry
{
    /// <param name="platform"><see cref="RestorePlatforms"/>.</param>
    /// <param name="reason">An <c>AttestationCodes</c> word.</param>
    void AttestationFailed(string platform, string reason);

    /// <summary>One item refused by the 30-day cooldown (<c>zaghlol.seat.move_cooldown_refused{channel=restore}</c>).</summary>
    void MoveCooldownRefused();
}
