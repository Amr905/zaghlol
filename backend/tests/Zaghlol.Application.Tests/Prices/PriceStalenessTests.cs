using Zaghlol.Application.Prices;

namespace Zaghlol.Application.Tests.Prices;

/// <summary>T-127 review minor 1, resolved in T-128: staleness is judged per kind (gold feed, FX), each against 24 h.</summary>
public class PriceStalenessTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 10, 12, 0, 0, TimeSpan.Zero);

    private static PriceRow Gold(DateTimeOffset feedAsOf) =>
        new("XAU24_G", "EGP", 4800m, feedAsOf, "fake", false, null, 4800m, feedAsOf);

    private static FxRow Fx(DateTimeOffset asOf) => new("EGP", 48.95m, asOf, "fake");

    [Fact]
    public void AStaleGoldFeedIsStaleEvenWhenFxIsFresh()
    {
        var block = PriceReadService.Build([Gold(Now.AddHours(-25))], [Fx(Now)], Now)!;

        Assert.True(block.Stale);
        Assert.Equal(Now, block.AsOf); // asOf stays the newest feed time
    }

    [Fact]
    public void AStaleFxFeedIsStaleEvenWhenGoldIsFresh()
    {
        Assert.True(PriceReadService.Build([Gold(Now)], [Fx(Now.AddHours(-25))], Now)!.Stale);
    }

    [Fact]
    public void BothKindsWithin24HoursAreFresh()
    {
        Assert.False(PriceReadService.Build([Gold(Now.AddHours(-24))], [Fx(Now.AddHours(-23))], Now)!.Stale);
    }

    [Fact]
    public void AGoldOnlyOrFxOnlyCacheIsJudgedOnWhatItHas()
    {
        Assert.False(PriceReadService.Build([Gold(Now.AddHours(-1))], [], Now)!.Stale);
        Assert.False(PriceReadService.Build([], [Fx(Now.AddHours(-1))], Now)!.Stale);
        Assert.True(PriceReadService.Build([], [Fx(Now.AddHours(-25))], Now)!.Stale);
        Assert.Null(PriceReadService.Build([], [], Now));
    }
}
