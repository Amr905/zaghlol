using System.Collections.Concurrent;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Application.Purchases.Restore;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.Purchases;

/// <summary>
/// 10 restore attempts per rolling 24 h per purchase across all installs (backend-api §1), in process memory like the other
/// rate-limit buckets: with N API instances the effective limit is up to N times higher (the same accepted residual as
/// <c>RateLimits</c>). Keys are SHA-256 digests held only in memory, never logged. Bounded: expired entries are dropped as the map
/// grows, and past <see cref="MaxKeys"/> live keys a new purchase is refused (fail closed) rather than evicting a counted one.
/// </summary>
public sealed class RestoreAttemptLimiter(TimeProvider clock) : IRestoreAttemptLimiter
{
    public const int MaxKeys = 200_000;
    private static readonly TimeSpan Window = TimeSpan.FromHours(24);

    private readonly ConcurrentDictionary<string, Queue<DateTimeOffset>> attempts = new(StringComparer.Ordinal);

    public bool TryAcquire(ReadOnlySpan<byte> purchaseKey)
    {
        var now = clock.GetUtcNow();
        var key = Convert.ToBase64String(purchaseKey);
        if (attempts.Count >= MaxKeys)
        {
            Prune(now);
            if (attempts.Count >= MaxKeys && !attempts.ContainsKey(key))
            {
                return false;
            }
        }

        var queue = attempts.GetOrAdd(key, static _ => new Queue<DateTimeOffset>());
        lock (queue)
        {
            while (queue.Count > 0 && queue.Peek() <= now - Window)
            {
                queue.Dequeue();
            }

            if (queue.Count >= IRestoreAttemptLimiter.AttemptsPerDay)
            {
                return false;
            }

            queue.Enqueue(now);
            return true;
        }
    }

    private void Prune(DateTimeOffset now)
    {
        foreach (var (key, queue) in attempts)
        {
            bool expired;
            lock (queue)
            {
                expired = queue.Count == 0 || queue.Last() <= now - Window;
            }

            if (expired)
            {
                attempts.TryRemove(key, out _);
            }
        }
    }
}

internal sealed class RestoreTelemetry(ZaghlolMetrics metrics) : IRestoreTelemetry
{
    public void AttestationFailed(string platform, string reason) => metrics.AttestationFailed(platform, reason);

    public void MoveCooldownRefused() => metrics.MoveCooldownRefused("restore");
}

public static class RestoreServiceCollectionExtensions
{
    /// <summary>
    /// <c>POST /v1/purchases/restore</c> (T-185): the per-purchase limiter, the telemetry and <see cref="RestoreService"/> (transient,
    /// it holds the transient attestation and store clients). Call after <c>AddZaghlolPurchaseVerification</c>,
    /// <c>AddZaghlolAttestation</c>, <c>AddZaghlolSeats</c>, <c>AddZaghlolSeatKeys</c> and <c>AddZaghlolEntitlements</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolRestore(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton<ZaghlolMetrics>();
        services.TryAddSingleton<IRestoreAttemptLimiter, RestoreAttemptLimiter>();
        services.TryAddSingleton<IRestoreTelemetry, RestoreTelemetry>();
        services.TryAddTransient<RestoreService>();
        return services;
    }
}
