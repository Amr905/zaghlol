using Zaghlol.Application.Audit;
using Zaghlol.Application.Llm.Categorise.Review;

namespace Zaghlol.Application.Tests.Llm.Categorise;

/// <summary>T-354: the wire words, the key and page rules of the review bodies, and the audit rows they leave.</summary>
public class LlmCatReviewWireTests
{
    [Theory]
    [InlineData("promote", CorrectionAction.Promote, "promoted")]
    [InlineData("reject", CorrectionAction.Reject, "rejected")]
    [InlineData("prompt_issue", CorrectionAction.PromptIssue, "prompt_issue")]
    public void ACorrectionActionParsesExactlyAndNamesItsStoredStatus(string text, CorrectionAction expected, string status)
    {
        Assert.True(LlmCatReviewWire.TryParse(text, out CorrectionAction action));
        Assert.Equal(expected, action);
        Assert.Equal(status, LlmCatReviewWire.Wire(action));
    }

    [Theory]
    [InlineData("Promote")]
    [InlineData("promoted")]
    [InlineData("prompt-issue")]
    [InlineData("")]
    [InlineData(null)]
    public void AnythingElseIsNotACorrectionAction(string? text) => Assert.False(LlmCatReviewWire.TryParse(text, out CorrectionAction _));

    [Theory]
    [InlineData("promote", true)]
    [InlineData("reject", true)]
    [InlineData("prompt_issue", false)]
    [InlineData("PROMOTE", false)]
    public void AConfirmedActionIsPromoteOrRejectOnly(string text, bool valid) => Assert.Equal(valid, LlmCatReviewWire.TryParse(text, out ConfirmedAction _));

    [Theory]
    [InlineData("zz", true)]
    [InlineData("مكتبة النور", true)]
    [InlineData("z", false)]
    [InlineData("", false)]
    [InlineData("line\nbreak", false)]
    public void AMerchantKeyIsTwoToSixtyFourCharactersWithoutControls(string text, bool valid) => Assert.Equal(valid, LlmCatReviewWire.IsValidMerchant(text));

    [Fact]
    public void AMerchantKeyOverSixtyFourCharactersIsRefused()
    {
        Assert.True(LlmCatReviewWire.IsValidMerchant(new string('a', 64)));
        Assert.False(LlmCatReviewWire.IsValidMerchant(new string('a', 65)));
    }

    [Theory]
    [InlineData(null, true, 0)]
    [InlineData("0", true, 0)]
    [InlineData("150", true, 150)]
    [InlineData("-1", false, 0)]
    [InlineData("1.5", false, 0)]
    [InlineData("1234567890", false, 0)]
    [InlineData("", false, 0)]
    public void TheCursorIsABoundedDecimalOffset(string? cursor, bool valid, int offset)
    {
        Assert.Equal(valid, LlmCatReviewWire.TryParseCursor(cursor, out var parsed));
        Assert.Equal(offset, parsed);
    }

    [Theory]
    [InlineData(null, true)]
    [InlineData(1, true)]
    [InlineData(100, true)]
    [InlineData(0, false)]
    [InlineData(101, false)]
    public void ThePageSizeIsOneToOneHundred(int? limit, bool valid) => Assert.Equal(valid, LlmCatReviewWire.IsPage(limit));

    [Fact]
    public void TheAuditRowsNameTheActionKeepTheTextEncodedAndHoldNoIdentifier()
    {
        var promote = new LlmCatReviewAudit(LlmCatReviewKind.CorrectionPromote, "emF3eWE", "dining", "education", 3, 812);
        var issue = new LlmCatReviewAudit(LlmCatReviewKind.CorrectionPromptIssue, "emF3eWE", "dining", "custom", 1, null);
        var confirmed = new LlmCatReviewAudit(LlmCatReviewKind.ConfirmedReject, "emF3eWE", null, "dining", 4, null);

        Assert.Equal("llmcat_correction_promote", promote.Action);
        Assert.Equal("llmcat/corrections:emF3eWE", promote.Target);
        Assert.Equal("{\"ai_category\":\"dining\",\"category\":\"education\",\"rows\":3,\"merchant_id\":812}", promote.Details());
        Assert.Equal("llmcat_correction_prompt_issue", issue.Action);
        Assert.Equal("{\"ai_category\":\"dining\",\"category\":\"custom\",\"rows\":1}", issue.Details());
        Assert.Equal("llmcat_confirmed_reject", confirmed.Action);
        Assert.Equal("llmcat/confirmed:emF3eWE", confirmed.Target);
        Assert.Equal("{\"category\":\"dining\",\"rows\":4}", confirmed.Details());
        Assert.All(new[] { promote.Details(), issue.Details(), confirmed.Details(), promote.Target }, text => Assert.DoesNotContain('@', text));
    }

    [Fact]
    public void EveryReviewKindHasItsOwnAction()
    {
        var actions = Enum.GetValues<LlmCatReviewKind>().Select(k => new LlmCatReviewAudit(k, "a", null, "dining", 1, null).Action).ToList();

        Assert.Equal(actions.Count, actions.Distinct(StringComparer.Ordinal).Count());
        Assert.All(actions, a => Assert.StartsWith("llmcat_", a, StringComparison.Ordinal));
    }
}
