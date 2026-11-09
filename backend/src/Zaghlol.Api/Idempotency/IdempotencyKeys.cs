using System.Diagnostics.CodeAnalysis;
using System.Text.RegularExpressions;

namespace Zaghlol.Api.Idempotency;

/// <summary><c>Idempotency-Key</c>: exactly one 26-character Crockford ULID (OpenAPI <c>IdempotencyKey</c>). Never logged.</summary>
internal static partial class IdempotencyKeys
{
    public const string HeaderName = "Idempotency-Key";

    /// <summary>The OpenAPI pattern, character for character (a contract test compares them).</summary>
    public const string Pattern = "^[0-9A-HJKMNP-TV-Z]{26}$";

    public static bool TryRead(IHeaderDictionary headers, [NotNullWhen(true)] out string? key)
    {
        ArgumentNullException.ThrowIfNull(headers);

        key = null;
        var values = headers[HeaderName];
        if (values.Count != 1 || values[0] is not { } value || !Ulid().IsMatch(value))
        {
            return false;
        }

        key = value;
        return true;
    }

    [GeneratedRegex(Pattern, RegexOptions.CultureInvariant)]
    private static partial Regex Ulid();
}
