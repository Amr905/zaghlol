using System.Collections.Concurrent;
using System.Globalization;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Json.Schema;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

namespace Zaghlol.Application.Llm.Plans;

/// <summary>
/// Server-side validation of a model plan (<c>ask-plan/1</c>, ask-llm.md section 2.4, FR-LLM-05/06/07/35). Pure: no I/O and no state
/// besides the compiled schema. Steps 1 to 5 failing give a fallback; step 6 (template grammar) failing drops the template only.
/// Plan text, template text and question text never reach a log, an exception or a result: only <see cref="PlanReason"/> codes do.
/// </summary>
public sealed partial class PlanValidator
{
    /// <summary>Hard cap on the plan JSON before any parsing work (a valid plan is well under 2 KB).</summary>
    public const int MaxPlanJsonLength = 16 * 1024;

    private const string SchemaResource = "Zaghlol.Llm.ask-plan-v1.schema.json";

    private static readonly EvaluationOptions Options = new() { OutputFormat = OutputFormat.List, RequireFormatValidation = true };

    private static readonly string[] FilterKeys = ["slug", "ref", "mention"];

    private static readonly Lazy<JsonObject> SchemaFile = new(LoadSchemaFile);

    private static readonly Lazy<JsonSchema> RootSchema = new(() => JsonSchema.FromText(SchemaFile.Value.ToJsonString()));

    private static readonly ConcurrentDictionary<string, JsonSchema?> PerPlan = new(StringComparer.Ordinal);

    private readonly NumberWords numberWords;
    private readonly List<string> aliases;
    private readonly HashSet<string> threeDecimals;
    private readonly HashSet<string> noDecimals;
    private readonly ILogger logger;

    public PlanValidator(PlanValidatorData? data = null, ILogger<PlanValidator>? logger = null)
    {
        var d = data ?? PlanValidatorData.Default;
        numberWords = new NumberWords(d.NumberWords);
        aliases = d.RegistryAliases.Select(PlanText.Fold).Where(a => a.Length > 0).ToList();
        threeDecimals = d.ThreeDecimalCurrencies.ToHashSet(StringComparer.Ordinal);
        noDecimals = d.ZeroDecimalCurrencies.ToHashSet(StringComparer.Ordinal);
        this.logger = logger ?? NullLogger<PlanValidator>.Instance;
    }

    /// <summary>
    /// Validates <paramref name="planJson"/> (the model reply) against the text that was sent (<paramref name="sentText"/>, placeholders
    /// already inserted) and the request language (<c>ar</c> or <c>en</c>).
    /// </summary>
    public PlanValidationResult Validate(JsonElement planJson, string sentText, string lang)
    {
        var failure = CheckPlan(planJson, sentText);
        if (failure is { } reason)
        {
            LogPlanRejected(logger, reason);
            return PlanValidationResult.Fallback(reason);
        }

        var (template, rejection) = CheckTemplate(planJson, lang);
        if (rejection is { } dropped)
        {
            LogTemplateDropped(logger, dropped);
        }

        return PlanValidationResult.Valid(planJson.Clone(), template, rejection);
    }

    private PlanReason? CheckPlan(JsonElement planJson, string sent)
    {
        // Step 1: the schema. Size first, then the closed shape.
        if (planJson.ValueKind != JsonValueKind.Object || planJson.GetRawText().Length > MaxPlanJsonLength)
        {
            return PlanReason.SchemaInvalid;
        }

        var node = JsonNode.Parse(planJson.GetRawText());
        if (node is not JsonObject plan || !IsValid(RootSchema.Value, plan))
        {
            return PlanReason.SchemaInvalid;
        }

        // Step 2: every ref occurs verbatim; no plain registry name in any string of p.
        var p = plan["p"];
        var refs = new List<string>();
        var strings = new List<string>();
        var mentions = new List<string>();
        foreach (var obj in Objects(p))
        {
            AddIfString(obj["ref"], refs);
            AddIfString(obj["mention"], mentions);
            foreach (var (_, value) in obj)
            {
                AddIfString(value, strings);
            }
        }

        if (refs.Any(r => !sent.Contains(r, StringComparison.Ordinal)))
        {
            return PlanReason.RefNotInText;
        }

        foreach (var text in strings)
        {
            var folded = PlanText.Fold(text);
            if (aliases.Any(a => PlanText.ContainsWord(folded, a)))
            {
                return PlanReason.PlainName;
            }
        }

        // Step 3: mention is a substring of the normalised sent text.
        var foldedSent = PlanText.Fold(sent);
        foreach (var mention in mentions)
        {
            var folded = PlanText.Fold(mention);
            if (folded.Length == 0 || !foldedSent.Contains(folded, StringComparison.Ordinal))
            {
                return PlanReason.MentionNotInText;
            }
        }

        // Step 4: amounts come from the question.
        HashSet<decimal>? known = null;
        HashSet<decimal>? words = null;
        foreach (var obj in Objects(p))
        {
            if (obj["amount"] is not JsonValue value || !value.TryGetValue<string>(out var amount))
            {
                continue;
            }

            known ??= NumbersIn(foldedSent);
            words ??= numberWords.ValuesIn(foldedSent);
            if (!decimal.TryParse(amount, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var number) || !(known.Contains(number) || words.Contains(number)))
            {
                return PlanReason.AmountNotInText;
            }

            if (obj["currency"] is JsonValue c && c.TryGetValue<string>(out var currency) && FractionDigits(amount) > Exponent(currency))
            {
                return PlanReason.AmountFractionTooLong;
            }
        }

        // Step 5: cross-field rules.
        return CrossField(plan);
    }

