using System.Text;
using Zaghlol.Application.Llm.Ask;
using Zaghlol.Application.Llm.Attestation;

namespace Zaghlol.Application.Tests.Llm.Ask;

/// <summary>T-349: the closed body of <c>POST /v1/ask/plan</c> (ask-llm §4.1; the 4 KB and 16 KB caps are the endpoint's).</summary>
public class AskPlanRequestParserTests
{
    private const string Id = "01JD8Z3Q4F6R7T9V0W1X2Y3Z4A";

    private static string Body(string q = "\"how much on ⟦CARD_1⟧\"", string extra = "", string attestation = ", \"attestation\": {\"type\":\"dev\",\"proof\":\"abcdefghijklmnop\"}") =>
        $$"""{"planVersion":1,"requestId":"{{Id}}","q":{{q}},"lang":"en","consent":{"provider":"openai-luna","v":1}{{attestation}}{{extra}}}""";

    private static AskParseResult Parse(string body) => AskPlanRequestParser.Parse(Encoding.UTF8.GetBytes(body));

    [Fact]
    public void AValidBodyIsParsedWithTheQuestionHeldAsSensitive()
    {
        var parsed = Parse(Body());

        Assert.Equal(AskParseFailure.None, parsed.Failure);
        var request = parsed.Request!;
        Assert.Equal(Id, request.RequestId);
        Assert.Equal("how much on ⟦CARD_1⟧", request.Question.Reveal());
        Assert.Equal("***", request.Question.ToString());
        Assert.DoesNotContain("CARD", request.ToString(), StringComparison.Ordinal);
        Assert.IsType<LlmDevProof>(request.Proof);
        Assert.Equal("openai-luna", request.ConsentProvider);
        parsed.Document?.Dispose();
    }

    [Fact]
    public void AMissingAttestationIsAParsedRequestWithoutAProofNotAFailure()
    {
        var parsed = Parse(Body(attestation: string.Empty));

        Assert.Equal(AskParseFailure.None, parsed.Failure);
        Assert.Null(parsed.Request!.Proof);
        parsed.Document?.Dispose();
    }

    [Theory]
    [InlineData(", \"amount\": 5")]
    [InlineData(", \"messages\": [\"a\"]")]
    [InlineData(", \"installId\": \"x\"")]
    public void AnyMemberOutsideTheClosedBodyIsUnknownFieldAndNothingIsEchoed(string extra)
    {
        var parsed = Parse(Body(extra: extra));

        Assert.Equal(AskParseFailure.UnknownField, parsed.Failure);
        Assert.Null(parsed.Request);
    }

    [Fact]
    public void AnUnknownMemberInsideConsentOrTheProofIsUnknownField()
    {
        var consent = Body().Replace("\"v\":1}", "\"v\":1,\"x\":1}", StringComparison.Ordinal);
        Assert.Equal(AskParseFailure.UnknownField, Parse(consent).Failure);

        var proof = Body().Replace("\"proof\":\"abcdefghijklmnop\"", "\"proof\":\"abcdefghijklmnop\",\"x\":1", StringComparison.Ordinal);
        Assert.Equal(AskParseFailure.UnknownField, Parse(proof).Failure);
    }

    [Theory]
    [InlineData("not json")]
    [InlineData("[]")]
    [InlineData("""{"planVersion":2,"requestId":"01JD8Z3Q4F6R7T9V0W1X2Y3Z4A","q":"hi","lang":"en","consent":{"provider":"openai-luna","v":1}}""")]
    [InlineData("""{"planVersion":1,"requestId":"01JD8Z3Q4F6R7T9V0W1X2Y3Z4A","q":"hi","lang":"fr","consent":{"provider":"openai-luna","v":1}}""")]
    [InlineData("""{"planVersion":1,"requestId":"01JD8Z3Q4F6R7T9V0W1X2Y3Z4A","q":"hi","lang":"en","consent":{"provider":"X","v":1}}""")]
    [InlineData("""{"planVersion":1,"requestId":"01JD8Z3Q4F6R7T9V0W1X2Y3Z4A","q":"hi","lang":"en","consent":{"provider":"openai-luna","v":0}}""")]
    [InlineData("""{"planVersion":1,"requestId":"nope","q":"hi","lang":"en","consent":{"provider":"openai-luna","v":1}}""")]
    [InlineData("""{"planVersion":1,"requestId":"01JD8Z3Q4F6R7T9V0W1X2Y3Z4A\n","q":"hi","lang":"en","consent":{"provider":"openai-luna","v":1}}""")]
    [InlineData("""{"planVersion":1,"requestId":"01JD8Z3Q4F6R7T9V0W1X2Y3Z4A","q":"hi","q":"again","lang":"en","consent":{"provider":"openai-luna","v":1}}""")]
    [InlineData("""{"planVersion":1,"requestId":"01JD8Z3Q4F6R7T9V0W1X2Y3Z4A","q":"hi","lang":"en","consent":{"provider":"openai-luna\n","v":1}}""")]
    [InlineData("""{"planVersion":"1","requestId":"01JD8Z3Q4F6R7T9V0W1X2Y3Z4A","q":"hi","lang":"en","consent":{"provider":"openai-luna","v":1}}""")]
    public void AnythingElseThatIsMalformedIsValidationFailed(string body)
    {
        var parsed = Parse(body);

        Assert.Equal(AskParseFailure.Invalid, parsed.Failure);
        Assert.Null(parsed.Request);
    }

    [Fact]
    public void TheQuestionIsTrimmedAndBoundedTo300Characters()
    {
        var parsed = Parse(Body(q: "\"  hello  \""));
        Assert.Equal("hello", parsed.Request!.Question.Reveal());
        parsed.Document?.Dispose();

        Assert.Equal(AskParseFailure.Invalid, Parse(Body(q: "\"   \"")).Failure);
        Assert.Equal(AskParseFailure.Invalid, Parse(Body(q: "\"" + new string('a', 301) + "\"")).Failure);
        var ok = Parse(Body(q: "\"" + new string('a', 300) + "\""));
        Assert.Equal(AskParseFailure.None, ok.Failure);
        ok.Document?.Dispose();
        Assert.Equal(AskParseFailure.Invalid, Parse(Body(q: "\"a\\u0000b\"")).Failure);
        Assert.Equal(AskParseFailure.Invalid, Parse(Body(q: "\"lone \\ud800 surrogate\"")).Failure);
    }
}
