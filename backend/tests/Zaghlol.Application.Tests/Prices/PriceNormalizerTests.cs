using Zaghlol.Application.Prices;

namespace Zaghlol.Application.Tests.Prices;

public class PriceNormalizerTests
{
    private static readonly DateTimeOffset At = new(2026, 11, 10, 9, 0, 0, TimeSpan.Zero);

    private static ProviderSnapshot Snapshot(IEnumerable<GoldQuote>? gold = null, IEnumerable<FxQuote>? fx = null) =>
        new((gold ?? []).ToList(), (fx ?? []).ToList(), At);

    private static NormalizedPrices Run(params (string Source, ProviderSnapshot Snapshot)[] snapshots) => PriceNormalizer.Normalize(snapshots);

    private static decimal Price(NormalizedPrices result, string symbol, string currency) =>
        result.Gold.Single(g => g.Symbol == symbol && g.Currency == currency).Price;

    [Fact]
    public void MissingKaratsAreDerivedFromThe24KPrice()
    {
        var result = Run(("local_gold", Snapshot([new GoldQuote("XAU24_G", "EGP", 4800m)])));

        Assert.Equal(4200.00m, Price(result, "XAU21_G", "EGP"));
        Assert.Equal(3600.00m, Price(result, "XAU18_G", "EGP"));
        Assert.Equal("local_gold+derived", result.Gold.Single(g => g.Symbol == "XAU21_G").Source);
        Assert.Equal("local_gold", result.Gold.Single(g => g.Symbol == "XAU24_G").Source);
    }

    [Fact]
    public void AKaratTheFeedSuppliesIsNeverOverwrittenByDerivation()
    {
        var result = Run(("local_gold", Snapshot([new GoldQuote("XAU24_G", "EGP", 4820m), new GoldQuote("XAU21_G", "EGP", 4217.50m)])));

        Assert.Equal(4217.50m, Price(result, "XAU21_G", "EGP"));
        Assert.Equal(3615.00m, Price(result, "XAU18_G", "EGP"));
    }

    [Fact]
    public void AMissingKaratIsDerivedFromALowerKaratWhenThe24KIsAbsent()
    {
        var result = Run(("local_gold", Snapshot([new GoldQuote("XAU21_G", "EGP", 4200m)])));

        Assert.Equal(4800.00m, Price(result, "XAU24_G", "EGP"));
        Assert.Equal(3600.00m, Price(result, "XAU18_G", "EGP"));
    }

    [Fact]
    public void UsdGoldIsDerivedFromEgpGoldAndTheUsdEgpRate()
    {
        var result = Run(("fake", Snapshot([new GoldQuote("XAU24_G", "EGP", 4895m)], [new FxQuote("EGP", 48.95m)])));

        Assert.Equal(100.00m, Price(result, "XAU24_G", "USD"));
        Assert.Equal(87.50m, Price(result, "XAU21_G", "USD"));
        Assert.Equal(75.00m, Price(result, "XAU18_G", "USD"));
        Assert.Equal(6, result.Gold.Count);
    }

    [Fact]
    public void WithoutAnEgpRateNoUsdPriceIsInvented()
    {
        var result = Run(("fake", Snapshot([new GoldQuote("XAU24_G", "EGP", 4895m)])));

        Assert.DoesNotContain(result.Gold, g => g.Currency == "USD");
    }

    [Fact]
    public void ADerivedValueIsRoundedToTwoDecimalsAwayFromZero()
    {
        var result = Run(("p", Snapshot([new GoldQuote("XAU24_G", "EGP", 4821.37m)])));

        Assert.Equal(4218.70m, Price(result, "XAU21_G", "EGP")); // 4821.37 * 21 / 24 = 4218.69875
        Assert.Equal(3616.03m, Price(result, "XAU18_G", "EGP")); // 3616.0275
    }

    [Fact]
    public void TheFirstProviderThatSuppliesAQuoteWins()
    {
        var result = Run(
            ("local_gold", Snapshot([new GoldQuote("XAU24_G", "EGP", 4800m)])),
            ("spot_gold", Snapshot([new GoldQuote("XAU24_G", "EGP", 5000m), new GoldQuote("XAU21_G", "EGP", 4300m)])));

        Assert.Equal(4800m, Price(result, "XAU24_G", "EGP"));
        Assert.Equal(4300m, Price(result, "XAU21_G", "EGP"));
    }

    [Fact]
    public void FxFromAnotherProviderIsMergedAndRoundedToEightDecimals()
    {
        var result = Run(
            ("local_gold", Snapshot([new GoldQuote("XAU24_G", "EGP", 4895m)])),
            ("fx", Snapshot(fx: [new FxQuote("EGP", 48.95m), new FxQuote("SAR", 3.750000009m)])));

        Assert.Equal(100.00m, Price(result, "XAU24_G", "USD"));
        Assert.Equal(3.75000001m, result.Fx.Single(f => f.Quote == "SAR").Rate);
        Assert.Equal("fx", result.Fx.Single(f => f.Quote == "SAR").Source);
    }

    [Theory]
    [InlineData("XAU24_G", "EGP", 0)]
    [InlineData("XAU24_G", "EGP", -1)]
    [InlineData("XAU24_G", "EUR", 100)]
    [InlineData("XAG_G", "EGP", 100)]
    [InlineData("XAU24_G", "EGP", 1_000_000_000_000)]
    public void InvalidGoldQuotesAreDropped(string symbol, string currency, long price)
    {
        var result = Run(("p", Snapshot([new GoldQuote(symbol, currency, price)])));

        Assert.Empty(result.Gold);
    }

    [Theory]
    [InlineData("usd", 1)]
    [InlineData("US", 1)]
    [InlineData("USD", 1)]
    [InlineData("EGP", 0)]
    [InlineData("EGP", -48)]
    public void InvalidOrBaseFxQuotesAreDropped(string quote, long rate)
    {
        var result = Run(("p", Snapshot(fx: [new FxQuote(quote, rate)])));

        Assert.Empty(result.Fx);
    }

    [Fact]
    public void NoProviderYieldsNothing()
    {
        var result = Run();

        Assert.Empty(result.Gold);
        Assert.Empty(result.Fx);
    }

    [Theory]
    [InlineData("4820", "4820.00")]
    [InlineData("4217.5", "4217.50")]
    [InlineData("98.4", "98.40")]
    [InlineData("0.123456", "0.123456")]
    [InlineData("48.95", "48.95")]
    public void TheWireFormIsADecimalStringWithAtLeastTwoDecimalsAndNoExponent(string value, string expected)
    {
        Assert.Equal(expected, PriceWire.Format(decimal.Parse(value, System.Globalization.CultureInfo.InvariantCulture)));
    }

    [Fact]
    public void FxRatesAreWrittenWithUpToEightDecimals()
    {
        Assert.Equal("3.75000001", PriceWire.Format(3.75000001m, 8));
        Assert.Equal("0.92", PriceWire.Format(0.92m, 8));
    }
}
