using System.Buffers;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Zaghlol.Application.Llm.Plans;

/// <summary>
/// The model template grammar (ask-llm.md section 2.3, step 6). Rules run in the fixed order of <c>templateRules.order</c> of the shared
/// vectors and the first failing rule gives the reason. Never logs and never puts the text into an exception.
/// </summary>
public static partial class TemplateGrammar
{
    public const int MaxLength = 200;

    private static readonly SearchValues<char> LineBreaks = SearchValues.Create(['\n', '\r', '\u0085', '\u2028', '\u2029']);

    private static readonly SearchValues<char> Ats = SearchValues.Create(['@', '\uff20', '\ufe6b']);

    private static readonly SearchValues<char> Markup = SearchValues.Create(['<', '>', '[', ']', '(', ')', '*', '_', '#', '`', '|', '~']);

    /// <summary>Blanks a template may use per plan. Plans that are not listed never use a model template (BR-LLM-04).</summary>
    private static readonly Dictionary<string, string[]> Blanks = new(StringComparer.Ordinal)
    {
        ["PL-SPEND"] = ["target", "period", "amount", "count"],
        ["PL-COMPARE"] = ["target", "period", "periodB", "amount", "amountB", "diff", "pct"],
        ["PL-BREAKDOWN"] = ["period", "count"],
        ["PL-TOPN"] = ["period", "count"],
        ["PL-AVERAGE"] = ["target", "period", "amount", "count"],
        ["PL-INCOME"] = ["period", "amount"],
        ["PL-SAVED"] = ["period", "amount"],
        ["PL-BILLS-DUE"] = ["count", "amount", "date"],
        ["PL-BUDGET-LEFT"] = ["target", "amount"],
        ["PL-SAFE-SPEND"] = ["amount"],
        ["PL-BALANCE"] = ["amount"],
        ["PL-WHATIF-CUT"] = ["target", "pct", "monthly", "total", "months"],
        ["PL-WHATIF-SAVE"] = ["monthly", "total", "months"],
    };

    /// <summary>Null when the template passes, otherwise the first failing rule.</summary>
    public static PlanReason? Check(string plan, string requestLang, string templateLang, string text)
    {
        if (text.Length is < 1 or > MaxLength || text.AsSpan().IndexOfAny(LineBreaks) >= 0)
        {
            return PlanReason.TemplateLength;
        }

        if (!Nfc.IsNfc(text))
        {
            return PlanReason.TemplateNotNfc;
        }

        if (templateLang is not ("ar" or "en") || !string.Equals(templateLang, requestLang, StringComparison.Ordinal))
        {
            return PlanReason.TemplateLang;
        }

        if (!Blanks.TryGetValue(plan, out var allowed))
        {
            return PlanReason.TemplatePlanNotAllowed;
        }

        if (text.Contains('\u27e6', StringComparison.Ordinal) || text.Contains('\u27e7', StringComparison.Ordinal))
        {
            return PlanReason.TemplatePlaceholder;
        }

        if (text.EnumerateRunes().Any(r => Rune.GetUnicodeCategory(r) == UnicodeCategory.DecimalDigitNumber))
        {
            return PlanReason.TemplateDigit;
        }

        var found = BlankRegex().Matches(text).Select(m => m.Groups[1].Value).ToList();
        var remainder = BlankRegex().Replace(text, string.Empty);
        if (remainder.Contains('{', StringComparison.Ordinal) || remainder.Contains('}', StringComparison.Ordinal) || found.Any(f => !allowed.Contains(f)))
        {
            return PlanReason.TemplateBadBlank;
        }

        if (found.Count != found.Distinct(StringComparer.Ordinal).Count())
        {
            return PlanReason.TemplateDuplicateBlank;
        }

        if (text.AsSpan().IndexOfAny(Ats) >= 0)
        {
            return PlanReason.TemplateAt;
        }

        if (text.Contains("://", StringComparison.Ordinal) || text.Contains("www.", StringComparison.OrdinalIgnoreCase) || LabelTldRegex().IsMatch(text))
        {
            return PlanReason.TemplateLink;
        }

        if (text.AsSpan().IndexOfAny(Markup) >= 0)
        {
            return PlanReason.TemplateMarkup;
        }

        if (text.Any(IsControl))
        {
            return PlanReason.TemplateControl;
        }

        if (text.EnumerateRunes().Count(r => IsEmoji(r.Value)) > 1)
        {
            return PlanReason.TemplateEmoji;
        }

        var letters = remainder.EnumerateRunes().Where(r => Rune.IsLetter(r)).ToList();
        var arabic = letters.Count(r => IsArabicScript(r.Value));
        if (requestLang == "ar" ? letters.Count == 0 || arabic * 100 < letters.Count * 70 : arabic > 0)
        {
            return PlanReason.TemplateScript;
        }

        return null;
    }

    private static bool IsControl(char u) =>
        char.IsControl(u) || u == '؜' || (u >= '\u200b' && u <= '\u200f') || u == '\u2060' || (u >= '\u202a' && u <= '\u202e') || (u >= '\u2066' && u <= '\u2069') || u == '\ufeff';

    private static bool IsEmoji(int cp) => (cp >= 0x1F000 && cp <= 0x1FAFF) || (cp >= 0x2600 && cp <= 0x27BF) || cp == 0x2B50 || cp == 0x2B55;

    private static bool IsArabicScript(int cp) =>
        (cp >= 0x0600 && cp <= 0x06FF) || (cp >= 0x0750 && cp <= 0x077F) || (cp >= 0x08A0 && cp <= 0x08FF) || (cp >= 0xFB50 && cp <= 0xFDFF) || (cp >= 0xFE70 && cp <= 0xFEFF);

    [GeneratedRegex(@"\{([A-Za-z]+)\}")]
    private static partial Regex BlankRegex();

    [GeneratedRegex(@"\p{L}\.\p{L}{2}")]
    private static partial Regex LabelTldRegex();
}
