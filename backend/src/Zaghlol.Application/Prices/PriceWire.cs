using System.Globalization;

namespace Zaghlol.Application.Prices;

/// <summary>The wire form of a price: a decimal string with at least two decimals and no exponent, never a JSON number.</summary>
public static class PriceWire
{
    public static string Format(decimal value, int maxDecimals = 6) =>
        decimal.Round(value, maxDecimals, MidpointRounding.AwayFromZero).ToString("0.00" + new string('#', Math.Max(0, maxDecimals - 2)), CultureInfo.InvariantCulture);
}
