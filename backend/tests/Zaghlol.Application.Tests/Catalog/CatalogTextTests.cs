using Zaghlol.Application.Catalog;

namespace Zaghlol.Application.Tests.Catalog;

public class CatalogTextTests
{
    [Theory]
    [InlineData("Koshary  El\tTahrir ", "koshary el tahrir")]
    [InlineData("\u0661\u0662\u0663", "123")]
    [InlineData("\u06F4\u06F5", "45")]
    [InlineData("\u0623\u0643\u0644", "\u0627\u0643\u0644")]
    [InlineData("\u0635\u064E\u064A\u0652\u062F\u0644\u064A\u0640\u0629", "\u0635\u064A\u062F\u0644\u064A\u0629")]
    [InlineData("\u0645\u0635\u0631\u0649", "\u0645\u0635\u0631\u064A")]
    [InlineData("a\u200Bb", "ab")]
    [InlineData("   ", "")]
    public void NormalizeAppliesTheStructuralRules(string input, string expected)
    {
        Assert.Equal(expected, CatalogText.Normalize(input));
    }

    [Theory]
    [InlineData("koshary el tahrir", true)]
    [InlineData("Koshary", false)]
    [InlineData(" koshary", false)]
    [InlineData("koshary  el", false)]
    [InlineData("", false)]
    [InlineData("\u0661", false)]
    public void IsNormalizedMeansEqualToItsOwnNormalizedForm(string text, bool expected)
    {
        Assert.Equal(expected, CatalogText.IsNormalized(text));
    }

    [Fact]
    public void NormalizationIsIdempotent()
    {
        var once = CatalogText.Normalize("  \u0623\u0643\u0644\u064E  \u0661\u0662 Pharmacy ");

        Assert.Equal(once, CatalogText.Normalize(once));
        Assert.True(CatalogText.IsNormalized(once));
    }

    [Fact]
    public void IsAsciiTextRejectsArabicAndControlCharacters()
    {
        Assert.True(CatalogText.IsAsciiText("el ezaby 2"));
        Assert.False(CatalogText.IsAsciiText("\u0635"));
        Assert.False(CatalogText.IsAsciiText("a\nb"));
    }
}
