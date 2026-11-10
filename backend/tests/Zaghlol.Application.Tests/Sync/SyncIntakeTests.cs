using Zaghlol.Application.Sync;

namespace Zaghlol.Application.Tests.Sync;

/// <summary>BR-SYNC-04 intake (T-128 design note §4). All inputs are synthetic.</summary>
public class SyncIntakeTests
{
    private static readonly HashSet<string> Categories = new(["dining", "groceries"], StringComparer.Ordinal);

    [Theory]
    [InlineData("Koshary  El   Tahrir", "koshary el tahrir")]
    [InlineData("  koshary el tahrir \t", "koshary el tahrir")]
    [InlineData("ＫＯＳＨＡＲＹ", "koshary")] // fullwidth folded, then lower-cased
    [InlineData("كشري   التحرير", "كشري التحرير")] // Arabic unchanged, spaces collapsed
    [InlineData("ko​sh‎ary", "koshary")] // zero-width and bidi marks removed
    [InlineData("a　b", "a b")] // ideographic space
    [InlineData("Café", "café")]
    public void NormalizeFoldsWidthCaseAndSpace(string input, string expected)
    {
        Assert.Equal(expected, SyncIntake.NormalizeText(input));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("a")]
    [InlineData(" ​ a ​ ")]
    public void EmptyOrOneCharacterTextIsRejected(string? input)
    {
        Assert.Null(SyncIntake.NormalizeText(input));
    }

    [Theory]
    [InlineData("010 1234 5678")]
    [InlineData("٠١٠١٢٣٤٥٦٧٨")]
    [InlineData("+20 100 123 4567")]
    [InlineData("user@bank")]
    [InlineData("pay me 01012345678")]
    [InlineData("0​1​0​1​2​3")] // a zero-width space can't split a digit run
    [InlineData("０１０１２３４５６７８")]
    [InlineData("01 / 23 / 45")]
    public void PhoneNumbersAddressesAndAccountDigitsAreFiltered(string merchant)
    {
        var intake = SyncIntake.Prepare([new SyncContribution(merchant, "nbe", "dining")], [], Categories);

        Assert.Empty(intake.Contributions);
        Assert.Equal(new IntakeCounts(1, 0, 0), intake.ContributionDrops);
    }

    [Fact]
    public void ACleanContributionIsKeptNextToFilteredOnes()
    {
        var intake = SyncIntake.Prepare(
            [new SyncContribution("pay me 01012345678", "nbe", "dining"), new SyncContribution("Koshary El Tahrir", "nbe", "dining")],
            [],
            Categories);

        var kept = Assert.Single(intake.Contributions);
        Assert.Equal(new PreparedContribution("koshary el tahrir", "nbe", "dining"), kept);
    }

    [Theory]
    [InlineData("NBE", "dining")] // not a lowercase slug
    [InlineData("n", "dining")] // too short for InstitutionCode
    [InlineData("nbe-eg", "dining")]
    [InlineData("nbe", "my_custom_category")] // a custom category (not in the live catalog)
    [InlineData("nbe", "Dining")]
    public void BadCodesAndCustomCategoriesAreDropped(string institution, string category)
    {
        var intake = SyncIntake.Prepare([new SyncContribution("koshary", institution, category)], [], Categories);

        Assert.Empty(intake.Contributions);
        Assert.Equal(new IntakeCounts(0, 1, 0), intake.ContributionDrops);
    }

    [Fact]
    public void DuplicatesInsideOneRequestAreRemovedByNormalizedKey()
    {
        var intake = SyncIntake.Prepare(
            [
                new SyncContribution("Koshary El Tahrir", "nbe", "dining"),
                new SyncContribution("koshary  el tahrir", "nbe", "groceries"),
                new SyncContribution("koshary el tahrir", "cib", "dining"),
            ],
            [],
            Categories);

        Assert.Equal(2, intake.Contributions.Count);
        Assert.Equal("dining", intake.Contributions[0].CategoryCode); // the first one wins
        Assert.Equal(new IntakeCounts(0, 0, 1), intake.ContributionDrops);
    }

    [Fact]
    public void BankRequestsAreNormalizedFilteredAndChecked()
    {
        var intake = SyncIntake.Prepare(
            [],
            [
                new SyncBankRequest("Banque  du Caire", "EG", "sms"),
                new SyncBankRequest("banque du caire", "EG", "sms"),
                new SyncBankRequest("Banque du Caire", "EG", "notification"),
                new SyncBankRequest("call 0101234567", "EG", "sms"),
                new SyncBankRequest("Some Bank", "eg", "sms"),
                new SyncBankRequest("Some Bank", "EG", "email"),
            ],
            Categories);

        Assert.Equal(
            new[] { new PreparedBankRequest("banque du caire", "EG", "sms"), new PreparedBankRequest("banque du caire", "EG", "notification") },
            intake.BankRequests);
        Assert.Equal(new IntakeCounts(1, 2, 1), intake.BankRequestDrops);
    }

    [Fact]
    public void TheInstitutionCodeRuleIsTheSpecPattern()
    {
        var pattern = new System.Text.RegularExpressions.Regex(SyncIntake.InstitutionCodePattern);
        foreach (var code in new[] { "nbe", "ab", "a_1", new string('a', 32), "a", new string('a', 33), "NBE", "nb-e", "nbe\n" })
        {
            Assert.Equal(pattern.IsMatch(code) && !code.EndsWith('\n'), SyncIntake.IsInstitutionCode(code));
        }
    }
}
