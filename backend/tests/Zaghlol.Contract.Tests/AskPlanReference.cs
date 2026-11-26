using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Json.Schema;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// A small reference implementation of steps 2 to 6 of <c>ask-llm.md</c> section 2.4, written only to prove that the
/// shared vectors are self-consistent (every vector gets the outcome it declares). The production validators
/// (backend T-330, phone T-331) are separate code that must give the same answers on the same vectors.
/// </summary>
internal sealed partial class AskPlanReference
{
    private static readonly char[] LineBreaks = ['\n', '\r', '\u0085', '\u2028', '\u2029'];

    private static readonly string[] FilterKeys = ["slug", "ref", "mention"];

    private static readonly string[] TextKeys = ["ref", "mention"];

    private readonly JsonObject schemaFile;
    private readonly Dictionary<string, JsonSchema> perPlan = new(StringComparer.Ordinal);
    private readonly Dictionary<string, decimal> numberWords = new(StringComparer.Ordinal);
    private readonly List<string> aliases;
    private readonly Dictionary<string, string[]> blanks = new(StringComparer.Ordinal);
    private readonly HashSet<string> threeDecimals;
    private readonly HashSet<string> noDecimals;

    public AskPlanReference(JsonObject vectors)
    {
        schemaFile = LlmContractFiles.AskPlanSchemaFile();
        foreach (var (word, value) in vectors["numberWords"]!["words"]!.AsObject())
        {
            numberWords[Fold(word)] = decimal.Parse(value!.GetValue<string>(), CultureInfo.InvariantCulture);
        }

        aliases = vectors["registryAliases"]!["aliases"]!.AsArray().Select(a => Fold(a!.GetValue<string>())).ToList();
        foreach (var (plan, list) in vectors["templateBlanks"]!.AsObject())
        {
            if (list is JsonArray array)
            {
                blanks[plan] = array.Select(b => b!.GetValue<string>()).ToArray();
            }
        }

        var exponents = vectors["currencyExponents"]!.AsObject();
        threeDecimals = exponents["3"]!.AsArray().Select(c => c!.GetValue<string>()).ToHashSet(StringComparer.Ordinal);
        noDecimals = exponents["0"]!.AsArray().Select(c => c!.GetValue<string>()).ToHashSet(StringComparer.Ordinal);
    }

    /// <summary>Outcome of steps 2 to 5: null when the plan is accepted, otherwise (step, reason).</summary>
    public (int Step, string Reason)? CheckPlan(JsonObject plan, string sent)
    {
        // Step 2: references, then plain registry names.
        var texts = new List<(string Key, string Value)>();
        Collect(plan["p"], texts);
        foreach (var (key, value) in texts.Where(t => t.Key == "ref"))
        {
            if (!sent.Contains(value, StringComparison.Ordinal))
            {
                return (2, "REF_NOT_IN_TEXT");
            }
        }

        foreach (var (key, value) in texts.Where(t => t.Key == "mention"))
        {
            var folded = Fold(value);
            if (aliases.Any(a => ContainsWord(folded, a)))
            {
                return (2, "PLAIN_NAME");
            }
        }

        // Step 3: mention is a substring of the sent text after normalisation.
        var foldedSent = Fold(sent);
        foreach (var (key, value) in texts.Where(t => t.Key == "mention"))
        {
            if (!MentionOccurs(foldedSent, value))
            {
                return (3, "MENTION_NOT_IN_TEXT");
            }
        }

        // Step 4: amounts come from the question.
        var knownNumbers = NumbersIn(foldedSent);
        foreach (var amount in Amounts(plan["p"]))
        {
            if (!decimal.TryParse(amount.Value, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var number)
                || !(knownNumbers.Contains(number) || WordValues(foldedSent).Contains(number)))
            {
                return (4, "AMOUNT_NOT_IN_TEXT");
            }

            if (amount.Currency is { } currency && FractionDigits(amount.Value) > Exponent(currency))
            {
                return (4, "AMOUNT_FRACTION_TOO_LONG");
            }
        }

        // Step 5: cross-field rules.
        return CrossField(plan);
    }

    public static bool MentionOccurs(string foldedSent, string mention)
    {
        var folded = Fold(mention);
        return folded.Length > 0 && foldedSent.Contains(folded, StringComparison.Ordinal);
    }

