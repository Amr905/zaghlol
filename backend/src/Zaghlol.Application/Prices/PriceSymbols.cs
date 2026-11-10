using System.Globalization;

namespace Zaghlol.Application.Prices;

/// <summary>
/// The price symbols and currencies the service knows (FR-BE-04). The set is closed: an override for anything else is
/// <c>400</c>, so a typo can't create a quote, and every metric tag stays a fixed value set.
/// </summary>
public static class PriceSymbols
{
    public const string Gold24 = "XAU24_G";
    public const string Gold21 = "XAU21_G";
    public const string Gold18 = "XAU18_G";

    public const string Egp = "EGP";
    public const string Usd = "USD";

    /// <summary>The unit stored in <c>price_quotes.per_unit</c> for gold.</summary>
    public const string PerGram = "gram";

    /// <summary>FX is quoted against this base (backend-api sync example: <c>fx.base = "USD"</c>).</summary>
    public const string FxBase = Usd;

    public static IReadOnlyList<string> Gold { get; } = [Gold24, Gold21, Gold18];

    public static IReadOnlyList<string> GoldCurrencies { get; } = [Egp, Usd];

    public static bool IsGold(string? symbol) => symbol is not null && Gold.Contains(symbol, StringComparer.Ordinal);

    public static bool IsGoldCurrency(string? currency) => currency is not null && GoldCurrencies.Contains(currency, StringComparer.Ordinal);

    /// <summary>The karat of a gold symbol (24, 21 or 18), or <c>null</c>.</summary>
    public static int? KaratOf(string symbol) => symbol switch
    {
        Gold24 => 24,
        Gold21 => 21,
        Gold18 => 18,
        _ => null,
    };

    public static string SymbolOf(int karat) => karat switch
    {
        24 => Gold24,
        21 => Gold21,
        18 => Gold18,
        _ => throw new ArgumentOutOfRangeException(nameof(karat), karat.ToString(CultureInfo.InvariantCulture), "unsupported karat"),
    };

    /// <summary>True for an ISO 4217-shaped code (three upper-case ASCII letters).</summary>
    public static bool IsCurrencyShape(string? code) =>
        code is { Length: 3 } && code.All(c => c is >= 'A' and <= 'Z');
}
