using Zaghlol.Application.Llm.Categorise.Feedback;

namespace Zaghlol.Application.Tests.Llm.Categorise;

/// <summary>T-353: the per-item rules of feedback intake (FR-LCAT-22/23, FU-410): privacy re-check, closed category set, verdict agreement, dedupe, cap.</summary>
public class CategoriseFeedbackIntakeTests
{
    private static readonly IReadOnlySet<string> Codes = new HashSet<string>(["dining", "education", "groceries"], StringComparer.Ordinal);

    private static SyncLlmCatFeedback Item(string merchant = "zawya coffee", string verdict = "right", string ai = "dining", string user = "dining", string source = "llm") =>
        new(merchant, verdict, ai, user, source);

    private static PreparedFeedback Prepare(params SyncLlmCatFeedback[] items) => CategoriseFeedbackIntake.Prepare(items, Codes);

    // AC 1
    [Fact]
    public void RightBecomesAConfirmationAndWrongAnOpenCorrectionWithTheCodesOnly()
    {
        var result = Prepare(Item(), Item("مكتبة النور", "wrong", "groceries", "education", "cache"));

        Assert.Equal(new PreparedConfirmation("zawya coffee", "dining", "llm"), Assert.Single(result.Confirmations));
        Assert.Equal(new PreparedCorrection("مكتبة النور", "groceries", "education", "cache"), Assert.Single(result.Corrections));
    }

    // AC 1
    [Fact]
    public void ACustomCategoryIsStoredAsTheLiteralCustom()
    {
        var result = Prepare(Item(verdict: "wrong", ai: "dining", user: "custom"));

        Assert.Equal("custom", Assert.Single(result.Corrections).UserCategory);
    }

    // FU-410
    [Theory]
    [InlineData("right", "custom", "custom")]
    [InlineData("right", "nosuchcode", "nosuchcode")]
    [InlineData("wrong", "dining", "nosuchcode")]
    [InlineData("wrong", "dining", "dining")]
    [InlineData("right", "dining", "education")]
    [InlineData("wrong", "dining", "Custom")]
    public void CodesOutsideTheClosedSetOrAtOddsWithTheVerdictAreDroppedOnTheirOwn(string verdict, string ai, string user)
    {
        var result = Prepare(Item(verdict: verdict, ai: ai, user: user), Item("second shop"));

        Assert.Equal("second shop", Assert.Single(result.Confirmations).MerchantNorm);
        Assert.Empty(result.Corrections);
        var drops = verdict == "right" ? result.ConfirmationDrops : result.CorrectionDrops;
        Assert.Equal(1, drops.InvalidCode);
    }

    // AC 2 and the reuse of the categorise filter
    [Theory]
    [InlineData("shop 01012345678")]
    [InlineData("ahmed@instapay")]
    [InlineData("shop 1234")]
    [InlineData("www.example.com")]
    [InlineData("x")]
    public void MerchantsThatCarryIdentifiersAreFilteredAndCounted(string merchant)
    {
        var result = Prepare(Item(merchant), Item(merchant, "wrong", "dining", "education"));

        Assert.True(result.IsEmpty);
        Assert.Equal(1, result.ConfirmationDrops.Filtered);
        Assert.Equal(1, result.CorrectionDrops.Filtered);
    }

    [Fact]
    public void TheSameMerchantTwiceInOneCallKeepsTheFirstPerVerdictAfterNormalising()
    {
        var result = Prepare(Item("Zawya  Coffee", ai: "dining", user: "dining"), Item("zawya coffee", ai: "groceries", user: "groceries"), Item("zawya coffee", "wrong", "dining", "education"));

        Assert.Equal("dining", Assert.Single(result.Confirmations).CategoryCode);
        Assert.Single(result.Corrections);
        Assert.Equal(1, result.ConfirmationDrops.Duplicate);
    }

    [Fact]
    public void OnlyTheFirstFiftyItemsAreLookedAt()
    {
        var items = Enumerable.Range(0, 60).Select(i => Item("shop " + (char)('a' + (i % 26)) + (char)('a' + (i / 26)) + "x")).ToArray();

        var result = Prepare(items);

        Assert.Equal(50, result.Confirmations.Count);
    }
}
