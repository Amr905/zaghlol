using System.Globalization;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Config;
using Zaghlol.Application.Flags;

namespace Zaghlol.Application.Llm.Spend;

/// <summary>One ledger increment: the UTC day, the key and the amounts. Cost is <see cref="decimal"/> at the column scale.</summary>
public sealed record SpendRecord(DateOnly Day, LlmFeature Feature, string ProviderId, string Model, int Calls, long InputTokens, long CachedTokens, long OutputTokens, decimal CostUsd);

/// <summary><c>llm_spend_daily</c> on the App login (raw SQL; there is no EF entity for it).</summary>
public interface ISpendLedgerStore
{
    /// <summary>Upserts the (day, feature, provider, model) row, adding every amount.</summary>
    Task RecordAsync(SpendRecord record, CancellationToken cancellationToken);

    /// <summary>The summed cost of the days in <c>[fromInclusive, untilExclusive)</c> over every feature (UTC days).</summary>
    Task<decimal> TotalAsync(DateOnly fromInclusive, DateOnly untilExclusive, CancellationToken cancellationToken);

    /// <summary>
    /// Atomically claims the 80 % alert of <paramref name="monthStart"/> for <paramref name="feature"/>: <c>true</c> for exactly one caller
    /// (any process), <c>false</c> when it was claimed before. The claim is a zero-cost marker row in the ledger
    /// (provider <see cref="SpendLedgerMarkers.AlertProvider"/>) and survives restarts.
    /// </summary>
    Task<bool> TryClaimAlertAsync(LlmFeature feature, DateOnly monthStart, CancellationToken cancellationToken);
}

public static class SpendLedgerMarkers
{
    /// <summary>The provider id of the zero-cost alert marker rows; the metrics and reports skip it.</summary>
    public const string AlertProvider = "~alert80";
}

/// <summary>The settings of <see cref="SpendGuard"/>.</summary>
public sealed record SpendGuardOptions(TimeSpan CacheTtl, int MaxInputTokens, decimal WarnFraction)
{
    /// <summary>The longest question the API accepts (ask-llm.md), in characters; counted as one token per character (an upper bound for any script).</summary>
    public const int MaxQuestionChars = 300;

    /// <summary>System prompt plus the structured-output schema. The schema alone is about 14 KB (about 3.5-4.5 k tokens); 20 000 leaves more than 4 times headroom (one token per byte would be 14 k for the schema).</summary>
    public const int PromptAndSchemaTokens = 20_000;

    /// <summary>Provider-added overhead (Anthropic tool definition, Vertex wrapper).</summary>
    public const int ProviderOverheadTokens = 1_000;

    /// <summary>The input-token bound the worst case is priced with: question + prompt and schema + provider overhead (B94-m5). The output bound is the call's configured max output tokens.</summary>
    public const int DefaultMaxInputTokens = MaxQuestionChars + PromptAndSchemaTokens + ProviderOverheadTokens;

    public static SpendGuardOptions Default { get; } = new(TimeSpan.FromSeconds(60), DefaultMaxInputTokens, 0.8m);
}

/// <summary>
/// The USD spend cap of the LLM features (ask-llm.md 4.3; PO: USD 10 per month, 80 % warning, pause at 100 %, shared by Ask and
/// categorise).
/// <para>
/// <b>Clock:</b> the ledger day and the month are <b>UTC</b> (provider billing is UTC). The quota month is Africa/Cairo (T-335); the two
/// are deliberately different.
/// </para>
/// <para>
/// <b>Reserve-then-settle.</b> <see cref="ReserveAsync"/> adds the call's worst-case cost to an in-process in-flight sum and refuses
/// (<see cref="LlmServicePausedException"/>) when <c>settled month total + in-flight + worst case</c> would pass the cap; the
/// reservation is replaced by the real cost at settle. So within one process concurrent calls can never take the month more than
/// the difference between a call's worst-case and real cost past the cap (the worst case is a true upper bound), not more than
/// one call's worst case in any case. The settled total is the ledger sum cached for 60 s plus this process's own settles since
/// the refresh (counted before the write, so a refresh racing a write can only double count, which is the safe side). Residual,
/// accepted and documented: spend of <i>other</i> processes is seen within the cache TTL, so N processes can overshoot by N
/// in-flight calls plus 60 s of the other processes' spend; production runs one API process (spec 4.3 estimates this at about
/// USD 0.13 at default limits).
/// </para>
/// <para>
/// <b>Fail closed.</b> A cap, ledger read or ledger write failure pauses (never free spending): a read failure throws
/// <see cref="LlmServicePausedException"/> from <see cref="ReserveAsync"/> and makes <see cref="IsPausedAsync"/> true; a failed write
/// keeps the entry in memory (still counted) and pauses every call until a later flush writes it. An abandoned reservation (the
/// call was cancelled and nobody settled) is charged at its worst case.
/// </para>
/// </summary>
public interface ISpendGuard
{
    /// <summary>True when the month's settled spend has reached the cap, or the ledger or cap can't be read or written. Never throws except on cancellation.</summary>
    Task<bool> IsPausedAsync(CancellationToken cancellationToken);

