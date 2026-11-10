using System.Globalization;
using System.Text;
using Zaghlol.Application.Contributions;

namespace Zaghlol.Application.Tests.Contributions;

public class ContributionPrivacyTests
{
    /// <summary>Filtered by the API. <c>PrivacyFilterCheckTests</c> (Infrastructure) proves every text the filter accepts passes the CHECK.</summary>
    public static TheoryData<string> Rejected =>
    [
        "transfer 123456",
        "pay 01001234567",
        "تحويل ٠١٠١٢٣٤٥٦٧",
        "pay ۰۱۲۳۴۵۶",
        "pay ０１２３４５６",
        "pay 01٢٣45۶",
        "pay 010 1234 5678",
        "card 41-11-11-11",
        "acct 12.34.56",
        "acct 12  34  56",
        "acct 12 / 34 / 56",
        "acct 12_34_56",
        "acct 12،34،56",
        "acct 12, 34, 56",
        "acct 1 2 3 4 5 6",
        "ahmed@instapay",
        "someone@example.com",
        "٠١ - ٢٣ - ٤٥",
        "shop 12\t34\t56",

        // T-128 security review S1: any decimal digit, any non-letter separator, marks skipped, every commercial at.
        "010\u20131234\u20135678",
        "010\u22121234\u22125678",
        "\u0660\u0661\u0660\u0640\u0661\u0662\u0663\u0664\u0640\u0665\u0666\u0667\u0668",
        "010\u20221234\u20225678",
        "010|1234|5678",
        "010:1234:5678",
        "(010) 1234\u00B75678",
        "pay \u0966\u0967\u0966\u0967\u0968\u0969",
        "pay \U0001D7CE\U0001D7CF\U0001D7D0\U0001D7D1\U0001D7D2\U0001D7D3",
        "pay \u2070\u00B9\u00B2\u00B3\u2074\u2075",
        "pay \u2460\u2461\u2462\u2463\u2464\u2465",
        "0\u03011\u03010\u03011\u03012\u03013\u0301",
        "0\u200B1\u200B0\u200B1\u200B2\u200B3",
        "name\uFE6Binstapay",
        "name\uFF20instapay",
    ];

    public static TheoryData<string> Accepted =>
    [
        "carrefour maadi",
        "branch 12345",
        "فرع ١٢٣٤٥",
        "كارفور المعادي",
        "shop 12 34 5",
        "7 eleven 2024",
        "acct 12    34 56",
        "acct 12 ---- 34 56",
        "12 abc 34 def 56",
        new string('b', 64),
        "carrefour \u2013 maadi",
        "\u0643\u0634\u0631\u064A \u0661\u0662\u0663",
        "shop 12 \u2022 34 abc 56",
        "pay \u2469 1234", // circled ten is not one digit
    ];

    [Theory]
    [MemberData(nameof(Rejected))]
    public void RejectsPersonalNumbersAndAddresses(string text) => Assert.False(ContributionPrivacy.IsAcceptable(text));

    [Theory]
    [MemberData(nameof(Accepted))]
    public void AcceptsOrdinaryMerchantNames(string text) => Assert.True(ContributionPrivacy.IsAcceptable(text));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public void RejectsEmpty(string? text) => Assert.False(ContributionPrivacy.IsAcceptable(text));

    [Fact]
    public void RejectsOver64Characters() => Assert.False(ContributionPrivacy.IsAcceptable(new string('a', 65)));

    [Fact]
    public void FoldsEveryDigitScriptToAscii()
    {
        Assert.Equal("0123456789", ContributionPrivacy.Fold("٠١٢٣٤٥٦٧٨٩"));
        Assert.Equal("0123456789", ContributionPrivacy.Fold("۰۱۲۳۴۵۶۷۸۹"));
        Assert.Equal("0123456789", ContributionPrivacy.Fold("０１２３４５６７８９"));
        Assert.Equal("a1b", ContributionPrivacy.Fold("a١b"));
        Assert.Equal("0123456789", ContributionPrivacy.Fold("\u0966\u0967\u0968\u0969\u096A\u096B\u096C\u096D\u096E\u096F"));
        Assert.Equal("019", ContributionPrivacy.Fold("\U0001D7CE\U0001D7CF\U0001D7D7"));
        Assert.Equal("0123", ContributionPrivacy.Fold("\u2070\u00B9\u2082\u2462"));
        Assert.Equal("x\u2469\u00BD", ContributionPrivacy.Fold("x\u2469\u00BD")); // ten and one half are not single digits
    }

    [Fact]
    public void EveryDecimalDigitInUnicodeIsADigit()
    {
        for (var value = 0; value <= 0x10FFFF; value++)
        {
            if (Rune.IsValid(value) && Rune.GetUnicodeCategory(new Rune(value)) == UnicodeCategory.DecimalDigitNumber)
            {
                Assert.Equal((int?)CharUnicodeInfo.GetDecimalDigitValue(new Rune(value).ToString(), 0), ContributionPrivacy.DigitValue(new Rune(value)));
            }
        }
    }
}
