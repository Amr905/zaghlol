using System.Text.Json.Nodes;
using Json.Schema;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// T-322 AC1 and AC2: the shared plan vectors against <c>ask-plan-v1.schema.json</c> and the section 2.4 rules, and the
/// provider keyword subset of the schema files. The same vectors are run by the Dart tests (T-331).
/// </summary>
public class AskPlanVectorTests
{
    private static readonly JsonObject Vectors = LlmContractFiles.Vectors("ask-plan-v1.json");

    private static readonly JsonObject SchemaFile = LlmContractFiles.AskPlanSchemaFile();

    private static readonly JsonSchema Schema = LlmContractFiles.Compile(SchemaFile);

    private static readonly AskPlanReference Reference = new(Vectors);

    private static readonly string[] AllPlans =
    [
        "PL-SPEND", "PL-COMPARE", "PL-BREAKDOWN", "PL-TOPN", "PL-AVERAGE", "PL-INCOME", "PL-SAVED", "PL-BILLS-DUE", "PL-BUDGET-LEFT",
        "PL-SAFE-SPEND", "PL-BALANCE", "PL-WHATIF-CUT", "PL-WHATIF-SAVE", "PL-SUGGEST", "PL-INVEST", "PL-FALLBACK", "PL-REFUSE",
    ];

    private static readonly string[] SchemaKeywords =
    [
        "$schema", "$id", "$comment", "title", "type", "properties", "required", "additionalProperties", "enum", "anyOf", "$defs",
        "$ref", "pattern", "minimum", "maximum", "minItems", "maxItems", "items",
    ];

    private static IEnumerable<JsonObject> PlanVectors => Vectors["plans"]!.AsArray().Select(v => v!.AsObject());

    [Fact]
    public void EveryValidVectorPassesTheSchemaAndTheRulesAndEveryInvalidOneFailsAtItsDeclaredStep()
    {
        var failures = new List<string>();
        foreach (var vector in PlanVectors)
        {
            var id = vector["id"]!.GetValue<string>();
            var plan = vector["plan"]!;
            var expect = vector["expect"]!;
            var schemaValid = LlmContractFiles.IsValid(Schema, plan);
            if (expect["outcome"]!.GetValue<string>() == "accept")
            {
                var result = schemaValid ? Reference.CheckPlan(plan.AsObject(), vector["sent"]!.GetValue<string>()) : (1, "SCHEMA_INVALID");
                if (result is not null)
                {
                    failures.Add($"{id}: expected accept, got step {result.Value.Item1} {result.Value.Item2}");
                }

                continue;
            }

            var step = expect["step"]!.GetValue<int>();
            var reason = expect["reason"]!.GetValue<string>();
            if (step == 1)
            {
                if (schemaValid)
                {
                    failures.Add($"{id}: expected a schema failure, but the schema accepted it");
                }

                if (reason != "SCHEMA_INVALID")
                {
                    failures.Add($"{id}: step 1 reason must be SCHEMA_INVALID");
                }

                continue;
            }

            if (!schemaValid)
            {
                failures.Add($"{id}: declared step {step} but the schema already rejects it");
                continue;
            }

            var outcome = Reference.CheckPlan(plan.AsObject(), vector["sent"]!.GetValue<string>());
            if (outcome is null || outcome.Value.Item1 != step || outcome.Value.Item2 != reason)
            {
                failures.Add($"{id}: expected step {step} {reason}, got {(outcome is null ? "accept" : $"step {outcome.Value.Item1} {outcome.Value.Item2}")}");
            }

            if (expect["counted"]!.GetValue<bool>())
            {
                failures.Add($"{id}: a validator failure is never counted");
            }
        }

        Assert.Empty(failures);
    }

    [Fact]
    public void EveryPlanOfTheCatalogueHasAValidVectorAndTheSchemaListsExactlyThosePlans()
    {
        var covered = PlanVectors
            .Where(v => v["expect"]!["outcome"]!.GetValue<string>() == "accept")
            .Select(v => v["plan"]!["plan"]!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal);
        Assert.Empty(AllPlans.Except(covered, StringComparer.Ordinal));

        var inSchema = SchemaFile["properties"]!["plan"]!["enum"]!.AsArray().Select(n => n!.GetValue<string>()).ToList();
        Assert.Equal(AllPlans.Order(StringComparer.Ordinal), inSchema.Order(StringComparer.Ordinal));
        foreach (var plan in AllPlans)
        {
            Assert.NotNull(SchemaFile["$defs"]![("P_" + plan)]);
        }
    }