    /// <summary>The first failing step 6 rule for a template, or null.</summary>
    public string? CheckTemplate(string plan, string requestLang, string tLang, string text)
    {
        if (text.Length is < 1 or > 200 || text.IndexOfAny(LineBreaks) >= 0)
        {
            return "TEMPLATE_LENGTH";
        }

        if (!IsNfc(text))
        {
            return "TEMPLATE_NOT_NFC";
        }

        if (tLang is not ("ar" or "en") || tLang != requestLang)
        {
            return "TEMPLATE_LANG";
        }

        if (!blanks.TryGetValue(plan, out var allowed))
        {
            return "TEMPLATE_PLAN_NOT_ALLOWED";
        }

        if (text.Contains('\u27e6', StringComparison.Ordinal) || text.Contains('\u27e7', StringComparison.Ordinal))
        {
            return "TEMPLATE_PLACEHOLDER";
        }

        if (text.EnumerateRunes().Any(r => Rune.GetUnicodeCategory(r) == UnicodeCategory.DecimalDigitNumber))
        {
            return "TEMPLATE_DIGIT";
        }

        var found = BlankRegex().Matches(text).Select(m => m.Groups[1].Value).ToList();
        var remainder = BlankRegex().Replace(text, string.Empty);
        if (remainder.Contains('{', StringComparison.Ordinal) || remainder.Contains('}', StringComparison.Ordinal) || found.Any(f => !allowed.Contains(f)))
        {
            return "TEMPLATE_BAD_BLANK";
        }

        if (found.Count != found.Distinct(StringComparer.Ordinal).Count())
        {
            return "TEMPLATE_DUPLICATE_BLANK";
        }

        if (text.IndexOfAny(['@', '\uff20', '\ufe6b']) >= 0)
        {
            return "TEMPLATE_AT";
        }

        if (text.Contains("://", StringComparison.Ordinal) || text.Contains("www.", StringComparison.OrdinalIgnoreCase) || LabelTldRegex().IsMatch(text))
        {
            return "TEMPLATE_LINK";
        }

        if (text.IndexOfAny(['<', '>', '[', ']', '(', ')', '*', '_', '#', '`', '|', '~']) >= 0)
        {
            return "TEMPLATE_MARKUP";
        }

        if (text.Any(IsControl))
        {
            return "TEMPLATE_CONTROL";
        }

        if (text.EnumerateRunes().Count(r => IsEmoji(r.Value)) > 1)
        {
            return "TEMPLATE_EMOJI";
        }

        var letters = remainder.EnumerateRunes().Where(r => Rune.IsLetter(r)).ToList();
        var arabic = letters.Count(r => IsArabicScript(r.Value));
        if (requestLang == "ar" ? letters.Count == 0 || arabic * 100 < letters.Count * 70 : arabic > 0)
        {
            return "TEMPLATE_SCRIPT";
        }

        return null;
    }

    /// <summary>
    /// The backend test host runs with invariant globalization, where <c>string.Normalize</c> is a no-op for non-ASCII text, so the
    /// reference also rejects any Latin combining mark (U+0300..U+036F), which is what the vectors use. Production code must use a real
    /// NFC implementation (the T-330 validator may not rely on <c>string.IsNormalized</c> under invariant globalization).
    /// </summary>
    private static bool IsNfc(string text) => text.IsNormalized(NormalizationForm.FormC) && !text.Any(c => c is >= '\u0300' and <= '\u036f');

