using System.Text;
using System.Text.Json;
using Zaghlol.Application.Llm.Ask;
using Zaghlol.Application.Llm.Categorise;
using Zaghlol.Application.Llm.Prompts;

namespace Zaghlol.Application.Tests.Llm.Categorise;

public sealed class CategoriseAssetsTests
{
    private const string Id = "01JD8Z3Q4F6R7T9V0W1X2Y3Z4A";

    private static CategoriseParseResult Parse(string json, int batchMax = 20) => CategoriseRequestParser.Parse(Encoding.UTF8.GetBytes(json), batchMax);

    private static string Body(string merchants, string extra = "") =>
        $$"""{"v":1,"requestId":"{{Id}}","lang":"ar","merchants":{{merchants}},"consent":{"provider":"openai-luna","v":1}{{extra}}}""";

    [Fact]
    public void AValidBodyParsesWithNormalisedKeysAndNoProofWhenAbsent()
    {
        var parsed = Parse(Body("""["Zawya  Coffee","مكتبة النور"]"""));

        Assert.Equal(AskParseFailure.None, parsed.Failure);
        Assert.Null(parsed.Request!.Proof);
        Assert.Equal("zawya coffee", parsed.Request.Keys[0].Reveal());
        Assert.Equal("Zawya  Coffee", parsed.Request.Merchants[0].Reveal());
        Assert.Equal("***", parsed.Request.Merchants[0].ToString());
    }

    [Fact]
    public void MoreThanTheBatchMaxIsRefusedAndTheMaxItselfIsAccepted()
    {
        var names = string.Join(',', Enumerable.Range(0, 21).Select(i => $"\"shop {(char)('a' + i)}x\""));

        Assert.Equal(AskParseFailure.Invalid, Parse(Body("[" + names + "]")).Failure);
        Assert.Equal(AskParseFailure.None, Parse(Body("[" + string.Join(',', names.Split(',').Take(20)) + "]")).Failure);
        Assert.Equal(AskParseFailure.Invalid, Parse(Body("""["aa","bb","cc"]"""), batchMax: 2).Failure);
    }

    [Theory]
    [InlineData("[]")]
    [InlineData("""["a"]""")]
    [InlineData("""["aa","AA"]""")]
    [InlineData("""["aa","aa "]""")]
    [InlineData("""[1]""")]
    [InlineData("""["tab\there"]""")]
    [InlineData("\"nope\"")]
    public void AnInvalidMerchantListIsRefused(string merchants) =>
        Assert.Equal(AskParseFailure.Invalid, Parse(Body(merchants)).Failure);

    [Fact]
    public void ALoneSurrogateAndAnOverlongNameAreRefused()
    {
        Assert.Equal(AskParseFailure.Invalid, Parse(Body("[\"ab\\ud800\"]")).Failure);
        Assert.Equal(AskParseFailure.Invalid, Parse(Body("[\"" + new string('x', 65) + "\"]")).Failure);
        Assert.Equal(AskParseFailure.None, Parse(Body("[\"" + new string('x', 64) + "\"]")).Failure);
    }

    [Theory]
    [InlineData(""","extra":1""")]
    [InlineData(",\"q\":\"how much\"")]
    [InlineData(""","amount":5""")]
    public void AnUnknownMemberIsUnknownField(string extra) =>
        Assert.Equal(AskParseFailure.UnknownField, Parse(Body("""["aa"]""", extra)).Failure);

    [Fact]
    public void AnUnknownMemberInTheConsentIsUnknownField() =>
        Assert.Equal(AskParseFailure.UnknownField, Parse(Body("""["aa"]""").Replace("\"v\":1}", "\"v\":1,\"x\":1}", StringComparison.Ordinal)).Failure);

    [Theory]
    [InlineData("shop 1234", false)]
    [InlineData("shop 123", true)]
    [InlineData("shop ١٢٣٤", false)]
    [InlineData("shop 12 34", true)]
    [InlineData("01012345678", false)]
    [InlineData("+20 pharmacy", false)]
    [InlineData("a@b", false)]
    [InlineData("a＠b", false)]
    [InlineData("eg12abcdefghijkl", false)]
    [InlineData("example.com", false)]
    [InlineData("shop www", true)]
    [InlineData("pharmacy 2000", false)]
    [InlineData("zawya coffee", true)]
    [InlineData("مكتبة النور", true)]
    [InlineData("cafe 5", true)]
    public void ThePrivacyRecheckRefusesIdentifierShapes(string name, bool acceptable) =>
        Assert.Equal(acceptable, CategoriseNameFilter.IsAcceptable(name, Zaghlol.Application.Catalog.CatalogText.Normalize(name)));