    private static PlanReason? CrossField(JsonObject plan)
    {
        var name = plan["plan"]!.GetValue<string>();
        var p = plan["p"]!;
        var perPlan = PerPlan.GetOrAdd(name, CompilePlan);
        if (perPlan is null || !IsValid(perPlan, p))
        {
            return PlanReason.PlanMismatch;
        }

        foreach (var node in Objects(p))
        {
            if (HasKeys(node, "k", "o", "n", "m", "y"))
            {
                var kind = node["k"]!.GetValue<string>();
                if ((node["n"] is not null) != (kind == "lastDays") || (node["m"] is not null) != (kind == "monthOfYear") || (node["y"] is not null && kind != "monthOfYear"))
                {
                    return PlanReason.PeriodFieldMismatch;
                }
            }
            else if (HasKeys(node, "slug", "ref", "mention", "currency"))
            {
                if (FilterKeys.Count(k => node[k] is not null) > 1)
                {
                    return PlanReason.FilterMultipleKeys;
                }
            }
            else if (HasKeys(node, "kind", "percent", "amount", "currency"))
            {
                var percent = node["kind"]!.GetValue<string>() == "percent";
                if ((node["percent"] is not null) != percent || (node["amount"] is not null) == percent || (percent && node["currency"] is not null))
                {
                    return PlanReason.ModeFieldMismatch;
                }
            }
            else if (HasKeys(node, "kind", "whatIf", "amount"))
            {
                var kind = node["kind"]!.GetValue<string>();
                if ((node["whatIf"] is not null) != (kind == "whatIf") || (node["amount"] is not null) != (kind == "amount"))
                {
                    return PlanReason.SourceFieldMismatch;
                }
            }
        }

        if (p["instruments"] is JsonArray instruments && instruments.Select(i => i!.GetValue<string>()).Distinct(StringComparer.Ordinal).Count() != instruments.Count)
        {
            return PlanReason.InstrumentsDuplicate;
        }

        if (p["target"]?["currency"] is not null)
        {
            return PlanReason.TargetCurrencySet;
        }

        if (name == "PL-INCOME" && p["filter"]?["slug"] is not null)
        {
            return PlanReason.IncomeSlugSet;
        }

        return null;
    }

    private static (PlanTemplate? Template, PlanReason? Rejection) CheckTemplate(JsonElement planJson, string lang)
    {
        if (!planJson.TryGetProperty("t", out var t) || t.ValueKind != JsonValueKind.Object)
        {
            return (null, null);
        }

        // The schema leaves t unconstrained so that a bad template never fails the plan: read it defensively.
        var templateLang = t.TryGetProperty("lang", out var l) && l.ValueKind == JsonValueKind.String ? l.GetString() : null;
        var text = t.TryGetProperty("text", out var x) && x.ValueKind == JsonValueKind.String ? x.GetString() : null;
        if (templateLang is null || text is null)
        {
            return (null, PlanReason.TemplateLength);
        }

        var plan = planJson.GetProperty("plan").GetString()!;
        var rejection = TemplateGrammar.Check(plan, lang, templateLang, text);
        return rejection is null ? (new PlanTemplate(templateLang, text), null) : (null, rejection);
    }

    private static JsonSchema? CompilePlan(string name)
    {
        var file = SchemaFile.Value;
        if (file["$defs"]?["P_" + name] is null)
        {
            return null;
        }

        var root = new JsonObject
        {
            ["$schema"] = file["$schema"]!.GetValue<string>(),
            ["$ref"] = "#/$defs/P_" + name,
            ["$defs"] = JsonNode.Parse(file["$defs"]!.ToJsonString()),
        };
        return JsonSchema.FromText(root.ToJsonString());
    }

    private static JsonObject LoadSchemaFile()
    {
        using var stream = typeof(PlanValidator).Assembly.GetManifestResourceStream(SchemaResource)
            ?? throw new InvalidOperationException("The embedded ask-plan schema is missing.");
        var file = JsonNode.Parse(stream)!.AsObject();

        // $id is stripped so the schema can be compiled more than once (whole file and per plan).
        file.Remove("$id");
        return file;
    }

    private static bool IsValid(JsonSchema schema, JsonNode? instance) => schema.Evaluate(instance, Options).IsValid;

    private static bool HasKeys(JsonObject node, params string[] keys) => node.Count == keys.Length && keys.All(k => node.ContainsKey(k));

    private static void AddIfString(JsonNode? node, List<string> into)
    {
        if (node is JsonValue value && value.TryGetValue<string>(out var text))
        {
            into.Add(text);
        }
    }

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
        else if (node is JsonArray array)
        {
            foreach (var child in array)
            {
                foreach (var nested in Objects(child))
                {
                    yield return nested;
                }
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

    private static int FractionDigits(string amount)
    {
        var dot = amount.IndexOf('.', StringComparison.Ordinal);
        return dot < 0 ? 0 : amount.Length - dot - 1;
    }

    private int Exponent(string currency) => threeDecimals.Contains(currency) ? 3 : noDecimals.Contains(currency) ? 0 : 2;

    [LoggerMessage(EventId = 1, Level = LogLevel.Debug, Message = "Plan rejected: {Reason}")]
    private static partial void LogPlanRejected(ILogger logger, PlanReason reason);

    [LoggerMessage(EventId = 2, Level = LogLevel.Debug, Message = "Template dropped: {Reason}")]
    private static partial void LogTemplateDropped(ILogger logger, PlanReason reason);

    [GeneratedRegex(@"[0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?", RegexOptions.None, matchTimeoutMilliseconds: 200)]
    private static partial Regex NumberRegex();
}
