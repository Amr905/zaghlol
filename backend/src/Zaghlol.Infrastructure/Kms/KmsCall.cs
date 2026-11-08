using System.Security.Cryptography;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>Bounds every KMS call: 2 s per attempt and one retry by default. Results are never cached.</summary>
public sealed class KmsCallPolicy
{
    public TimeSpan Timeout { get; init; } = TimeSpan.FromSeconds(2);

    public int Attempts { get; init; } = 2;
}

internal static class KmsCall
{
    /// <summary>
    /// Runs <paramref name="call"/> under the policy. Caller cancellation propagates. Cryptographic, configuration and
    /// argument errors propagate unchanged (a retry can't fix them). Anything else, including a timeout, is retried and
    /// then becomes <see cref="KmsUnavailableException"/> without the inner exception (its text may name a key).
    /// </summary>
    public static async ValueTask<T> RunAsync<T>(
        KmsCallPolicy policy,
        TimeProvider clock,
        string operation,
        Func<CancellationToken, ValueTask<T>> call,
        CancellationToken cancellationToken)
    {
        for (var attempt = 1; ; attempt++)
        {
            using var timer = new CancellationTokenSource(policy.Timeout, clock);
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timer.Token);
            Task<T>? pending = null;
            try
            {
                pending = call(linked.Token).AsTask();

                // The adapter may not honour the token; the bound is enforced here too.
                return await pending.WaitAsync(policy.Timeout, clock, cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception ex) when (ex is CryptographicException or KmsConfigurationException or ArgumentException)
            {
                throw;
            }
#pragma warning disable CA1031 // Any adapter failure (transport, throttling, timeout) is retried once, then fails closed as 503.
            catch (Exception ex) when (IsTransient(ex))
#pragma warning restore CA1031
            {
                Observe(pending);
                if (attempt >= policy.Attempts)
                {
                    KmsMetrics.KmsUnavailable(operation);
                    throw new KmsUnavailableException();
                }
            }
        }
    }

    private static bool IsTransient(Exception ex) => ex is not (OutOfMemoryException or StackOverflowException);

    private static void Observe(Task? pending) =>
        _ = pending?.ContinueWith(
            static t => _ = t.Exception,
            CancellationToken.None,
            TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);
}
