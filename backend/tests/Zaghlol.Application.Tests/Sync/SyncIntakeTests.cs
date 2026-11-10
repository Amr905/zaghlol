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

    /// <summary>T-128 security review S1: phone and account numbers in shapes the first filter missed, all synthetic.</summary>
    public static TheoryData<string, string> S1Bypasses => new()
    {
        { "en dash", "010\u20131234\u20135678" },
        { "minus sign", "010\u22121234\u22125678" },
        { "figure dash", "010\u20121234\u20125678" },
        { "tatweel", "\u0660\u0661\u0660\u0640\u0661\u0662\u0663\u0664\u0640\u0665\u0666\u0667\u0668" },
        { "bullet", "010\u20221234\u20225678" },
        { "pipe", "010|1234|5678" },
        { "colon", "010:1234:5678" },
        { "brackets and middle dot", "(010) 1234\u00B75678" },
        { "Devanagari digits", "pay \u0966\u0967\u0966\u0967\u0968\u0969\u096A\u096B" },
        { "Bengali digits", "pay \u09E6\u09E7\u09E8\u09E9\u09EA\u09EB" },
        { "mathematical digits", "pay \U0001D7CE\U0001D7CF\U0001D7D0\U0001D7D1\U0001D7D2\U0001D7D3" },
        { "mathematical double-struck digits", "\U0001D7D8\U0001D7D9 \U0001D7DA\U0001D7DB \U0001D7DC\U0001D7DD" },
        { "superscript digits", "pay \u2070\u00B9\u00B2\u00B3\u2074\u2075" },
        { "subscript digits", "pay \u2080\u2081\u2082\u2083\u2084\u2085" },
        { "circled digits", "pay \u2460\u2461\u2462\u2463\u2464\u2465" },
        { "combining acute after each digit", "0\u03011\u03010\u03011\u03012\u03013\u03014\u0301" },
        { "combining grapheme joiner", "0\u034F1\u034F0\u034F1\u034F2\u034F3" },
        { "variation selector", "0\uFE0F1\uFE0F0\uFE0F1\uFE0F2\uFE0F3" },
        { "enclosing keycap", "0\u20E31\u20E30\u20E31\u20E32\u20E33" },
        { "small commercial at", "name\uFE6Binstapay" },
        { "fullwidth commercial at", "name\uFF20instapay" },
    };

    [Theory]
    [MemberData(nameof(S1Bypasses))]
    public void S1BypassShapesAreFiltered(string shape, string merchant)
    {
        var intake = SyncIntake.Prepare(
            [new SyncContribution(merchant, "nbe", "dining")],
            [new SyncBankRequest(merchant, "EG", "sms")],
            Categories);

        Assert.True(intake.IsEmpty, shape);
        Assert.Equal(new IntakeCounts(1, 0, 0), intake.ContributionDrops);
        Assert.Equal(new IntakeCounts(1, 0, 0), intake.BankRequestDrops);
    }

    [Theory]
    [InlineData("name\uFE6Bx", "name@x")] // small commercial at
    [InlineData("name\uFF20x", "name@x")] // fullwidth commercial at
    [InlineData("shop \u0661\u0662", "shop 12")] // Arabic-Indic digits stored as ASCII
    [InlineData("shop \u0967\u0968", "shop 12")] // Devanagari
    [InlineData("shop \U0001D7CF\U0001D7D0", "shop 12")] // mathematical digits (surrogate pairs)
    [InlineData("shop \u00B9\u2082", "shop 12")] // superscript and subscript
    [InlineData("shop \u2460\u2461", "shop 12")] // circled
    [InlineData("1\u03012\u20E3", "12")] // combining and enclosing marks removed
    [InlineData("\u0643\u064E\u0634\u0652\u0631\u0650\u064A", "\u0643\u0634\u0631\u064A")] // Arabic harakat removed
    [InlineData("shop \u2469", "shop \u2469")] // circled ten is not one digit: kept
    public void NormalizeFoldsAtSignsDigitsAndMarks(string input, string expected)
    {
        Assert.Equal(expected, SyncIntake.NormalizeText(input));
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
