using Zaghlol.Application.Llm.Ask;

namespace Zaghlol.Application.Tests.Llm.Ask;

/// <summary>T-349 / FR-LLM-03: the server-side scrub, defence in depth behind the phone (same tokens as <c>client_scrub.dart</c>).</summary>
public class QuestionScrubberTests
{
    [Theory]
    [InlineData("call 01001234567 please", "call ⟦PHONE⟧ please")]
    [InlineData("اتصل ٠١٠٠١٢٣٤٥٦٧ دلوقتي", "اتصل ⟦PHONE⟧ دلوقتي")]
    [InlineData("my number is +20 100 123 4567 ok", "my number is ⟦PHONE⟧ ok")]
    [InlineData("0100.123.4567", "⟦PHONE⟧")]
    [InlineData("mail me at ahmed.s@example.com now", "mail me at ⟦EMAIL⟧ now")]
    [InlineData("send to ahmed@instapay today", "send to ⟦IPA⟧ today")]
    [InlineData("send to ahmed @ instapay today", "send to ⟦IPA⟧ today")]
    [InlineData("card 4111 1111 1111 1111 spent", "card ⟦NUMBER⟧ spent")]
    [InlineData("account 123456789012 balance", "account ⟦NUMBER⟧ balance")]
    [InlineData("حساب ١٢٣٤٥٦٧٨٩٠١٢", "حساب ⟦NUMBER⟧")]
    public void SensitiveLiteralsBecomeNeutralTokens(string text, string expected) => Assert.Equal(expected, QuestionScrubber.Scrub(text));

    [Theory]
    [InlineData("how much did I spend on ⟦CARD_1⟧ and ⟦MERCHANT_2⟧")]
    [InlineData("لو قللت الأكل 50% لمدة 12 شهر وحوشت 2500.50 جنيه")]
    [InlineData("card ending 1234 spent 1,234,567 last year")]
    [InlineData("⟦PHONE⟧ ⟦EMAIL⟧ ⟦IPA⟧ ⟦NUMBER⟧")]
    [InlineData("a plain question with no secrets")]
    public void AmountsPercentagesPeriodsShortNumbersAndThePhonesOwnTokensStay(string text) => Assert.Equal(text, QuestionScrubber.Scrub(text));

    [Fact]
    public void ScrubbingTwiceChangesNothingMore()
    {
        var once = QuestionScrubber.Scrub("01001234567 and a@b.com and 4111111111111111");
        Assert.Equal(once, QuestionScrubber.Scrub(once));
        Assert.DoesNotContain("0100", once, StringComparison.Ordinal);
    }
}
