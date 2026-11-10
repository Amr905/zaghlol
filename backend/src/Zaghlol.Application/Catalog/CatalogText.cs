using System.Globalization;
using System.Text;

namespace Zaghlol.Application.Catalog;

/// <summary>
/// Structural normalization of catalog alias and keyword text (backend-api §5.2). A key is canonical only when it equals its
/// own normalized form. The rules: lower case, whitespace runs collapsed to one space and trimmed, Arabic-Indic digits folded
/// to ASCII, Arabic tashkeel, tatweel, combining marks, zero-width and bidi controls dropped, alef forms unified to alef and
/// alef maqsura to yeh. The Latin transliteration that produces <c>merchant_norm</c> is done by the app tooling
/// (<c>tools/catalog_build</c>); the backend only refuses text that is plainly not in normalized shape. Deliberately not
/// <c>string.Normalize</c>: the host runs with invariant globalization.
/// </summary>
public static class CatalogText
{
    /// <summary>The longest alias or keyword, matching the <c>merchant_norm</c> cap.</summary>
    public const int MaxKeyLength = 64;

    public static string Normalize(string text)
    {
        ArgumentNullException.ThrowIfNull(text);

        var builder = new StringBuilder(text.Length);
        foreach (var c in text)
        {
            if (Fold(c) is not { } folded)
            {
                continue;
            }

            if (folded == ' ')
            {
                if (builder.Length > 0 && builder[^1] != ' ')
                {
                    builder.Append(' ');
                }
            }
            else
            {
                builder.Append(folded);
            }
        }

        while (builder.Length > 0 && builder[^1] == ' ')
        {
            builder.Length--;
        }

        return builder.ToString();
    }

    /// <summary>True when <paramref name="text"/> is 1 to 64 characters and equals <see cref="Normalize"/> of itself.</summary>
    public static bool IsNormalized(string text)
    {
        ArgumentNullException.ThrowIfNull(text);

        return text.Length is > 0 and <= MaxKeyLength && string.Equals(Normalize(text), text, StringComparison.Ordinal);
    }

    /// <summary>True when every character is printable ASCII (an alias is a Latin <c>merchant_norm</c> string).</summary>
    public static bool IsAsciiText(string text)
    {
        ArgumentNullException.ThrowIfNull(text);

        return text.All(c => c is >= ' ' and <= '~');
    }

    /// <summary>True when <paramref name="text"/> has no control character (display names and notes).</summary>
    public static bool HasNoControlCharacters(string text)
    {
        ArgumentNullException.ThrowIfNull(text);

        return !text.Any(char.IsControl);
    }

    private static char? Fold(char c)
    {
        if (char.IsWhiteSpace(c))
        {
            return ' ';
        }

        if (char.IsControl(c))
        {
            return null;
        }

        switch (c)
        {
            case >= '\u0660' and <= '\u0669':
                return (char)('0' + (c - '\u0660'));
            case >= '\u06F0' and <= '\u06F9':
                return (char)('0' + (c - '\u06F0'));
            case '\u0622' or '\u0623' or '\u0625' or '\u0671':
                return '\u0627';
            case '\u0649':
                return '\u064A';
            case '\u0640' or '\u0670' or '\u2060' or '\uFEFF':
            case >= '\u064B' and <= '\u065F':
            case >= '\u0300' and <= '\u036F':
            case >= '\u200B' and <= '\u200F':
            case >= '\u202A' and <= '\u202E':
                return null;
            default:
                return char.ToLower(c, CultureInfo.InvariantCulture);
        }
    }
}
