using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Llm.Plans;

namespace Zaghlol.Application.Tests.Llm.Plans;

/// <summary>T-330: the section 2.4 validator against the shared vectors (AC1), the template classes (AC2), the fallback rule (AC3) and the no-logging rule (AC4).</summary>
public class PlanValidatorTests
{
    private static readonly JsonObject Vectors = JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "vectors", "ask-plan-v1.json")))!.AsObject();

    private static readonly PlanValidator Validator = new();

    public static TheoryData<string> PlanVectorIds()
    {
        var data = new TheoryData<string>();
        foreach (var v in Vectors["plans"]!.AsArray())
        {
            data.Add(v!["id"]!.GetValue<string>());
        }

        return data;
    }

    [Theory]
    [MemberData(nameof(PlanVectorIds))]
    public void Ac1_EveryPlanVectorGivesItsDeclaredOutcomeAndReason(string id)
    {
        var vector = Vectors["plans"]!.AsArray().Select(v => v!.AsObject()).Single(v => v["id"]!.GetValue<string>() == id);
        var json = JsonDocument.Parse(vector["plan"]!.ToJsonString()).RootElement;
        var result = Validator.Validate(json, vector["sent"]!.GetValue<string>(), vector["lang"]!.GetValue<string>());
        var expect = vector["expect"]!;
        if (expect["outcome"]!.GetValue<string>() == "accept")
        {
            Assert.True(result.IsValid, result.Reason?.Code());
            Assert.Null(result.Reason);
            if (expect["templateReason"] is JsonNode templateReason)
            {
                Assert.Null(result.Template);
                Assert.Equal(templateReason.GetValue<string>(), result.TemplateRejection!.Value.Code());
            }
            else if (vector["plan"]!["t"] is JsonObject)
            {
                Assert.NotNull(result.Template);
            }
        }
        else
        {
            Assert.False(result.IsValid);
            Assert.Equal(expect["reason"]!.GetValue<string>(), result.Reason!.Value.Code());
            Assert.Null(result.Template);
        }
    }

    public static TheoryData<string> TemplateVectorIds()
    {
        var data = new TheoryData<string>();
        foreach (var v in Vectors["templates"]!.AsArray())
        {
            data.Add(v!["id"]!.GetValue<string>());
        }

        return data;
    }

    [Theory]
    [MemberData(nameof(TemplateVectorIds))]
    public void Ac1_EveryTemplateVectorGivesItsDeclaredReason(string id)
    {
        var vector = Vectors["templates"]!.AsArray().Select(v => v!.AsObject()).Single(v => v["id"]!.GetValue<string>() == id);
        var reason = TemplateGrammar.Check(
            vector["plan"]!.GetValue<string>(),
            vector["requestLang"]!.GetValue<string>(),
            vector["t"]!["lang"]!.GetValue<string>(),
            vector["t"]!["text"]!.GetValue<string>());
        Assert.Equal(vector["expect"]!.GetValue<string>(), reason is null ? "ok" : reason.Value.Code());
    }

    [Fact]
    public void Ac1_NormalisationCasesOfTheMentionRule()
    {
        foreach (var node in Vectors["normalisation"]!["cases"]!.AsArray())
        {
            var v = node!.AsObject();
            var mention = PlanText.Fold(v["mention"]!.GetValue<string>());
            var actual = mention.Length > 0 && PlanText.Fold(v["sent"]!.GetValue<string>()).Contains(mention, StringComparison.Ordinal);
            Assert.True(actual == v["expect"]!.GetValue<bool>(), v["id"]!.GetValue<string>());
        }
    }

    public static TheoryData<string, string, PlanReason> TemplateClasses() => new()
    {
        { "لو قللت {target} بـ 7", "ar", PlanReason.TemplateDigit },
        { "لو قللت {target} بـ٧", "ar", PlanReason.TemplateDigit },
        { "لو قللت {target} ⟦ACCOUNT_1⟧", "ar", PlanReason.TemplatePlaceholder },
        { "لو قللت { target", "ar", PlanReason.TemplateBadBlank },
        { "لو قللت {target} وكمان {amount}", "ar", PlanReason.TemplateBadBlank },
        { "لو قللت {target} و {target}", "ar", PlanReason.TemplateDuplicateBlank },
        { "لو قللت {target} @zaghlol", "ar", PlanReason.TemplateAt },
        { "لو قللت {target} https://x", "ar", PlanReason.TemplateLink },
        { "لو قللت {target} www.x", "ar", PlanReason.TemplateLink },
        { "لو قللت {target} example.com", "ar", PlanReason.TemplateLink },
        { "لو قللت {target} *كتير*", "ar", PlanReason.TemplateMarkup },
        { "لو قللت {target} ‮", "ar", PlanReason.TemplateControl },
        { "لو قللت {target} \U0001F389\U0001F389", "ar", PlanReason.TemplateEmoji },
        { "you will save lots of money on {target} dear friend", "ar", PlanReason.TemplateScript },
        { "you will save on {target} م", "en", PlanReason.TemplateScript },
        { new string('a', 201), "en", PlanReason.TemplateLength },
    };

    [Theory]
    [MemberData(nameof(TemplateClasses))]
    public void Ac2_AndAc3_EachRejectionClassDropsTheTemplateAndKeepsThePlan(string text, string lang, PlanReason expected)
    {
        var vectorId = "valid-template-ar-whatif";
        var vector = Vectors["plans"]!.AsArray().Select(v => v!.AsObject()).Single(v => v["id"]!.GetValue<string>() == vectorId);
        var plan = JsonNode.Parse(vector["plan"]!.ToJsonString())!.AsObject();
        plan["t"] = new JsonObject { ["lang"] = lang, ["text"] = text };
        var result = Validator.Validate(JsonDocument.Parse(plan.ToJsonString()).RootElement, vector["sent"]!.GetValue<string>(), lang);

        Assert.True(result.IsValid);
        Assert.Null(result.Template);
        Assert.Equal(expected, result.TemplateRejection);
        Assert.Equal("PL-WHATIF-CUT", result.Plan.GetProperty("plan").GetString());
    }

    [Theory]
    [InlineData("{\"v\":1,\"v\":1,\"plan\":\"PL-SPEND\",\"p\":{}}")]
    [InlineData("{\"v\":1,\"plan\":\"PL-SPEND\",\"p\":{\"filter\":{\"mention\":\"zq-secret-a\",\"mention\":\"zq-secret-b\"}}}")]
    [InlineData("{\"v\":1,\"plan\":\"PL-SPEND\",\"p\":{},\"t\":{\"text\":\"zq-secret-a\",\"text\":\"zq-secret-b\"}}")]
    public void M1_ADuplicateKeyIsSchemaInvalidAndNeverThrowsNorLogsPlanText(string raw)
    {
        var logger = new CapturingLogger();
        var validator = new PlanValidator(logger: logger);
        var json = JsonDocument.Parse(raw).RootElement;

        var result = validator.Validate(json, "how much did I spend?", "en");

        Assert.False(result.IsValid);
        Assert.Equal(PlanReason.SchemaInvalid, result.Reason);
        Assert.DoesNotContain(logger.Lines, l => l.Contains("zq-secret", StringComparison.Ordinal));
    }

    [Fact]
    public void M1_ADefaultJsonElementIsSchemaInvalid()
    {
        var result = Validator.Validate(default, "x", "en");

        Assert.Equal(PlanReason.SchemaInvalid, result.Reason);
    }

    private sealed class CapturingLogger : Microsoft.Extensions.Logging.ILogger<PlanValidator>
    {
        public List<string> Lines { get; } = [];

        public IDisposable? BeginScope<TState>(TState state)
            where TState : notnull => null;

        public bool IsEnabled(Microsoft.Extensions.Logging.LogLevel logLevel) => true;

        public void Log<TState>(Microsoft.Extensions.Logging.LogLevel logLevel, Microsoft.Extensions.Logging.EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
            Lines.Add(formatter(state, exception) + exception);
    }

    [Fact]
    public void Ac3_StepOneToFiveFailuresAreFallbacksNotPartialPlans()
    {
        var vector = Vectors["plans"]!.AsArray().Select(v => v!.AsObject()).Single(v => v["id"]!.GetValue<string>() == "valid-template-ar-whatif");
        var plan = JsonNode.Parse(vector["plan"]!.ToJsonString())!.AsObject();
        plan["plan"] = "PL-SPEND";
        var result = Validator.Validate(JsonDocument.Parse(plan.ToJsonString()).RootElement, vector["sent"]!.GetValue<string>(), "ar");
        Assert.False(result.IsValid);
        Assert.Equal(PlanReason.PlanMismatch, result.Reason);
        Assert.Null(result.Template);
    }

    [Theory]
    [InlineData("[]")]
    [InlineData("\"x\"")]
    [InlineData("null")]
    [InlineData("{}")]
    public void NonObjectOrEmptyPlansAreSchemaInvalid(string json)
    {
        var result = Validator.Validate(JsonDocument.Parse(json).RootElement, "anything", "en");
        Assert.Equal(PlanReason.SchemaInvalid, result.Reason);
    }

    [Fact]
    public void AnOversizedPlanIsRejectedBeforeParsing()
    {
        var json = "{\"v\":1,\"pad\":\"" + new string('x', PlanValidator.MaxPlanJsonLength) + "\"}";
        Assert.Equal(PlanReason.SchemaInvalid, Validator.Validate(JsonDocument.Parse(json).RootElement, "q", "en").Reason);
    }

    [Fact]
    public void Ac4_NothingFromThePlanOrTheQuestionReachesTheLogOrTheResult()
    {
        const string Sentinel = "SENTINELzawyaqq";
        var sink = new ListLogger();
        var validator = new PlanValidator(logger: sink);
        var plan = new JsonObject
        {
            ["v"] = 1,
            ["plan"] = "PL-SPEND",
            ["p"] = new JsonObject
            {
                ["period"] = new JsonObject { ["k"] = "month", ["o"] = 0, ["n"] = null, ["m"] = null, ["y"] = null },
                ["filter"] = new JsonObject { ["slug"] = null, ["ref"] = null, ["mention"] = Sentinel, ["currency"] = null },
            },
            ["t"] = null,
        };
        var fallback = validator.Validate(JsonDocument.Parse(plan.ToJsonString()).RootElement, "question without it", "en");
        Assert.Equal(PlanReason.MentionNotInText, fallback.Reason);

        // A template carrying the sentinel is dropped and logged by code only.
        var vector = Vectors["plans"]!.AsArray().Select(v => v!.AsObject()).Single(v => v["id"]!.GetValue<string>() == "valid-template-en-spend");
        var withT = JsonNode.Parse(vector["plan"]!.ToJsonString())!.AsObject();
        withT["t"] = new JsonObject { ["lang"] = "en", ["text"] = "spent {amount} " + Sentinel + " www.x" };
        var dropped = validator.Validate(JsonDocument.Parse(withT.ToJsonString()).RootElement, vector["sent"]!.GetValue<string>(), "en");
        Assert.Equal(PlanReason.TemplateLink, dropped.TemplateRejection);

        Assert.NotEmpty(sink.Lines);
        Assert.DoesNotContain(sink.Lines, l => l.Contains(Sentinel, StringComparison.Ordinal) || l.Contains("question", StringComparison.Ordinal));
        Assert.DoesNotContain(Sentinel, fallback.Reason.ToString()!, StringComparison.Ordinal);
    }

    private sealed class ListLogger : ILogger<PlanValidator>
    {
        public List<string> Lines { get; } = [];

        public IDisposable? BeginScope<TState>(TState state)
            where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
            Lines.Add(formatter(state, exception) + (exception?.ToString() ?? string.Empty));
    }
}
