using Microsoft.Extensions.Logging.Abstractions;
using Zaghlol.Application.Config;
using Zaghlol.Application.Flags;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Spend;

namespace Zaghlol.Application.Tests.Llm.Spend;

/// <summary>T-339: cost math, the 80 % alert, the pause at the cap, reserve-then-settle and fail-closed behaviour.</summary>
public class SpendGuardTests
{
    private sealed class Clock(DateTimeOffset start) : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = start;

        public override DateTimeOffset GetUtcNow() => Now;
    }

    private sealed class MemoryLedger : ISpendLedgerStore
    {
        public List<SpendRecord> Rows { get; } = [];

        public HashSet<(LlmFeature, DateOnly)> Claims { get; } = [];

        public bool FailReads { get; set; }

        public bool FailWrites { get; set; }

        public int Reads { get; private set; }

        public Task RecordAsync(SpendRecord record, CancellationToken cancellationToken)
        {
            if (FailWrites)
            {
                throw new InvalidOperationException("write");
            }

            Rows.Add(record);
            return Task.CompletedTask;
        }

        public Task<decimal> TotalAsync(DateOnly fromInclusive, DateOnly untilExclusive, CancellationToken cancellationToken)
        {
            Reads++;
            return FailReads
                ? throw new InvalidOperationException("read")
                : Task.FromResult(Rows.Where(r => r.Day >= fromInclusive && r.Day < untilExclusive).Sum(r => r.CostUsd));
        }

        public Task<bool> TryClaimAlertAsync(LlmFeature feature, DateOnly monthStart, CancellationToken cancellationToken) =>
            Task.FromResult(Claims.Add((feature, monthStart)));
    }

    private sealed class Config : IRemoteConfigService
    {
        public string? Cap { get; set; }

        public bool Fail { get; set; }

        public Task<RemoteConfigSnapshot> GetAsync(CancellationToken cancellationToken) =>
            Fail
                ? throw new InvalidOperationException("config")
                : Task.FromResult(RemoteConfigService.Build(Cap is null ? [] : [new RemoteConfigRow(RemoteConfigKeys.LlmSpendCapUsd, Cap, 1, DateTimeOffset.UnixEpoch)]));
    }

    private sealed class Alerts : IOpsAlertSink
    {
        public List<string> Sent { get; } = [];

        public Task<bool> SendAsync(string message, CancellationToken cancellationToken)
        {
            Sent.Add(message);
            return Task.FromResult(true);
        }
    }

    private sealed class Prices(LlmPrices prices) : ILlmPriceList
    {
        public bool TryGet(string providerId, out LlmPriceEntry entry)
        {
            entry = new LlmPriceEntry("model-x", prices);
            return providerId == "p1";
        }
    }

    // 1 USD per million input, 0.5 cached, 4 output: one call at 1M input + 1M output costs 5.00, which keeps the numbers readable.
    private static readonly LlmPrices Simple = new(1m, 0.5m, 4m);

    private static readonly DateTimeOffset Start = new(2026, 11, 10, 12, 0, 0, TimeSpan.Zero);

    private readonly Clock clock = new(Start);
    private readonly MemoryLedger ledger = new();
    private readonly Config config = new();
    private readonly Alerts alerts = new();

    private SpendGuard Guard(LlmPrices? prices = null, int maxInput = 1000) =>
        new(ledger, config, new Prices(prices ?? Simple), alerts, new NullLlmMetrics(), clock, NullLogger<SpendGuard>.Instance,
            SpendGuardOptions.Default with { MaxInputTokens = maxInput });

    private void Seed(decimal cost, int daysAgo = 0) =>
        ledger.Rows.Add(new SpendRecord(DateOnly.FromDateTime(clock.Now.UtcDateTime.AddDays(-daysAgo)), LlmFeature.Ask, "p1", "model-x", 1, 0, 0, 0, cost));

    private static async Task CallAsync(SpendGuard guard, LlmFeature feature, int inTokens = 100, int cached = 0, int outTokens = 10)
    {
        await using var reservation = await guard.ReserveAsync(feature, "p1", 100, CancellationToken.None);
        await reservation.SettleAsync(LlmOutcome.Ok, new LlmUsage(inTokens, cached, outTokens), TimeSpan.FromMilliseconds(5));
    }

    // AC 1: a table of the price shapes the three candidates can have (illustrative numbers, not live prices).
    [Theory]
    [InlineData(1_000_000, 0, 1_000_000, 0.15, 0.075, 0.60, "0.750000")] // cached at half the input price
    [InlineData(1_000_000, 600_000, 500_000, 0.10, 0.025, 0.40, "0.255000")] // cached at a quarter, part of the input cached
    [InlineData(1_000, 1_000, 100, 1.00, 1.00, 5.00, "0.001500")] // no cached discount, all of the input cached
    [InlineData(2_000, 0, 300, 3.00, 0.00, 15.00, "0.010500")] // free cached tokens, none used
    [InlineData(2_000, 5_000, 0, 3.00, 0.30, 15.00, "0.000600")] // cached count above the input is clamped to the input
    [InlineData(0, 0, 0, 1.00, 0.10, 2.00, "0.000000")]
    [InlineData(1, 0, 1, 0.01, 0.01, 0.01, "0.000001")] // rounds up to a micro-dollar, never down to zero
    public void CostPricesCachedTokensSeparatelyAndRoundsUp(int input, int cached, int output, double pIn, double pCached, double pOut, string expected)
    {
        var prices = new LlmPrices((decimal)pIn, (decimal)pCached, (decimal)pOut);
        Assert.Equal(decimal.Parse(expected, System.Globalization.CultureInfo.InvariantCulture), LlmCostCalculator.Cost(new LlmUsage(input, cached, output), prices));
    }

    // AC 2
    [Fact]
    public async Task TheEightyPercentAlertIsSentOncePerMonthPerFeatureAndRearmsNextMonth()
    {
        var guard = Guard();
        Seed(7.99m);
        await CallAsync(guard, LlmFeature.Ask);
        Assert.Empty(alerts.Sent);

        Seed(0.5m);
        clock.Now = Start.AddMinutes(2);
        await CallAsync(guard, LlmFeature.Ask);
        await CallAsync(guard, LlmFeature.Ask);
        Assert.Single(alerts.Sent);
        Assert.Contains("80 %", alerts.Sent[0], StringComparison.Ordinal);
        Assert.Contains("feature ask", alerts.Sent[0], StringComparison.Ordinal);

        // The other feature has its own alert; a second one for the same feature is not sent, even from a new process.
        await CallAsync(guard, LlmFeature.Categorise);
        Assert.Equal(2, alerts.Sent.Count);
        var restarted = Guard();
        clock.Now = Start.AddMinutes(4);
        await CallAsync(restarted, LlmFeature.Ask);
        Assert.Equal(2, alerts.Sent.Count);

        // Next UTC month: spend is back at zero, the alert re-arms when 80 % is crossed again.
        clock.Now = new DateTimeOffset(2026, 12, 1, 0, 5, 0, TimeSpan.Zero);
        await CallAsync(guard, LlmFeature.Ask);
        Assert.Equal(2, alerts.Sent.Count);
        Seed(9m);
        clock.Now = clock.Now.AddMinutes(2);
        await CallAsync(guard, LlmFeature.Ask);
        Assert.Equal(3, alerts.Sent.Count);
    }

    // AC 3
    [Fact]
    public async Task AtTheCapBothFeaturesPauseAndARaisedCapResumesWithinSixtySeconds()
    {
        var guard = Guard();
        Seed(10.00m);
        Assert.True(await guard.IsPausedAsync(CancellationToken.None));
        await Assert.ThrowsAsync<LlmServicePausedException>(() => guard.ReserveAsync(LlmFeature.Ask, "p1", 100, CancellationToken.None));
        await Assert.ThrowsAsync<LlmServicePausedException>(() => guard.ReserveAsync(LlmFeature.Categorise, "p1", 100, CancellationToken.None));

        config.Cap = "20.00";
        clock.Now = Start.AddSeconds(30);
        Assert.True(await guard.IsPausedAsync(CancellationToken.None)); // still the cached cap
        clock.Now = Start.AddSeconds(61);
        Assert.False(await guard.IsPausedAsync(CancellationToken.None));
        await CallAsync(guard, LlmFeature.Ask);

        // A new UTC month starts at zero without waiting for the cache.
        config.Cap = null;
        Seed(10.00m);
        clock.Now = new DateTimeOffset(2026, 12, 1, 0, 0, 1, TimeSpan.Zero);
        Assert.False(await guard.IsPausedAsync(CancellationToken.None));
    }

    [Fact]
    public async Task TheMonthIsUtcNotCairo()
    {
        // 30 Nov 22:30 UTC is 1 Dec 00:30 in Cairo (UTC+2): still November's spend.
        Seed(10m, 0);
        clock.Now = new DateTimeOffset(2026, 11, 30, 22, 30, 0, TimeSpan.Zero);
        ledger.Rows.Clear();
        ledger.Rows.Add(new SpendRecord(new DateOnly(2026, 11, 30), LlmFeature.Ask, "p1", "m", 1, 0, 0, 0, 10m));
        Assert.True(await Guard().IsPausedAsync(CancellationToken.None));
    }

    // Negative proof 1: without the reservation, a burst would all see "room left". Each reservation holds its worst case.
    [Fact]
    public async Task ConcurrentCallsNeverTakeTheMonthPastTheCapByMoreThanTheirRealCost()
    {
        // worst case per call: 1000 in * 1 + 100 out * 4 = 0.0014 USD; cap leaves room for exactly 3.
        Seed(9.9958m);
        var guard = Guard();
        var held = new List<SpendReservation>();
        var refused = 0;
        for (var i = 0; i < 10; i++)
        {
            try
            {
                held.Add(await guard.ReserveAsync(LlmFeature.Ask, "p1", 100, CancellationToken.None));
            }
            catch (LlmServicePausedException)
            {
                refused++;
            }
        }

        Assert.Equal(3, held.Count);
        Assert.Equal(7, refused);
        foreach (var reservation in held)
        {
            await reservation.SettleAsync(LlmOutcome.Ok, new LlmUsage(500, 0, 50), TimeSpan.Zero);
        }

        Assert.True(ledger.Rows.Sum(r => r.CostUsd) <= 10.00m);
    }

    [Fact]
    public async Task ParallelReservationsAreSafe()
    {
        Seed(9.9958m);
        var guard = Guard();
        var results = await Task.WhenAll(Enumerable.Range(0, 40).Select(async _ =>
        {
            try
            {
                return await guard.ReserveAsync(LlmFeature.Ask, "p1", 100, CancellationToken.None);
            }
            catch (LlmServicePausedException)
            {
                return null;
            }
        }));
        Assert.Equal(3, results.Count(r => r is not null));
        foreach (var r in results)
        {
            if (r is not null)
            {
                await r.DisposeAsync();
            }
        }
    }

    // Negative proof 2: a failed ledger read, config read or write must pause, never allow.
    [Fact]
    public async Task ALedgerOrConfigFailureFailsClosed()
    {
        var guard = Guard();
        ledger.FailReads = true;
        Assert.True(await guard.IsPausedAsync(CancellationToken.None));
        await Assert.ThrowsAsync<LlmServicePausedException>(() => guard.ReserveAsync(LlmFeature.Ask, "p1", 100, CancellationToken.None));

        ledger.FailReads = false;
        config.Fail = true;
        Assert.True(await guard.IsPausedAsync(CancellationToken.None));
        await Assert.ThrowsAsync<LlmServicePausedException>(() => guard.ReserveAsync(LlmFeature.Ask, "p1", 100, CancellationToken.None));

        config.Fail = false;
        Assert.False(await guard.IsPausedAsync(CancellationToken.None));
    }

    [Fact]
    public async Task AFailedWritePausesUntilTheEntryIsWrittenAndIsStillCounted()
    {
        var guard = Guard();
        ledger.FailWrites = true;
        await CallAsync(guard, LlmFeature.Ask, 500_000, 0, 100_000); // settle fails: queued, no exception
        Assert.Empty(ledger.Rows);
        Assert.True(await guard.IsPausedAsync(CancellationToken.None));
        await Assert.ThrowsAsync<LlmServicePausedException>(() => guard.ReserveAsync(LlmFeature.Ask, "p1", 100, CancellationToken.None));

        ledger.FailWrites = false;
        Assert.False(await guard.IsPausedAsync(CancellationToken.None));
        Assert.Single(ledger.Rows);
        Assert.Equal(0.9m, ledger.Rows[0].CostUsd);
    }

    [Fact]
    public async Task AnUnknownProviderIsPausedAndAnAbandonedReservationIsChargedAtItsWorstCase()
    {
        var guard = Guard();
        await Assert.ThrowsAsync<LlmServicePausedException>(() => guard.ReserveAsync(LlmFeature.Ask, "unknown", 100, CancellationToken.None));

        var reservation = await guard.ReserveAsync(LlmFeature.Ask, "p1", 100, CancellationToken.None);
        await reservation.DisposeAsync();
        Assert.Equal(reservation.WorstCaseUsd, Assert.Single(ledger.Rows).CostUsd);
        await reservation.SettleAsync(LlmOutcome.Ok, LlmUsage.None, TimeSpan.Zero); // a second settle is ignored
        Assert.Single(ledger.Rows);
    }

    [Fact]
    public async Task EveryProviderCallIsRecordedOnTheUtcDayWithItsFeatureProviderAndModel()
    {
        var guard = Guard();
        clock.Now = new DateTimeOffset(2026, 11, 10, 23, 59, 0, TimeSpan.Zero);
        await using var failed = await guard.ReserveAsync(LlmFeature.Categorise, "p1", 100, CancellationToken.None);
        await failed.SettleAsync(LlmOutcome.Timeout, LlmUsage.None, TimeSpan.FromSeconds(8));
        var row = Assert.Single(ledger.Rows);
        Assert.Equal((new DateOnly(2026, 11, 10), LlmFeature.Categorise, "p1", "model-x", 1, 0m), (row.Day, row.Feature, row.ProviderId, row.Model, row.Calls, row.CostUsd));
    }

    [Fact]
    public void TheCapDefaultsToTenDollarsWhenNothingIsSet()
    {
        Assert.Equal(10.00m, RemoteConfigService.Build([]).GetDecimal(RemoteConfigKeys.LlmSpendCapUsd));
    }
}
