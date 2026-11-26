using System.Text.Json.Nodes;
using Json.Schema;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// T-272 AC4 to AC6: the LLM operations of the OpenAPI file are closed and bounded, and every fake-backend fixture
/// validates against the OpenAPI response and problem schemas (and the plan against the JSON Schema file).
/// </summary>
public class LlmFixtureAndOpenApiTests
{
    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private static readonly JsonObject AskFixtures = LlmContractFiles.Contract(Path.Combine("fixtures", "ask-plan-responses-v1.json"));

    private static readonly JsonObject CatFixtures = LlmContractFiles.Contract(Path.Combine("fixtures", "categorise-responses-v1.json"));

    private static readonly JsonSchema PlanSchema = LlmContractFiles.Compile(LlmContractFiles.AskPlanSchemaFile());

    private static readonly string[] SpecStatuses = ["200", "400", "401", "409", "413", "415", "422", "429", "500", "502", "503"];

    private static readonly string[] AllPlans =
    [
        "PL-SPEND", "PL-COMPARE", "PL-BREAKDOWN", "PL-TOPN", "PL-AVERAGE", "PL-INCOME", "PL-SAVED", "PL-BILLS-DUE", "PL-BUDGET-LEFT",
        "PL-SAFE-SPEND", "PL-BALANCE", "PL-WHATIF-CUT", "PL-WHATIF-SAVE", "PL-SUGGEST", "PL-INVEST", "PL-FALLBACK", "PL-REFUSE",
    ];

    [Fact]
    public void TheLlmOperationsExistAreVersionedAndInstallScoped()
    {
        var operations = Spec.Operations().ToDictionary(o => o.Id, StringComparer.Ordinal);
        Assert.Equal("/v1/ask/plan", operations["askPlan"].Path);
        Assert.Equal("/v1/categorise", operations["categorise"].Path);
        foreach (var id in new[] { "askPlan", "categorise" })
        {
            var schemes = operations[id].Body["security"]!.AsArray().SelectMany(r => r!.AsObject().Select(p => p.Key)).ToHashSet(StringComparer.Ordinal);
            Assert.Equal(["accountToken", "installToken"], schemes.Order(StringComparer.Ordinal).ToArray());
            foreach (var status in SpecStatuses)
            {
                Assert.NotNull(operations[id].Body["responses"]![status]);
            }
        }

        Assert.NotNull(operations["askPlan"].Body["responses"]!["403"]);
        Assert.Null(operations["categorise"].Body["responses"]!["403"]);
    }

    [Fact]
    public void RequestBodiesAreClosedAndBounded()
    {
        var ask = Spec.Schemas["AskPlanRequest"]!;
        Assert.False(ask["additionalProperties"]!.GetValue<bool>());
        Assert.Equal(1, ask["properties"]!["q"]!["minLength"]!.GetValue<long>());
        Assert.Equal(300, ask["properties"]!["q"]!["maxLength"]!.GetValue<long>());
        string[] languages = ["ar", "en"];
        Assert.Equal(languages, ask["properties"]!["lang"]!["enum"]!.AsArray().Select(n => n!.GetValue<string>()).ToArray());

        var cat = Spec.Schemas["CategoriseRequest"]!;
        Assert.False(cat["additionalProperties"]!.GetValue<bool>());
        var merchants = cat["properties"]!["merchants"]!;
        Assert.Equal(1, merchants["minItems"]!.GetValue<long>());
        Assert.Equal(20, merchants["maxItems"]!.GetValue<long>());
        Assert.True(merchants["uniqueItems"]!.GetValue<bool>());
        Assert.Equal(2, merchants["items"]!["minLength"]!.GetValue<long>());
        Assert.Equal(64, merchants["items"]!["maxLength"]!.GetValue<long>());

        var feedback = Spec.Schemas["SyncRequest"]!["properties"]!["llmCatFeedback"]!;
        Assert.Equal(50, feedback["maxItems"]!.GetValue<long>());
        Assert.False(Spec.Schemas["LlmCatFeedbackItem"]!["additionalProperties"]!.GetValue<bool>());
    }