    /// <summary>
    /// Reserves one call of <paramref name="providerId"/> with at most <paramref name="maxOutputTokens"/> output tokens.
    /// Throws <see cref="LlmServicePausedException"/> when paused. Dispose the result (settling it first with the usage).
    /// </summary>
    Task<SpendReservation> ReserveAsync(LlmFeature feature, string providerId, int maxOutputTokens, CancellationToken cancellationToken);
}

public sealed class SpendReservation : IAsyncDisposable
{
    private readonly SpendGuard guard;
    private readonly LlmFeature feature;
    private readonly string providerId;
    private readonly LlmPriceEntry price;
    private readonly decimal worstCase;
    private readonly LlmUsage worstUsage;
    private int done;

    internal SpendReservation(SpendGuard guard, LlmFeature feature, string providerId, LlmPriceEntry price, decimal worstCase, LlmUsage worstUsage)
    {
        this.guard = guard;
        this.feature = feature;
        this.providerId = providerId;
        this.price = price;
        this.worstCase = worstCase;
        this.worstUsage = worstUsage;
    }

    public decimal WorstCaseUsd => worstCase;

    /// <summary>Records the real usage (also of a failed, refused or invalid call) and releases the reservation. Call once; later calls do nothing. Never throws.</summary>
    /// <remarks>
    /// B94-M1: when the usage is unknown (zero input and output tokens: timeout, transport failure after send, a reply without a usage
    /// block) the call is charged at the reserved worst case. Only <paramref name="neverSent"/> (see <see cref="LlmResult.NeverSent"/>) settles at 0.
    /// </remarks>
    public Task SettleAsync(LlmOutcome outcome, LlmUsage usage, TimeSpan latency, bool neverSent = false) =>
        Interlocked.Exchange(ref done, 1) == 0
            ? guard.SettleAsync(feature, providerId, price, worstCase, outcome, usage, latency, worstUsage, neverSent)
            : Task.CompletedTask;

    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref done, 1) == 0)
        {
            await guard.SettleAsync(feature, providerId, price, worstCase, LlmOutcome.Upstream, worstUsage, TimeSpan.Zero, worstUsage, neverSent: false).ConfigureAwait(false);
        }
    }
}