    /// <summary>The <c>foldKey</c> of <c>text_normalizer.dart</c>.</summary>
    public static string Fold(string input)
    {
        var output = new StringBuilder();
        var pendingSpace = false;
        var wroteAny = false;
        foreach (var unit in input)
        {
            if (IsSpace(unit))
            {
                pendingSpace = true;
                continue;
            }

            if (IsInvisible(unit) || unit == '\u0640' || (unit >= '\u064b' && unit <= '\u0652') || unit == '\u0670')
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

    private (int Step, string Reason)? CrossField(JsonObject plan)
    {
        var name = plan["plan"]!.GetValue<string>();
        var p = plan["p"]!;
        if (!perPlan.TryGetValue(name, out var schema))
        {
            schema = LlmContractFiles.CompileDef(schemaFile, "P_" + name);
            perPlan[name] = schema;
        }

        if (!LlmContractFiles.IsValid(schema, p))
        {
            return (5, "PLAN_MISMATCH");
        }

        foreach (var node in Objects(p))
        {
            if (HasKeys(node, "k", "o", "n", "m", "y"))
            {
                var kind = node["k"]!.GetValue<string>();
                var nSet = node["n"] is not null;
                var mSet = node["m"] is not null;
                var ySet = node["y"] is not null;
                if (nSet != (kind == "lastDays") || mSet != (kind == "monthOfYear") || (ySet && kind != "monthOfYear"))
                {
                    return (5, "PERIOD_FIELD_MISMATCH");
                }
            }
            else if (HasKeys(node, "slug", "ref", "mention", "currency"))
            {
                if (FilterKeys.Count(k => node[k] is not null) > 1)
                {
                    return (5, "FILTER_MULTIPLE_KEYS");
                }
            }
            else if (HasKeys(node, "kind", "percent", "amount", "currency"))
            {
                var percent = node["kind"]!.GetValue<string>() == "percent";
                if ((node["percent"] is not null) != percent || (node["amount"] is not null) == percent || (percent && node["currency"] is not null))
                {
                    return (5, "MODE_FIELD_MISMATCH");
                }
            }
            else if (HasKeys(node, "kind", "whatIf", "amount"))
            {
                var kind = node["kind"]!.GetValue<string>();
                if ((node["whatIf"] is not null) != (kind == "whatIf") || (node["amount"] is not null) != (kind == "amount"))
                {
                    return (5, "SOURCE_FIELD_MISMATCH");
                }
            }
        }

        if (p["instruments"] is JsonArray instruments && instruments.Select(i => i!.GetValue<string>()).Distinct(StringComparer.Ordinal).Count() != instruments.Count)
        {
            return (5, "INSTRUMENTS_DUPLICATE");
        }

        if (p["target"]?["currency"] is not null)
        {
            return (5, "TARGET_CURRENCY_SET");
        }

        if (name == "PL-INCOME" && p["filter"]?["slug"] is not null)
        {
            return (5, "INCOME_SLUG_SET");
        }

        return null;
    }

    private static bool HasKeys(JsonObject node, params string[] keys) => node.Count == keys.Length && keys.All(k => node.ContainsKey(k));

    private static IEnumerable<JsonObject> Objects(JsonNode? node)
    {
        if (node is JsonObject obj)
        {
            yield return obj;
            foreach (var (_, child) in obj)
            {
                foreach (var nested in Objects(child))
                {
                    yield return nested;
                }
            }
        }
    }

    private static void Collect(JsonNode? node, List<(string Key, string Value)> into)
    {
        foreach (var obj in Objects(node))
        {
            foreach (var key in TextKeys)
            {
                if (obj[key] is JsonValue value && value.TryGetValue<string>(out var text))
                {
                    into.Add((key, text));
                }
            }
        }
    }

    private static IEnumerable<(string Value, string? Currency)> Amounts(JsonNode? p)
    {
        foreach (var obj in Objects(p))
        {
            if (obj["amount"] is JsonValue value && value.TryGetValue<string>(out var text))
            {
                yield return (text, obj["currency"]?.GetValue<string>());
            }
        }
    }

    private static HashSet<decimal> NumbersIn(string foldedSent)
    {
        var numbers = new HashSet<decimal>();
        foreach (Match match in NumberRegex().Matches(foldedSent))
        {
            if (decimal.TryParse(match.Value.Replace(",", string.Empty, StringComparison.Ordinal), NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var value))
            {
                numbers.Add(value);
            }
        }

        return numbers;
    }

    private HashSet<decimal> WordValues(string foldedSent)
    {
        var values = new HashSet<decimal>();
        foreach (var (word, value) in numberWords)
        {
            if (ContainsWord(foldedSent, word))
            {
                values.Add(value);
            }
        }

        return values;
    }

    private static bool ContainsWord(string folded, string word)
    {
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

    private static int FractionDigits(string amount)
    {
        var dot = amount.IndexOf('.', StringComparison.Ordinal);
        return dot < 0 ? 0 : amount.Length - dot - 1;
    }

    private int Exponent(string currency) => threeDecimals.Contains(currency) ? 3 : noDecimals.Contains(currency) ? 0 : 2;

    private static bool IsSpace(char u) => u == ' ' || (u >= '\t' && u <= '\r') || u == '\u0085' || u == '\u00a0' || u == '\u202f' || u == '\u2009' || u == '\u2028' || u == '\u2029';

    private static bool IsInvisible(char u) =>
        (u >= '\u200b' && u <= '\u200f') || (u >= '\u202a' && u <= '\u202e') || (u >= '\u2066' && u <= '\u2069') || u == '\u061c' || u == '\u2060' || u == '\u00ad' || u == '\ufeff';

    private static char MapChar(char u)
    {
        if (u >= '\u0660' && u <= '\u0669')
        {
            return (char)('0' + (u - '\u0660'));
        }

        if (u >= '\u06f0' && u <= '\u06f9')
        {
            return (char)('0' + (u - '\u06f0'));
        }

        return u switch
        {
            '\u066b' => '.',
            '\u066c' => ',',
            '\u0623' or '\u0625' or '\u0622' or '\u0671' => '\u0627',
            '\u0649' => '\u064a',
            '\u0629' => '\u0647',
            >= 'A' and <= 'Z' => (char)(u + 0x20),
            _ => u,
        };
    }

    private static bool IsControl(char u) =>
        char.IsControl(u) || u == '\u061c' || (u >= '\u200b' && u <= '\u200f') || u == '\u2060' || (u >= '\u202a' && u <= '\u202e') || (u >= '\u2066' && u <= '\u2069') || u == '\ufeff';

    private static bool IsEmoji(int cp) => (cp >= 0x1F000 && cp <= 0x1FAFF) || (cp >= 0x2600 && cp <= 0x27BF) || cp == 0x2B50 || cp == 0x2B55;

    private static bool IsArabicScript(int cp) =>
        (cp >= 0x0600 && cp <= 0x06FF) || (cp >= 0x0750 && cp <= 0x077F) || (cp >= 0x08A0 && cp <= 0x08FF) || (cp >= 0xFB50 && cp <= 0xFDFF) || (cp >= 0xFE70 && cp <= 0xFEFF);

    [GeneratedRegex(@"\{([A-Za-z]+)\}")]
    private static partial Regex BlankRegex();

    [GeneratedRegex(@"\p{L}\.\p{L}{2}")]
    private static partial Regex LabelTldRegex();

    [GeneratedRegex(@"[0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?")]
    private static partial Regex NumberRegex();
}
