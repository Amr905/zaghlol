using System.Text;

namespace Zaghlol.Application.Contributions;

/// <summary>
/// The API-side privacy filter for free-text contribution fields (<c>merchant_norm</c>, <c>institution_name_norm</c>; BR-SYNC-04,
/// CLAUDE.md §2.5, T-122 security review F7). It runs before any INSERT so the database CHECK is only a backstop and never the
/// control that fires (a CHECK violation would log the row's detail server-side). It folds digits of every script to ASCII,
/// strips separators, and rejects a run of six digits, an <c>@</c>, and anything over 64 characters. T-128 calls it.
/// </summary>
public static class ContributionPrivacy
{
    public const int MaxLength = 64;
    public const int DigitRun = 6;

    /// <summary>
    /// The separators allowed between digits of one run (up to <see cref="MaxSeparators"/> in a row), mirrored by the SQL CHECK:
    /// whitespace, <c>. , / _ ، -</c>.
    /// </summary>
    public const string Separators = ".,/_،-";

    public const int MaxSeparators = 3;

    public static bool IsAcceptable(string? text)
    {
        if (string.IsNullOrEmpty(text) || text.Length > MaxLength || text.Contains('@', StringComparison.Ordinal))
        {
            return false;
        }

        return !HasDigitRun(Fold(text));
    }

    /// <summary>ASCII digits for the digits of every supported script; every other character is unchanged.</summary>
    public static string Fold(string text)
    {
        ArgumentNullException.ThrowIfNull(text);

        var builder = new StringBuilder(text.Length);
        foreach (var c in text)
        {
            builder.Append(DigitValue(c) is { } digit ? (char)('0' + digit) : c);
        }

        return builder.ToString();
    }

    private static int? DigitValue(char c) => c switch
    {
        >= '0' and <= '9' => c - '0',
        >= '٠' and <= '٩' => c - '٠', // Arabic-Indic
        >= '۰' and <= '۹' => c - '۰', // Extended Arabic-Indic
        >= '０' and <= '９' => c - '０', // fullwidth
        _ => null,
    };

    /// <summary>Six digits with at most <see cref="MaxSeparators"/> separators between neighbours: the regex of the CHECK, by hand.</summary>
    private static bool HasDigitRun(string folded)
    {
        var digits = 0;
        var gap = 0;
        foreach (var c in folded)
        {
            if (c is >= '0' and <= '9')
            {
                gap = 0;
                if (++digits >= DigitRun)
                {
                    return true;
                }
            }
            else if (digits > 0 && gap < MaxSeparators && (char.IsWhiteSpace(c) || Separators.Contains(c, StringComparison.Ordinal)))
            {
                gap++;
            }
            else
            {
                digits = 0;
                gap = 0;
            }
        }

        return false;
    }
}
