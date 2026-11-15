namespace Zaghlol.Application.Accounts;

/// <summary>What one retry pass did.</summary>
public sealed record AppleRevocationRetryRun(int Revoked, int Deferred, int Dropped, int GaveUp);

/// <summary>
/// One pass over <c>pending_apple_revocations</c> (the worker runs it periodically). Rows past their 30-day window are dropped first
/// ("gave up"). A due row is opened, revoked and deleted; <c>invalid_grant</c> (already revoked) counts as revoked; a failed attempt
/// is deferred with exponential back-off; a blob that no longer opens can never work and is dropped. Nothing here reads or keeps
/// anything but the sealed token and its attempt count.
/// </summary>
public sealed class AppleRevocationRetryJob(
    IPendingAppleRevocationStore store,
    IAppleTokenVault vault,
    IAppleAccountClient apple,
    TimeProvider clock)
{
    public const int BatchSize = 100;

    public async Task<AppleRevocationRetryRun> RunOnceAsync(CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow();
        var gaveUp = await store.DeleteExpiredAsync(now, cancellationToken).ConfigureAwait(false);

        int revoked = 0, deferred = 0, dropped = 0;
        foreach (var row in await store.ListDueAsync(now, BatchSize, cancellationToken).ConfigureAwait(false))
        {
            var token = await vault.OpenAsync(PendingAppleRevocationPolicy.VaultSubject, row.SealedToken, cancellationToken).ConfigureAwait(false);
            if (token is null)
            {
                await store.DeleteAsync(row.Id, cancellationToken).ConfigureAwait(false);
                dropped++;
                continue;
            }

            if (await apple.RevokeAsync(token, cancellationToken).ConfigureAwait(false) == AppleRevokeOutcome.Revoked)
            {
                await store.DeleteAsync(row.Id, cancellationToken).ConfigureAwait(false);
                revoked++;
                continue;
            }

            var attempts = row.Attempts + 1;
            await store.DeferAsync(row.Id, attempts, now + PendingAppleRevocationPolicy.DelayAfter(attempts), cancellationToken).ConfigureAwait(false);
            deferred++;
        }

        return new AppleRevocationRetryRun(revoked, deferred, dropped, gaveUp);
    }
}
