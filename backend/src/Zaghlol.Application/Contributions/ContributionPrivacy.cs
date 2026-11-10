using System.Globalization;
using System.Text;

namespace Zaghlol.Application.Contributions;

/// <summary>
/// The API-side privacy filter for free-text contribution fields (<c>merchant_norm</c>, <c>institution_name_norm</c>; BR-SYNC-04,
/// CLAUDE.md §2.5, T-122 security review F7, T-128 security review S1). It runs before any INSERT so the database CHECK is only a
/// backstop and never the control that fires (a CHECK violation would log the row's detail server-side). It rejects text over 64
/// UTF-16 code units, any commercial at (<c>@</c>, fullwidth <c>＠</c>, small <c>﹫</c>), and a run of six digits, where:
/// <list type="bullet">
/// <item>a digit is any Unicode decimal digit (category <c>Nd</c>, every script) or any other number character whose numeric
/// value is a whole number 0-9 (<c>No</c>: superscripts, subscripts, circled digits); see <see cref="DigitValue"/>;</item>
/// <item>up to <see cref="MaxSeparators"/> separators may stand between two digits of a run, and a separator is any character that
/// is not a letter (<c>Lu Ll Lt Lo</c>), so whitespace, every dash (<c>Pd</c>, U+2212 minus), brackets, other punctuation
/// (<c>• · : |</c>) and symbols all count; modifier letters (<c>Lm</c>, e.g. the Arabic tatweel <c>ـ</c>) count as separators too;</item>
/// <item>combining marks (<c>Mn Me Mc</c>) and format characters (<c>Cf</c>) are skipped: they neither break a run nor count as a
/// separator.</item>
/// </list>
/// Anything the database CHECK rejects (<c>CheckSql.PrivacySafeNorm</c>: ASCII, Arabic-Indic, Extended Arabic-Indic and fullwidth
/// digits with up to three whitespace, <c>. , / _ ، -</c> between them, an ASCII <c>@</c>, over 64 code points) is rejected here
/// first. T-128 calls it on the stored (normalized) form.
/// </summary>
public static class ContributionPrivacy
{
    public const int MaxLength = 64;
    public const int DigitRun = 6;

    /// <summary>The most separators allowed in a row between two digits of one run.</summary>
    public const int MaxSeparators = 3;

    /// <summary>The commercial-at characters: ASCII, fullwidth (U+FF20) and small (U+FE6B).</summary>
    public const string AtSigns = "@＠﹫";

    public static bool IsAcceptable(string? text)
    {
        if (string.IsNullOrEmpty(text) || text.Length > MaxLength || text.AsSpan().IndexOfAny(AtSigns) >= 0)
        {
            return false;
        }

        return !HasDigitRun(text);
    }

    /// <summary>
    /// Every digit (<see cref="DigitValue"/>) as its ASCII digit; every other character is unchanged (a digit outside the BMP
    /// becomes one ASCII character).
    /// </summary>
    public static string Fold(string text)
    {
        ArgumentNullException.ThrowIfNull(text);

        var builder = new StringBuilder(text.Length);
        foreach (var rune in text.EnumerateRunes())
        {
            if (DigitValue(rune) is { } digit)
            {
                builder.Append((char)('0' + digit));
            }
            else
            {
                builder.Append(rune.ToString());
            }
        }

        return builder.ToString();
    }

    /// <summary>
    /// The value 0-9 of a digit of any script: a decimal digit (<c>Nd</c>), or another number character (<c>No</c>) whose numeric
    /// value is a whole number 0-9 (superscript, subscript, circled and dingbat digits). <c>null</c> for anything else. Uses
    /// CoreLib's own Unicode tables, so it works under invariant globalization.
    /// </summary>
    public static int? DigitValue(Rune rune)
    {
        var category = Rune.GetUnicodeCategory(rune);
        if (category is not (UnicodeCategory.DecimalDigitNumber or UnicodeCategory.OtherNumber))
        {
            return null;
        }

        var value = Rune.GetNumericValue(rune);
        return value is >= 0 and <= 9 && value == Math.Floor(value) ? (int)value : null;
    }

    /// <summary>A run of <see cref="DigitRun"/> digits with at most <see cref="MaxSeparators"/> separators between neighbours.</summary>
    private static bool HasDigitRun(string text)
    {
        var digits = 0;
        var gap = 0;
        foreach (var rune in text.EnumerateRunes())
        {
            if (DigitValue(rune) is not null)
            {
                gap = 0;
                if (++digits >= DigitRun)
                {
                    return true;
                }

                continue;
            }

            switch (Rune.GetUnicodeCategory(rune))
            {
                case UnicodeCategory.NonSpacingMark or UnicodeCategory.EnclosingMark or UnicodeCategory.SpacingCombiningMark
                    or UnicodeCategory.Format:
                    continue; // transparent: neither breaks the run nor counts as a separator
                case UnicodeCategory.UppercaseLetter or UnicodeCategory.LowercaseLetter or UnicodeCategory.TitlecaseLetter
                    or UnicodeCategory.OtherLetter:
                    digits = 0;
                    gap = 0;
                    continue;
                default:
                    if (digits > 0 && gap < MaxSeparators)
                    {
                        gap++;
                    }
                    else
                    {
                        digits = 0;
                        gap = 0;
                    }

                    continue;
            }
        }

        return false;
    }
}