    [Fact]
    public void BoundsAreEnforcedByTheSchemasNotJustDeclared()
    {
        var body = JsonNode.Parse(Spec.Operations().Single(o => o.Id == "categorise").Body["requestBody"]!["content"]!["application/json"]!["example"]!.ToJsonString())!.AsObject();

        Assert.Null(Spec.Validate(Ref("CategoriseRequest"), body));
        body["merchants"] = new JsonArray(Enumerable.Range(0, 21).Select(i => (JsonNode?)JsonValue.Create("shop " + i)).ToArray());
        Assert.NotNull(Spec.Validate(Ref("CategoriseRequest"), body));
        body["merchants"] = new JsonArray("a");
        Assert.NotNull(Spec.Validate(Ref("CategoriseRequest"), body));
        body["merchants"] = new JsonArray(new string('a', 65));
        Assert.NotNull(Spec.Validate(Ref("CategoriseRequest"), body));
        body["merchants"] = new JsonArray("same shop", "same shop");
        Assert.NotNull(Spec.Validate(Ref("CategoriseRequest"), body));

        var ask = JsonNode.Parse(Spec.Operations().Single(o => o.Id == "askPlan").Body["requestBody"]!["content"]!["application/json"]!["example"]!.ToJsonString())!.AsObject();
        Assert.Null(Spec.Validate(Ref("AskPlanRequest"), ask));
        ask["q"] = string.Empty;
        Assert.NotNull(Spec.Validate(Ref("AskPlanRequest"), ask));
        ask["q"] = new string('x', 301);
        Assert.NotNull(Spec.Validate(Ref("AskPlanRequest"), ask));
        ask["q"] = new string('x', 300);
        Assert.Null(Spec.Validate(Ref("AskPlanRequest"), ask));
        ask["planVersion"] = 2;
        Assert.NotNull(Spec.Validate(Ref("AskPlanRequest"), ask));

        var feedback = Enumerable.Range(0, 51).Select(i => (JsonNode?)JsonNode.Parse("""{"merchantNorm":"zawya coffee","verdict":"right","aiCategory":"dining","userCategory":"dining","source":"llm"}""")).ToArray();
        var sync = new JsonObject { ["catalogVersion"] = 0, ["flagsVersion"] = 0, ["llmCatFeedback"] = new JsonArray(feedback.Take(50).Select(n => JsonNode.Parse(n!.ToJsonString())).ToArray()) };
        Assert.Null(Spec.Validate(Ref("SyncRequest"), sync));
        sync["llmCatFeedback"] = new JsonArray(feedback.Select(n => JsonNode.Parse(n!.ToJsonString())).ToArray());
        Assert.NotNull(Spec.Validate(Ref("SyncRequest"), sync));
    }

    [Fact]
    public void TheNewProblemCodesAndExtensionsAreInTheContract()
    {
        var codes = Spec.Schemas["ProblemCode"]!["enum"]!.AsArray().Select(n => n!.GetValue<string>()).ToHashSet(StringComparer.Ordinal);
        foreach (var code in new[] { "LLM_QUOTA_EXHAUSTED", "LLM_CONSENT_REQUIRED", "LLM_SERVICE_PAUSED", "DEVICE_ATTESTATION_FAILED", "RATE_LIMITED", "UPSTREAM_UNAVAILABLE" })
        {
            Assert.Contains(code, codes);
        }

        var problem = Spec.Schemas["Problem"]!["properties"]!;
        Assert.NotNull(problem["quota"]);
        Assert.NotNull(problem["providerId"]);
        Assert.NotNull(Spec.Schemas["ConfigBlock"]);
        Assert.NotNull(Spec.Schemas["SyncResponse"]!["properties"]!["config"]);
    }

    [Fact]
    public void EveryAskFixtureResponseValidatesAndEveryPlanVariantHasOne()
    {
        var failures = new List<string>();
        var plans = new HashSet<string>(StringComparer.Ordinal);
        foreach (var node in AskFixtures["ok"]!.AsArray())
        {
            var name = node!["name"]!.GetValue<string>();
            var body = node["body"]!;
            if (Spec.Validate(Ref("AskPlanResponse"), body) is { } problem)
            {
                failures.Add($"{name}: {problem}");
            }

            if (!LlmContractFiles.IsValid(PlanSchema, body["plan"]))
            {
                failures.Add($"{name}: plan does not validate against ask-plan-v1.schema.json");
            }

            plans.Add(body["plan"]!["plan"]!.GetValue<string>());
            AssertQuotaConsistent(body["quota"]!, failures, name);
        }

        Assert.Empty(failures);
        Assert.Empty(AllPlans.Except(plans, StringComparer.Ordinal));
        Assert.Contains(AskFixtures["ok"]!.AsArray(), n => n!["body"]!["counted"]!.GetValue<bool>() == false);
        Assert.Contains(AskFixtures["ok"]!.AsArray(), n => n!["body"]!["plan"]!["t"] is JsonObject);
    }