    [Fact]
    public void TheSrsExamplesAreVectors()
    {
        var ids = PlanVectors.Select(v => v["id"]!.GetValue<string>()).ToHashSet(StringComparer.Ordinal);
        string[] required =
        [
            "valid-compare-dining",
            "valid-average-day",
            "valid-saved",
            "valid-whatif-cut-percent",
            "invalid-whatif-percent-150",
            "invalid-unknown-plan-transfer",
            "invalid-plain-account-field",
            "invalid-ref-not-in-sent-text",
            "invalid-mention-not-substring",
            "valid-template-ar-whatif",
        ];
        Assert.Empty(required.Except(ids, StringComparer.Ordinal));
    }

    [Fact]
    public void EveryRejectionClassOfSection23And24HasAVector()
    {
        var reasons = PlanVectors
            .Where(v => v["expect"]!["outcome"]!.GetValue<string>() == "fallback")
            .Select(v => v["expect"]!["reason"]!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal);
        string[] steps2To5 =
        [
            "SCHEMA_INVALID", "REF_NOT_IN_TEXT", "PLAIN_NAME", "MENTION_NOT_IN_TEXT", "AMOUNT_NOT_IN_TEXT", "AMOUNT_FRACTION_TOO_LONG", "PLAN_MISMATCH",
            "FILTER_MULTIPLE_KEYS", "PERIOD_FIELD_MISMATCH", "MODE_FIELD_MISMATCH", "SOURCE_FIELD_MISMATCH", "INSTRUMENTS_DUPLICATE",
            "TARGET_CURRENCY_SET", "INCOME_SLUG_SET",
        ];
        Assert.Empty(steps2To5.Except(reasons, StringComparer.Ordinal));

        var order = Vectors["templateRules"]!["order"]!.AsArray().Select(n => "TEMPLATE_" + n!.GetValue<string>()).ToList();
        var templateReasons = Vectors["templates"]!.AsArray()
            .Select(t => t!["expect"]!.GetValue<string>())
            .ToHashSet(StringComparer.Ordinal);
        Assert.Empty(order.Except(templateReasons, StringComparer.Ordinal));
        Assert.Contains("ok", templateReasons);
    }

    [Fact]
    public void TemplateVectorsGetTheirDeclaredOutcome()
    {
        var failures = new List<string>();
        foreach (var node in Vectors["templates"]!.AsArray())
        {
            var vector = node!.AsObject();
            var actual = Reference.CheckTemplate(
                vector["plan"]!.GetValue<string>(),
                vector["requestLang"]!.GetValue<string>(),
                vector["t"]!["lang"]!.GetValue<string>(),
                vector["t"]!["text"]!.GetValue<string>()) ?? "ok";
            if (actual != vector["expect"]!.GetValue<string>())
            {
                failures.Add($"{vector["id"]!.GetValue<string>()}: expected {vector["expect"]!.GetValue<string>()}, got {actual}");
            }
        }

        Assert.True(failures.Count == 0, string.Join(" | ", failures));
    }

    [Fact]
    public void TemplatesOfPlanVectorsFollowTheGrammar()
    {
        foreach (var vector in PlanVectors.Where(v => v["plan"]!["t"] is JsonObject))
        {
            var t = vector["plan"]!["t"]!;
            if (vector["expect"]!["templateReason"]?.GetValue<string>() is { } declared)
            {
                Assert.Equal("TEMPLATE_PLAIN_NAME", declared);
                Assert.True(Reference.TemplateNamesAName(t["text"]!.GetValue<string>()), vector["id"]!.GetValue<string>());
                continue;
            }

            Assert.Null(Reference.CheckTemplate(vector["plan"]!["plan"]!.GetValue<string>(), vector["lang"]!.GetValue<string>(), t["lang"]!.GetValue<string>(), t["text"]!.GetValue<string>()));
        }
    }

    [Fact]
    public void MentionNormalisationCasesGetTheirDeclaredOutcome()
    {
        foreach (var node in Vectors["normalisation"]!["cases"]!.AsArray())
        {
            var vector = node!.AsObject();
            var actual = AskPlanReference.MentionOccurs(AskPlanReference.Fold(vector["sent"]!.GetValue<string>()), vector["mention"]!.GetValue<string>());
            Assert.True(actual == vector["expect"]!.GetValue<bool>(), vector["id"]!.GetValue<string>());
        }
    }

