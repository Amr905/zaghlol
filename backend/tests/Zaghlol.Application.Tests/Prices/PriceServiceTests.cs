using Zaghlol.Application.Prices;

namespace Zaghlol.Application.Tests.Prices;

/// <summary>Acceptance: override vs feed with a frozen clock, stale after 24 h, expiry defaults and the 7-day cap.</summary>
public class PriceServiceTests
{
    private static readonly DateTimeOffset T0 = new(2026, 11, 10, 9, 0, 0, TimeSpan.Zero);
    private static readonly Guid Operator = Guid.Parse("00000000-0000-4000-8000-0000000000aa");

    private readonly TestClock clock = new(T0);
    private readonly MemoryPriceStore store = new();

    private PriceOverrideService Overrides => new(store, clock);

    private static NormalizedPrices Feed(decimal gold24Egp, decimal usdEgp = 50m) =>
        PriceNormalizer.Normalize([("fake", new ProviderSnapshot([new GoldQuote("XAU24_G", "EGP", gold24Egp)], [new FxQuote("EGP", usdEgp)], T0))]);

    private async Task<PricesBlock> BlockAsync() => (await new PriceReadService(store, clock).GetBlockAsync(CancellationToken.None))!;

    private static string Egp21(PricesBlock block) =>
        PriceWire.Format(block.Gold.Single(g => g.Symbol == "XAU21_G" && g.Currency == "EGP").Price);

    [Fact]
    public async Task AFreshFeedIsServedAndNotStale()
    {
        await store.ApplyFeedAsync(Feed(4800m), T0, CancellationToken.None);

        var block = await BlockAsync();

        Assert.False(block.Stale);
        Assert.Equal(T0, block.AsOf);
        Assert.Equal("USD", block.FxBaseCurrency);
        Assert.Equal("4200.00", Egp21(block));
        Assert.Equal(50m, block.Fx.Single(f => f.Quote == "EGP").Rate);
    }

    [Fact]
    public async Task AFeedOutageServesTheLastValueAndTurnsStaleAfter24Hours()
    {
        await store.ApplyFeedAsync(Feed(4800m), T0, CancellationToken.None);

        clock.Now = T0.AddHours(24);
        var atLimit = await BlockAsync();
        clock.Now = T0.AddHours(24).AddSeconds(1);
        var outage = await BlockAsync();

        Assert.False(atLimit.Stale);
        Assert.True(outage.Stale);
        Assert.Equal("4200.00", Egp21(outage));
        Assert.Equal(T0, outage.AsOf);
    }

    [Fact]
    public async Task AnOverrideWinsOverTheFeedUntilItExpiresThenTheFeedReturns()
    {
        await store.ApplyFeedAsync(Feed(4800m), T0, CancellationToken.None);
        var result = await Overrides.SetAsync(new PriceOverrideInput("XAU21_G", "EGP", "4300.50", "Feed outage", null), Operator, CancellationToken.None);
        Assert.False(result.Invalid);

        Assert.Equal("4300.50", Egp21(await BlockAsync()));

        // A feed run while the override is in force updates the feed value but not what is served.
        clock.Now = T0.AddHours(1);
        await store.ApplyFeedAsync(Feed(4880m), clock.Now, CancellationToken.None);
        Assert.Equal("4300.50", Egp21(await BlockAsync()));

        clock.Now = T0.AddHours(24).AddTicks(-1);
        Assert.Equal("4300.50", Egp21(await BlockAsync()));

        clock.Now = T0.AddHours(24);
        Assert.Equal("4270.00", Egp21(await BlockAsync())); // 4880 * 21 / 24, the feed's own value, with no worker run needed
    }

    [Fact]
    public async Task AnExpiredOverrideOnAQuoteTheFeedNeverSuppliedServesNothingForIt()
    {
        await Overrides.SetAsync(new PriceOverrideInput("XAU24_G", "EGP", "4800", "Manual quote", null), Operator, CancellationToken.None);

        Assert.Single((await BlockAsync()).Gold);

        clock.Now = T0.AddHours(25);
        var rows = await store.ListGoldAsync(CancellationToken.None);
        Assert.Null(Assert.Single(rows).Effective(clock.Now));
        Assert.Null(await new PriceReadService(store, clock).GetBlockAsync(CancellationToken.None));
    }

    [Fact]
    public async Task AnOverrideDoesNotHideAStaleFeed()
    {
        await store.ApplyFeedAsync(Feed(4800m), T0, CancellationToken.None);
        clock.Now = T0.AddHours(30);
        await Overrides.SetAsync(new PriceOverrideInput("XAU24_G", "EGP", "5000", "Manual quote", null), Operator, CancellationToken.None);

        var block = await BlockAsync();

        Assert.True(block.Stale);
        Assert.Equal("5000.00", PriceWire.Format(block.Gold.Single(g => g.Symbol == "XAU24_G" && g.Currency == "EGP").Price));
    }