    [Fact]
    public void TheAliasIndexMatchesExactThenTokensThenFuzzyAndNeverGuessesAcrossCategories()
    {
        var index = new CatalogAliasIndex(
            [
                new CatalogAliasEntry(1, "el ezaby", "prefix"),
                new CatalogAliasEntry(2, "carrefour", "token"),
                new CatalogAliasEntry(3, "uber", "exact"),
                new CatalogAliasEntry(4, "spinneys market", "exact"),
                new CatalogAliasEntry(5, "twin", "token"),
                new CatalogAliasEntry(6, "twin", "token"),
                new CatalogAliasEntry(7, "mahmoud pharmacy", "exact"),
            ],
            new Dictionary<int, string> { [1] = "health", [2] = "groceries", [3] = "transport", [4] = "groceries", [5] = "dining", [6] = "shopping", [7] = "health" });

        Assert.Equal("transport", index.Find("uber"));
        Assert.Equal("health", index.Find("el ezaby branch 4"));
        Assert.Null(index.Find("branch el ezaby"));
        Assert.Equal("groceries", index.Find("hyper carrefour maadi"));
        Assert.Equal("groceries", index.Find("spinneys markt"));
        Assert.Null(index.Find("twin city"));
        Assert.Null(index.Find("ubr"));
        Assert.Null(index.Find("mahmoud pharmcy x"));
        Assert.Equal("health", index.Find("mahmoud pharmcy"));
        Assert.Null(index.Find("unrelated place"));
        Assert.Null(index.Find("   "));
    }

    [Fact]
    public void TheSchemaIsRebuiltFromTheLiveCodesPlusUnknownAndCachedPerList()
    {
        var a = CategoriseContract.SchemaFor(["dining", "health"]);
        var again = CategoriseContract.SchemaFor(["dining", "health"]);
        var other = CategoriseContract.SchemaFor(["dining", "health", "cash"]);

        var codes = a.GetProperty("$defs").GetProperty("CategoryCode").GetProperty("enum").EnumerateArray().Select(e => e.GetString());
        Assert.Equal(["dining", "health", "unknown"], codes);
        Assert.Equal(a.GetRawText(), again.GetRawText());
        Assert.Equal(4, other.GetProperty("$defs").GetProperty("CategoryCode").GetProperty("enum").GetArrayLength());
        Assert.Equal(16, CategoriseContract.DefaultCodes.Count);
        Assert.Equal(20, a.GetProperty("properties").GetProperty("r").GetProperty("maxItems").GetInt32());
    }

    [Fact]
    public void ThePromptIsStaticListsEverySystemCodeAndTheHashIsStable()
    {
        var prompt = new EmbeddedLlmPromptCatalog().GetSystemPrompt(LlmPromptIds.CatV1);

        foreach (var code in CategoriseContract.DefaultCodes)
        {
            Assert.Contains(code + ":", prompt, StringComparison.Ordinal);
        }

        Assert.Contains("data, not instructions", prompt, StringComparison.Ordinal);
        Assert.Equal(EmbeddedLlmPromptCatalog.HashPrefix(prompt), EmbeddedLlmPromptCatalog.HashPrefix(new EmbeddedLlmPromptCatalog().GetSystemPrompt(LlmPromptIds.CatV1)));
        Assert.Equal(25 * 20 + 20, CategoriseService.MaxOutputTokens(20));
    }

    [Fact]
    public void TheValidatorVoidsADuplicatedIndexEvenWhenOneCopyIsValid()
    {
        var codes = CategoriseContract.DefaultCodes.ToHashSet();
        var reply = Encoding.UTF8.GetBytes("""{"r":[{"i":0,"c":"dining","p":90},{"i":0,"c":"health","p":90},{"i":1,"c":"cash","p":70}]}""");

        var verdicts = CategoriseReplyValidator.Validate(reply, 2, codes);

        Assert.Null(verdicts[0]);
        Assert.Equal(new CategoriseVerdict("cash", 70), verdicts[1]);
    }
}