    [Fact]
    public void BothSchemasUseOnlyTheKeywordsThatTheProvidersAccept()
    {
        foreach (var file in new[] { SchemaFile, LlmContractFiles.CatResultSchemaFile() })
        {
            var violations = new List<string>();
            Assert.Equal("object", file["type"]!.GetValue<string>());
            Assert.Null(file["anyOf"]);
            CheckSubset(file, "#", violations);
            Assert.Empty(violations);
            Assert.Contains("$comment", file.Select(p => p.Key));
        }
    }

    [Fact]
    public void ThePlanSchemaDocumentsItsProviderExceptionsInTheComment()
    {
        var comment = SchemaFile["$comment"]!.GetValue<string>();
        foreach (var topic in new[] { "EXCEPTIONS AND ADAPTER WORKAROUNDS", "Anthropic", "Gemini", "OpenAI", "STEP 5" })
        {
            Assert.Contains(topic, comment, StringComparison.Ordinal);
        }
    }

    [Fact]
    public void ACategoriseResultSchemaAcceptsTheStructuredOutputAndNothingElse()
    {
        var schema = LlmContractFiles.Compile(LlmContractFiles.CatResultSchemaFile());
        Assert.True(LlmContractFiles.IsValid(schema, JsonNode.Parse("""{"r":[{"i":0,"c":"dining","p":88},{"i":1,"c":"unknown","p":0}]}""")));
        Assert.True(LlmContractFiles.IsValid(schema, JsonNode.Parse("""{"r":[]}""")));
        foreach (var bad in new[]
                 {
                     """{"r":[{"i":0,"c":"dining","p":101}]}""",
                     """{"r":[{"i":0,"c":"dining","p":-1}]}""",
                     """{"r":[{"i":20,"c":"dining","p":50}]}""",
                     """{"r":[{"i":0,"c":"pizza","p":50}]}""",
                     """{"r":[{"i":0,"c":"dining","p":50,"name":"zawya coffee"}]}""",
                     """{"r":[{"i":0,"c":"dining"}]}""",
                     """{"r":[{"i":0.5,"c":"dining","p":50}]}""",
                     """{"r":[{"i":0,"c":"dining","p":50}],"note":"x"}""",
                     """{"x":[]}""",
                 })
        {
            Assert.False(LlmContractFiles.IsValid(schema, JsonNode.Parse(bad)), bad);
        }

        var twentyOne = new JsonArray(Enumerable.Range(0, 21).Select(i => (JsonNode?)JsonNode.Parse($$"""{"i":{{i % 20}},"c":"dining","p":50}""")).ToArray());
        Assert.False(LlmContractFiles.IsValid(schema, new JsonObject { ["r"] = twentyOne }));
    }

    private static void CheckSubset(JsonNode? node, string where, List<string> violations)
    {
        if (node is not JsonObject schema)
        {
            return;
        }

        foreach (var (keyword, value) in schema)
        {
            if (!SchemaKeywords.Contains(keyword, StringComparer.Ordinal))
            {
                violations.Add($"{where}: keyword '{keyword}' is outside the provider subset");
            }

            switch (keyword)
            {
                case "properties" or "$defs":
                    foreach (var (name, child) in value!.AsObject())
                    {
                        CheckSubset(child, $"{where}/{keyword}/{name}", violations);
                    }

                    break;
                case "anyOf":
                    foreach (var child in value!.AsArray())
                    {
                        CheckSubset(child, where + "/anyOf", violations);
                    }

                    break;
                case "items" or "additionalProperties":
                    CheckSubset(value, $"{where}/{keyword}", violations);
                    break;
            }
        }

        if (schema["properties"] is JsonObject properties)
        {
            Assert.True(schema["additionalProperties"] is JsonValue { } ap && !ap.GetValue<bool>(), $"{where}: objects must set additionalProperties:false");
            var required = (schema["required"] as JsonArray ?? []).Select(n => n!.GetValue<string>()).ToList();
            Assert.Equal(properties.Select(p => p.Key).Order(StringComparer.Ordinal), required.Order(StringComparer.Ordinal));
        }
    }
}
