using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Zaghlol.Ops.Commands;

/// <summary>Client-side checks that mirror the OpenAPI patterns, so a typo fails before a sign-in or a prompt. The server stays the authority.</summary>
internal static partial class Validate
{
    public static bool Uuid(string? value, out Guid id) => Guid.TryParseExact(value, "D", out id);

    public static bool Match(Regex pattern, string? value) => value is not null && pattern.IsMatch(value);

    public static bool PositiveInt(string? value, int max, out int number) =>
        int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out number) && number >= 1 && number <= max;

    public static bool NonNegativeInt(string? value, int max, out int number) =>
        int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out number) && number >= 0 && number <= max;

    public static bool Long(string? value, out long number) =>
        long.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out number) && number >= 1;

    public static bool Text(string? value, int max) =>
        value is { Length: > 0 } && value.Length <= max && value.All(c => !char.IsControl(c));

    /// <summary>Canonical base64url without padding of the UTF-8 text (catalog alias and keyword keys).</summary>
    public static string B64u(string text) => System.Buffers.Text.Base64Url.EncodeToString(Encoding.UTF8.GetBytes(text));

    [GeneratedRegex(@"^[a-z][a-z0-9_]{1,31}$", RegexOptions.CultureInvariant, 1000)]
    public static partial Regex CategoryCode();

    [GeneratedRegex(@"^[a-z0-9_]{2,32}$", RegexOptions.CultureInvariant, 1000)]
    public static partial Regex InstitutionCode();

    [GeneratedRegex(@"^[a-z][a-z0-9_]{1,63}$", RegexOptions.CultureInvariant, 1000)]
    public static partial Regex FlagKey();

    [GeneratedRegex(@"^[A-Z0-9_]{3,16}$", RegexOptions.CultureInvariant, 1000)]
    public static partial Regex PriceSymbol();

    [GeneratedRegex(@"^[A-Z]{3}$", RegexOptions.CultureInvariant, 1000)]
    public static partial Regex Currency();

    [GeneratedRegex(@"^[0-9]{1,15}(\.[0-9]{1,8})?$", RegexOptions.CultureInvariant, 1000)]
    public static partial Regex Decimal();

    [GeneratedRegex(@"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$", RegexOptions.CultureInvariant, 1000)]
    public static partial Regex UtcTimestamp();

    [GeneratedRegex(@"^[A-Za-z0-9_-]{1,32}$", RegexOptions.CultureInvariant, 1000)]
    public static partial Regex TicketRef();

    [GeneratedRegex(@"^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$", RegexOptions.CultureInvariant, 1000)]
    public static partial Regex AppVersion();

    [GeneratedRegex(@"^([a-z][a-z0-9_]{1,31}|[0-9]{1,9}|[0-9]{1,9}:[A-Za-z0-9_-]{2,342}|[a-z]{2}:[A-Za-z0-9_-]{2,342})$", RegexOptions.CultureInvariant, 1000)]
    public static partial Regex CatalogKey();

    [GeneratedRegex(@"^[^@\s]{1,64}@[^@\s]{1,189}$", RegexOptions.CultureInvariant, 1000)]
    public static partial Regex Email();
}
