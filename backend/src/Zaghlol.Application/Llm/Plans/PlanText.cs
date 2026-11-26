using System.Text;

namespace Zaghlol.Application.Llm.Plans;

/// <summary>The shared normalisation (<c>foldKey</c> of <c>text_normalizer.dart</c>) and word matching used by steps 2 to 4.</summary>
internal static class PlanText
{
    public static string Fold(string input)
    {
        var output = new StringBuilder(input.Length);
        var pendingSpace = false;
        var wroteAny = false;
        foreach (var unit in input)
        {
            if (IsSpace(unit))
            {
                pendingSpace = true;
                continue;
            }

            if (IsInvisible(unit) || unit == 'ـ' || (unit >= 'ً' && unit <= 'ْ') || unit == 'ٰ')
            {
                continue;
            }

            if (pendingSpace && wroteAny)
            {
                output.Append(' ');
            }

            pendingSpace = false;
            wroteAny = true;
            output.Append(MapChar(unit));
        }

        return output.ToString();
    }

    public static bool ContainsWord(string folded, string word)
    {
        if (word.Length == 0)
        {
            return false;
        }

        var from = 0;
        while (from <= folded.Length - word.Length)
        {
            var at = folded.IndexOf(word, from, StringComparison.Ordinal);
            if (at < 0)
            {
                return false;
            }

            var before = at == 0 || !char.IsLetterOrDigit(folded[at - 1]);
            var end = at + word.Length;
            var after = end == folded.Length || !char.IsLetterOrDigit(folded[end]);
            if (before && after)
            {
                return true;
            }

            from = at + 1;
        }

        return false;
    }

    private static bool IsSpace(char u) =>
        u == ' ' || (u >= '\t' && u <= '\r') || u == '\u0085' || u == '\u00a0' || u == '\u202f' || u == '\u2009' || u == '\u2028' || u == '\u2029';

    private static bool IsInvisible(char u) =>
        (u >= '\u200b' && u <= '\u200f') || (u >= '\u202a' && u <= '\u202e') || (u >= '\u2066' && u <= '\u2069') || u == '؜' || u == '\u2060' || u == '\u00ad' || u == '\ufeff';

    private static char MapChar(char u)
    {
        if (u >= '٠' && u <= '٩')
        {
            return (char)('0' + (u - '٠'));
        }

        if (u >= '۰' && u <= '۹')
        {
            return (char)('0' + (u - '۰'));
        }

        return u switch
        {
            '٫' => '.',
            '٬' => ',',
            'أ' or 'إ' or 'آ' or 'ٱ' => 'ا',
            'ى' => 'ي',
            'ة' => 'ه',
            >= 'A' and <= 'Z' => (char)(u + 0x20),
            _ => u,
        };
    }
}
