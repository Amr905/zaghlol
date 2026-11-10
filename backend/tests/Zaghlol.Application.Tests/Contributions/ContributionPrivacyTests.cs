using Zaghlol.Application.Contributions;

namespace Zaghlol.Application.Tests.Contributions;

public class ContributionPrivacyTests
{
    /// <summary>Shared with the database test, which proves the CHECK rejects the same set (so it is only ever a backstop).</summary>
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
    }
}