    [Fact]
    public void EveryCategoriseFixtureResponseValidatesAndEveryStatusHasOne()
    {
        var failures = new List<string>();
        var statuses = new HashSet<string>(StringComparer.Ordinal);
        var sources = new HashSet<string>(StringComparer.Ordinal);
        foreach (var node in CatFixtures["ok"]!.AsArray())
        {
            var name = node!["name"]!.GetValue<string>();
            var body = node["body"]!;
            if (Spec.Validate(Ref("CategoriseResponse"), body) is { } problem)
            {
                failures.Add($"{name}: {problem}");
            }

            var merchants = node["merchants"]!.AsArray().Select(m => m!.GetValue<string>()).ToList();
            var results = body["results"]!.AsArray();
            if (!merchants.SequenceEqual(results.Select(r => r!["merchant"]!.GetValue<string>())))
            {
                failures.Add($"{name}: results are not in request order");
            }

            var llmOk = results.Count(r => r!["status"]!.GetValue<string>() == "ok" && r["source"]!.GetValue<string>() == "llm");
            if (body["counted"]!.GetValue<int>() != llmOk)
            {
                failures.Add($"{name}: counted must equal the number of ok results from the llm");
            }

            foreach (var result in results)
            {
                statuses.Add(result!["status"]!.GetValue<string>());
                if (result["source"] is { } source)
                {
                    sources.Add(source.GetValue<string>());
                }

                var ok = result["status"]!.GetValue<string>() == "ok";
                if (ok != (result["category"] is not null))
                {
                    failures.Add($"{name}: category is set exactly for ok results");
                }
            }

            AssertQuotaConsistent(body["quota"]!, failures, name);
        }

        Assert.Empty(failures);
        string[] expectedStatuses = ["low_confidence", "ok", "quota", "rejected", "unknown"];
        string[] expectedSources = ["cache", "catalog", "llm"];
        Assert.Equal(expectedStatuses, statuses.Order(StringComparer.Ordinal).ToArray());
        Assert.Equal(expectedSources, sources.Order(StringComparer.Ordinal).ToArray());
    }

    [Theory]
    [InlineData("ask-plan-responses-v1.json", "askPlan")]
    [InlineData("categorise-responses-v1.json", "categorise")]
    public void EveryProblemFixtureValidatesAndUsesAStatusTheOperationDeclares(string file, string operationId)
    {
        var fixtures = LlmContractFiles.Contract(Path.Combine("fixtures", file));
        var operation = Spec.Operations().Single(o => o.Id == operationId);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var node in fixtures["problems"]!.AsArray())
        {
            var code = node!["code"]!.GetValue<string>();
            var status = node["status"]!.GetValue<int>();
            var body = node["body"]!;

            Assert.Null(Spec.Validate(Ref("Problem"), body));
            Assert.Equal(code, body["code"]!.GetValue<string>());
            Assert.Equal(status, body["status"]!.GetValue<int>());
            Assert.NotNull(operation.Body["responses"]![status.ToString(System.Globalization.CultureInfo.InvariantCulture)]);
            Assert.True(seen.Add(code), $"{code} appears twice");
            Assert.Equal(code == "LLM_QUOTA_EXHAUSTED", body["quota"] is not null);
            Assert.Equal(code == "LLM_CONSENT_REQUIRED", body["providerId"] is not null);
        }

        string[] expected = file.StartsWith("ask", StringComparison.Ordinal)
            ? ["DEVICE_ATTESTATION_FAILED", "LLM_CONSENT_REQUIRED", "LLM_QUOTA_EXHAUSTED", "LLM_SERVICE_PAUSED", "RATE_LIMITED", "UNKNOWN_FIELD", "UPSTREAM_UNAVAILABLE", "VALIDATION_FAILED"]
            : ["DEVICE_ATTESTATION_FAILED", "LLM_CONSENT_REQUIRED", "LLM_SERVICE_PAUSED", "RATE_LIMITED", "UNKNOWN_FIELD", "UPSTREAM_UNAVAILABLE", "VALIDATION_FAILED"];
        Assert.Equal(expected, seen.Order(StringComparer.Ordinal).ToArray());
    }

    [Fact]
    public void FixturesAndVectorsCarryNoRealLookingData()
    {
        // AC6: every value is synthetic. Guards the obvious leaks: e-mail shapes, Egyptian mobile numbers, IBANs, URLs other than the contract's own host and the deliberate x.y of the template-rejection vector.
        foreach (var text in new[]
                 {
                     AskFixtures.ToJsonString(), CatFixtures.ToJsonString(), LlmContractFiles.Vectors("ask-plan-v1.json").ToJsonString(),
                     LlmContractFiles.Vectors("ask-binding-v1.json").ToJsonString(), LlmContractFiles.Vectors("cat-binding-v1.json").ToJsonString(),
                 })
        {
            Assert.DoesNotMatch(@"[A-Za-z0-9._-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", text);
            Assert.DoesNotMatch(@"01[0125][0-9]{8}", text);
            Assert.DoesNotMatch(@"EG[0-9]{2}[0-9]{23,25}", text);
            Assert.DoesNotMatch(@"https?://(?!zaghlol\.app/|x\.y)", text);
        }
    }

    private static JsonNode Ref(string schema) => JsonNode.Parse($$"""{"$ref":"#/components/schemas/{{schema}}"}""")!;

    private static void AssertQuotaConsistent(JsonNode quota, List<string> failures, string name)
    {
        var limit = quota["limit"]!.GetValue<int>();
        var used = quota["used"]!.GetValue<int>();
        var remaining = quota["remaining"]!.GetValue<int>();
        if (used + remaining != limit)
        {
            failures.Add($"{name}: quota used + remaining must equal limit");
        }
    }
}
