using System.Net.Sockets;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Llm;

namespace Zaghlol.Infrastructure.Llm;

/// <summary>Circuit breaker thresholds (ask-llm.md §3).</summary>
public sealed record LlmGuardOptions(
    TimeSpan AttemptTimeout,
    TimeSpan TotalTimeout,
    double FailureRatio,
    int MinimumThroughput,
    TimeSpan SamplingDuration,
    int ConsecutiveFailures,
    TimeSpan BreakDuration)
{
    public static LlmGuardOptions Default { get; } = new(
        TimeSpan.FromSeconds(8), TimeSpan.FromSeconds(9), 0.5, 10, TimeSpan.FromSeconds(30), 5, TimeSpan.FromSeconds(30));
}

/// <summary>
/// The resilience of one provider (ask-llm.md §3): attempt timeout, total budget, one retry only when the connection failed before
/// anything was sent, and a circuit breaker (at least 50 % failures over 30 s with at least 10 calls, or 5 in a row, then open for
/// 30 s and one probe). An open circuit is <see cref="LlmOutcome.Upstream"/> without a call. Model answers (<see cref="LlmOutcome.Invalid"/>,
/// <see cref="LlmOutcome.Refused"/>) are not failures of the provider. The caller's own cancellation is rethrown and counts for nothing.
/// Logs carry the provider id and a fixed state word only.
/// </summary>
public sealed partial class LlmCallGuard(string providerId, LlmGuardOptions options, TimeProvider clock, ILogger logger)
{
    private readonly ILogger log = logger;
    private readonly object gate = new();
    private readonly Queue<(DateTimeOffset At, bool Failed)> window = new();
    private int consecutive;
    private DateTimeOffset? openUntil;
    private bool probeInFlight;

    public LlmCircuitState State
    {
        get
        {
            lock (gate)
            {
                return StateLocked();
            }
        }
    }

    /// <summary>Runs <paramref name="attempt"/> (one HTTP call, given a token that fires at the attempt timeout).</summary>
    public async Task<LlmResult> RunAsync(Func<CancellationToken, Task<LlmResult>> attempt, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(attempt);
        if (!TryEnter(out var isProbe))
        {
            return LlmResult.Failed(LlmOutcome.Upstream);
        }

        var recorded = false;
        try
        {
            using var total = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            total.CancelAfter(options.TotalTimeout);
            LlmResult result;
            try
            {
                result = await Attempt(attempt, total.Token, cancellationToken);
            }
            catch (ConnectFailureException)
            {
                // Nothing was sent: one more try, if the total budget allows.
                result = await Attempt(attempt, total.Token, cancellationToken);
            }

            Record(result.Outcome is LlmOutcome.Timeout or LlmOutcome.Upstream);
            recorded = true;
            return result;
        }
        catch (ConnectFailureException)
        {
            Record(failed: true);
            recorded = true;
            return LlmResult.Failed(LlmOutcome.Upstream);
        }
        finally
        {
            if (!recorded)
            {
                // The caller cancelled (or something unexpected escaped): neither a success nor a failure of the provider.
                Abandon(isProbe);
            }
        }
    }

    private async Task<LlmResult> Attempt(Func<CancellationToken, Task<LlmResult>> attempt, CancellationToken totalToken, CancellationToken callerToken)
    {
        using var attemptCts = CancellationTokenSource.CreateLinkedTokenSource(totalToken);
        attemptCts.CancelAfter(options.AttemptTimeout);
        try
        {
            return await attempt(attemptCts.Token);
        }
        catch (OperationCanceledException) when (!callerToken.IsCancellationRequested)
        {
            return LlmResult.Failed(LlmOutcome.Timeout);
        }
        catch (HttpRequestException e) when (IsConnectFailure(e))
        {
            throw new ConnectFailureException();
        }
        catch (HttpRequestException)
        {
            return LlmResult.Failed(LlmOutcome.Upstream);
        }
    }

    /// <summary>A failure to connect (refused, DNS, unreachable) happens before a byte of the request is sent.</summary>
    internal static bool IsConnectFailure(HttpRequestException e) =>
        e.HttpRequestError is HttpRequestError.NameResolutionError or HttpRequestError.ConnectionError
        || e.InnerException is SocketException { SocketErrorCode: SocketError.ConnectionRefused or SocketError.HostNotFound or SocketError.NetworkUnreachable or SocketError.HostUnreachable };

    private bool TryEnter(out bool isProbe)
    {
        lock (gate)
        {
            isProbe = false;
            switch (StateLocked())
            {
                case LlmCircuitState.Closed:
                    return true;
                case LlmCircuitState.HalfOpen when !probeInFlight:
                    probeInFlight = true;
                    isProbe = true;
                    LogHalfOpen(providerId);
                    return true;
                default:
                    return false;
            }
        }
    }

    private LlmCircuitState StateLocked()
    {
        if (openUntil is not { } until)
        {
            return LlmCircuitState.Closed;
        }

        return clock.GetUtcNow() < until ? LlmCircuitState.Open : LlmCircuitState.HalfOpen;
    }

    private void Abandon(bool isProbe)
    {
        if (isProbe)
        {
            lock (gate)
            {
                probeInFlight = false;
            }
        }
    }

    private void Record(bool failed)
    {
        lock (gate)
        {
            var now = clock.GetUtcNow();
            if (openUntil is not null)
            {
                // The half-open probe finished: success closes the circuit, failure re-opens it.
                probeInFlight = false;
                if (failed)
                {
                    Open(now);
                }
                else
                {
                    openUntil = null;
                    consecutive = 0;
                    window.Clear();
                    LogClosed(providerId);
                }

                return;
            }

            window.Enqueue((now, failed));
            while (window.Count > 0 && now - window.Peek().At > options.SamplingDuration)
            {
                window.Dequeue();
            }

            consecutive = failed ? consecutive + 1 : 0;
            var failures = window.Count(w => w.Failed);
            if (failed
                && (consecutive >= options.ConsecutiveFailures
                    || (window.Count >= options.MinimumThroughput && failures >= options.FailureRatio * window.Count)))
            {
                Open(now);
            }
        }
    }

    private void Open(DateTimeOffset now)
    {
        openUntil = now + options.BreakDuration;
        consecutive = 0;
        window.Clear();
        LogOpened(providerId);
    }

    [LoggerMessage(EventId = 1, Level = LogLevel.Information, Message = "LLM circuit for {ProviderId} half-open: probing.")]
    private partial void LogHalfOpen(string providerId);

    [LoggerMessage(EventId = 2, Level = LogLevel.Information, Message = "LLM circuit for {ProviderId} closed.")]
    private partial void LogClosed(string providerId);

    [LoggerMessage(EventId = 3, Level = LogLevel.Warning, Message = "LLM circuit for {ProviderId} opened.")]
    private partial void LogOpened(string providerId);

    private sealed class ConnectFailureException : Exception;
}

public enum LlmCircuitState
{
    Closed,
    Open,
    HalfOpen,
}