public sealed partial class SpendGuard(
    ISpendLedgerStore ledger,
    IRemoteConfigService config,
    ILlmPriceList prices,
    IOpsAlertSink alerts,
    ILlmMetrics metrics,
    TimeProvider clock,
    ILogger<SpendGuard> logger,
    SpendGuardOptions? options = null) : ISpendGuard, IDisposable
{
    private readonly SpendGuardOptions settings = options ?? SpendGuardOptions.Default;
    private readonly object gate = new();
    private readonly SemaphoreSlim refresh = new(1, 1);
    private readonly SemaphoreSlim flush = new(1, 1);
    private readonly Queue<SpendRecord> pending = new();
    private readonly HashSet<(DateOnly Month, LlmFeature Feature)> alerted = [];

    private DateOnly cachedMonth;
    private DateTimeOffset cachedAt = DateTimeOffset.MinValue;
    private bool hasCache;
    private decimal baseTotal;
    private decimal localSettled;
    private decimal inFlight;
    private decimal cap;

    public void Dispose()
    {
        refresh.Dispose();
        flush.Dispose();
    }

    public static DateOnly MonthStart(DateTimeOffset now) => new(now.UtcDateTime.Year, now.UtcDateTime.Month, 1);

    public async Task<bool> IsPausedAsync(CancellationToken cancellationToken)
    {
        try
        {
            await EnsureFreshAsync(cancellationToken).ConfigureAwait(false);
            if (!await FlushAsync(cancellationToken).ConfigureAwait(false))
            {
                return true;
            }

            lock (gate)
            {
                return baseTotal + localSettled >= cap;
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
#pragma warning disable CA1031 // Fail closed: any ledger or config fault pauses the LLM features instead of letting them spend unmetered.
        catch (Exception)
#pragma warning restore CA1031
        {
            LogFailClosed("is_paused");
            return true;
        }
    }

    public async Task<SpendReservation> ReserveAsync(LlmFeature feature, string providerId, int maxOutputTokens, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(providerId);
        if (!prices.TryGet(providerId, out var price) || price.Prices.InPerMTok <= 0 || price.Prices.OutPerMTok <= 0)
        {
            metrics.Paused(feature, "no_price");
            throw new LlmServicePausedException();
        }

        var worst = LlmCostCalculator.WorstCase(price.Prices, settings.MaxInputTokens, maxOutputTokens);
        bool allowed;
        bool warn;
        DateOnly month;
        decimal capNow;
        decimal totalNow;
        try
        {
            await EnsureFreshAsync(cancellationToken).ConfigureAwait(false);
            if (!await FlushAsync(cancellationToken).ConfigureAwait(false))
            {
                metrics.Paused(feature, "ledger_write");
                throw new LlmServicePausedException();
            }

            lock (gate)
            {
                month = cachedMonth;
                capNow = cap;
                totalNow = baseTotal + localSettled;
                allowed = totalNow + inFlight + worst <= capNow;
                if (allowed)
                {
                    inFlight += worst;
                }

                warn = ShouldWarn(totalNow + inFlight, capNow);
            }
        }
        catch (LlmServicePausedException)
        {
            throw;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
#pragma warning disable CA1031 // Fail closed, see IsPausedAsync.
        catch (Exception)
#pragma warning restore CA1031
        {
            LogFailClosed("reserve");
            metrics.Paused(feature, "ledger_read");
            throw new LlmServicePausedException();
        }

        if (warn)
        {
            // Not tied to the caller's token: the reservation is already held and must reach a settle.
            await AlertAsync(feature, month, capNow, totalNow, CancellationToken.None).ConfigureAwait(false);
        }

        if (!allowed)
        {
            metrics.Paused(feature, "cap");
            throw new LlmServicePausedException();
        }

        return new SpendReservation(this, feature, providerId, price, worst, new LlmUsage(settings.MaxInputTokens, 0, maxOutputTokens));
    }

    internal async Task SettleAsync(LlmFeature feature, string providerId, LlmPriceEntry price, decimal reserved, LlmOutcome outcome, LlmUsage usage, TimeSpan latency, LlmUsage worstUsage, bool neverSent)
    {
        ArgumentNullException.ThrowIfNull(usage);
        if (neverSent)
        {
            usage = LlmUsage.None;
        }
        else if (usage.InputTokens <= 0 && usage.OutputTokens <= 0)
        {
            usage = worstUsage;
            LogUsageMissing(providerId);
        }

        var cost = LlmCostCalculator.Cost(usage, price.Prices);
        var now = clock.GetUtcNow();
        var record = new SpendRecord(
            DateOnly.FromDateTime(now.UtcDateTime), feature, providerId, price.Model, 1,
            Math.Max(0, usage.InputTokens), Math.Clamp(usage.CachedTokens, 0, Math.Max(0, usage.InputTokens)), Math.Max(0, usage.OutputTokens), cost);

        DateOnly month;
        decimal capNow;
        decimal totalNow;
        bool warn;
        lock (gate)
        {
            inFlight = Math.Max(0, inFlight - reserved);
            localSettled += cost;
            month = cachedMonth;
            capNow = cap;
            totalNow = baseTotal + localSettled;
            warn = hasCache && ShouldWarn(totalNow, capNow);
            pending.Enqueue(record);
        }

        metrics.ProviderCall(feature, providerId, outcome, latency, usage, cost);
        try
        {
            await FlushAsync(CancellationToken.None).ConfigureAwait(false);
            if (warn)
            {
                await AlertAsync(feature, month, capNow, totalNow, CancellationToken.None).ConfigureAwait(false);
            }
        }
#pragma warning disable CA1031 // Settling never throws: the entry stays queued (and counted) and the guard pauses until it is written.
        catch (Exception)
#pragma warning restore CA1031
        {
            LogFailClosed("settle");
        }
    }

    private bool ShouldWarn(decimal total, decimal capValue) => capValue > 0 && total >= capValue * settings.WarnFraction;

    /// <summary>Writes every queued entry; <c>false</c> when one could not be written (it stays queued, so the guard stays paused).</summary>
    private async Task<bool> FlushAsync(CancellationToken cancellationToken)
    {
        lock (gate)
        {
            if (pending.Count == 0)
            {
                return true;
            }
        }

        await flush.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            while (true)
            {
                SpendRecord? next;
                lock (gate)
                {
                    next = pending.Count > 0 ? pending.Peek() : null;
                }

                if (next is null)
                {
                    return true;
                }

                try
                {
                    await ledger.RecordAsync(next, cancellationToken).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    throw;
                }
#pragma warning disable CA1031 // Keep the entry queued and report failure; the caller fails closed.
                catch (Exception)
#pragma warning restore CA1031
                {
                    LogFailClosed("ledger_write");
                    return false;
                }

                lock (gate)
                {
                    _ = pending.Dequeue();
                }
            }
        }
        finally
        {
            _ = flush.Release();
        }
    }

    /// <summary>Loads cap and month total when the cache is older than the TTL or belongs to another UTC month. Throws on failure (nothing is cached).</summary>
    private async Task EnsureFreshAsync(CancellationToken cancellationToken)
    {
        if (IsFresh())
        {
            return;
        }

        await refresh.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (IsFresh())
            {
                return;
            }

            var now = clock.GetUtcNow();
            var month = MonthStart(now);
            var capValue = (await config.GetAsync(cancellationToken).ConfigureAwait(false)).GetDecimal(RemoteConfigKeys.LlmSpendCapUsd);
            decimal snapshot;
            decimal pendingAtSnapshot;
            lock (gate)
            {
                snapshot = localSettled;
                pendingAtSnapshot = pending.Sum(r => r.CostUsd);
            }

            var total = await ledger.TotalAsync(month, month.AddMonths(1), cancellationToken).ConfigureAwait(false);
            lock (gate)
            {
                cachedMonth = month;
                cachedAt = now;
                hasCache = true;
                // B94-m6: drop only what was counted before the read; add queued (unwritten) entries the read can't see.
                baseTotal = total + pendingAtSnapshot;
                localSettled -= snapshot;
                cap = capValue;
            }
        }
        finally
        {
            _ = refresh.Release();
        }
    }

    private bool IsFresh()
    {
        lock (gate)
        {
            var now = clock.GetUtcNow();
            return hasCache && cachedMonth == MonthStart(now) && now - cachedAt < settings.CacheTtl && now >= cachedAt;
        }
    }

    private async Task AlertAsync(LlmFeature feature, DateOnly month, decimal capValue, decimal total, CancellationToken cancellationToken)
    {
        lock (gate)
        {
            if (alerted.Contains((month, feature)))
            {
                return;
            }
        }

        try
        {
            if (!await ledger.TryClaimAlertAsync(feature, month, cancellationToken).ConfigureAwait(false))
            {
                lock (gate)
                {
                    _ = alerted.Add((month, feature));
                }

                return;
            }

            lock (gate)
            {
                _ = alerted.Add((month, feature));
            }

            var text = string.Create(
                CultureInfo.InvariantCulture,
                $"LLM spend warning: month {month:yyyy-MM} (UTC) has reached {settings.WarnFraction * 100:0} % of the USD {capValue:0.00} cap (feature {(feature == LlmFeature.Ask ? "ask" : "cat")}); spent about USD {total:0.00}. Both LLM features pause at 100 % until next month or a cap raise (llm.spend_cap_usd).");
            _ = await alerts.SendAsync(text, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
#pragma warning disable CA1031 // The alert is best effort and never fails a request.
        catch (Exception)
#pragma warning restore CA1031
        {
            LogAlertFailed();
        }
    }

    [LoggerMessage(EventId = 1, Level = LogLevel.Warning, Message = "LLM spend guard failed closed ({operation}).")]
    private partial void LogFailClosed(string operation);

    [LoggerMessage(EventId = 3, Level = LogLevel.Warning, Message = "LLM usage unknown for {providerId}; settled at the reserved worst case.")]
    private partial void LogUsageMissing(string providerId);

    [LoggerMessage(EventId = 2, Level = LogLevel.Warning, Message = "LLM spend 80 % alert could not be recorded or sent.")]
    private partial void LogAlertFailed();
}