    [Fact]
    public async Task ClearingAnActiveOverrideReturnsTheFeedAtOnceAndIsAudited()
    {
        await store.ApplyFeedAsync(Feed(4800m), T0, CancellationToken.None);
        await Overrides.SetAsync(new PriceOverrideInput("XAU21_G", "EGP", "4300.50", "Feed wrong", null), Operator, CancellationToken.None);

        Assert.True(await Overrides.ClearAsync("XAU21_G", "EGP", Operator, CancellationToken.None));
        Assert.False(await Overrides.ClearAsync("XAU21_G", "EGP", Operator, CancellationToken.None));
        Assert.False(await Overrides.ClearAsync("XAU99_G", "EGP", Operator, CancellationToken.None));

        Assert.Equal("4200.00", Egp21(await BlockAsync()));
        Assert.Equal(["price_override", "price_override_clear"], store.Audit.Select(a => a.Action));
    }

    [Fact]
    public async Task ExpiresAtDefaultsTo24Hours()
    {
        var result = await Overrides.SetAsync(new PriceOverrideInput("XAU21_G", "EGP", "4217.50", "Feed outage", null), Operator, CancellationToken.None);

        Assert.Equal(T0.AddHours(24), result.Row!.OverrideExpiresAt);
        Assert.Equal(T0, result.Row.AsOf);
    }

    [Fact]
    public async Task ExpiresAtExactlySevenDaysAheadIsAcceptedAndOneSecondMoreIsRejected()
    {
        var edge = await Overrides.SetAsync(new PriceOverrideInput("XAU21_G", "EGP", "1", "Edge case", T0.AddDays(7)), Operator, CancellationToken.None);
        var over = await Overrides.SetAsync(new PriceOverrideInput("XAU21_G", "EGP", "1", "Edge case", T0.AddDays(7).AddSeconds(1)), Operator, CancellationToken.None);

        Assert.False(edge.Invalid);
        Assert.Equal(T0.AddDays(7), edge.Row!.OverrideExpiresAt);
        Assert.True(over.Invalid);
        Assert.Null(over.Row);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-3600)]
    public async Task ExpiresAtNotInTheFutureIsRejected(int secondsFromNow)
    {
        var result = await Overrides.SetAsync(
            new PriceOverrideInput("XAU21_G", "EGP", "1", "Edge case", T0.AddSeconds(secondsFromNow)),
            Operator,
            CancellationToken.None);

        Assert.True(result.Invalid);
        Assert.Empty(store.Rows);
        Assert.Empty(store.Audit);
    }

    [Theory]
    [InlineData("XAU99_G", "EGP", "10", "reason")]
    [InlineData("xau21_g", "EGP", "10", "reason")]
    [InlineData("XAU21_G", "EUR", "10", "reason")]
    [InlineData("XAU21_G", "egp", "10", "reason")]
    [InlineData("XAU21_G", "EGP", "0", "reason")]
    [InlineData("XAU21_G", "EGP", "0.00", "reason")]
    [InlineData("XAU21_G", "EGP", "-5", "reason")]
    [InlineData("XAU21_G", "EGP", "1e3", "reason")]
    [InlineData("XAU21_G", "EGP", "1,000", "reason")]
    [InlineData("XAU21_G", "EGP", "٤٢١٧", "reason")]
    [InlineData("XAU21_G", "EGP", "4217.1234567", "reason")]
    [InlineData("XAU21_G", "EGP", "4217.", "reason")]
    [InlineData("XAU21_G", "EGP", ".5", "reason")]
    [InlineData("XAU21_G", "EGP", "1234567890123", "reason")]
    [InlineData("XAU21_G", "EGP", " 10", "reason")]
    [InlineData("XAU21_G", "EGP", "10", "ab")]
    [InlineData("XAU21_G", "EGP", "10", "  ab  ")]
    [InlineData("XAU21_G", "EGP", "10", "mail me@example.com")]
    [InlineData("XAU21_G", "EGP", "10", "line\nbreak")]
    [InlineData(null, "EGP", "10", "reason")]
    [InlineData("XAU21_G", null, "10", "reason")]
    [InlineData("XAU21_G", "EGP", null, "reason")]
    [InlineData("XAU21_G", "EGP", "10", null)]
    public async Task InvalidInputsAreRejectedBeforeAnythingIsWritten(string? symbol, string? currency, string? price, string? reason)
    {
        var result = await Overrides.SetAsync(new PriceOverrideInput(symbol, currency, price, reason, null), Operator, CancellationToken.None);

        Assert.True(result.Invalid);
        Assert.Empty(store.Rows);
        Assert.Empty(store.Audit);
    }

    [Fact]
    public async Task TheReasonCapIs200CharactersAndThePriceCapIsFifteenDigits()
    {
        var ok = await Overrides.SetAsync(
            new PriceOverrideInput("XAU21_G", "EGP", "123456789012.123456", new string('r', 200), null),
            Operator,
            CancellationToken.None);
        var tooLong = await Overrides.SetAsync(new PriceOverrideInput("XAU21_G", "EGP", "10", new string('r', 201), null), Operator, CancellationToken.None);

        Assert.False(ok.Invalid);
        Assert.True(tooLong.Invalid);
    }
}
