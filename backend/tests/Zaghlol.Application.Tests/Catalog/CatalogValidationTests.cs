using Zaghlol.Application.Catalog;

namespace Zaghlol.Application.Tests.Catalog;

public class CatalogValidationTests
{
    private static readonly CatalogFields Category = new()
    {
        NameAr = "\u0623\u0643\u0644",
        NameEn = "Dining",
        Icon = "restaurant",
        Color = "#0F7A55",
        Bucket = "wants",
        Sort = 1,
    };

    [Fact]
    public void ACompleteCategoryIsValid()
    {
        Assert.True(CatalogValidation.IsValid(CatalogEntity.Categories, Category));
    }

    [Theory]
    [InlineData("0F7A55")]
    [InlineData("#0F7A5")]
    [InlineData("#0F7A5G")]
    [InlineData("#0f7a55 ")]
    public void ACategoryColorMustBeHashAndSixHexDigits(string color)
    {
        Assert.False(CatalogValidation.IsValid(CatalogEntity.Categories, Category with { Color = color }));
    }

    [Fact]
    public void CategoryFieldsAreBounded()
    {
        Assert.False(CatalogValidation.IsValid(CatalogEntity.Categories, Category with { NameAr = string.Empty }));
        Assert.False(CatalogValidation.IsValid(CatalogEntity.Categories, Category with { NameEn = new string('x', 81) }));
        Assert.False(CatalogValidation.IsValid(CatalogEntity.Categories, Category with { Icon = new string('x', 65) }));
        Assert.False(CatalogValidation.IsValid(CatalogEntity.Categories, Category with { Bucket = new string('x', 33) }));
        Assert.False(CatalogValidation.IsValid(CatalogEntity.Categories, Category with { Sort = null }));
        Assert.False(CatalogValidation.IsValid(CatalogEntity.Categories, Category with { NameEn = "a\nb" }));
    }

    [Fact]
    public void MerchantFieldsAreBounded()
    {
        var merchant = new CatalogFields { Canonical = "Koshary", NameAr = "\u0643\u0634\u0631\u064A", Category = "dining" };

        Assert.True(CatalogValidation.IsValid(CatalogEntity.Merchants, merchant));
        Assert.False(CatalogValidation.IsValid(CatalogEntity.Merchants, merchant with { Canonical = string.Empty }));
        Assert.False(CatalogValidation.IsValid(CatalogEntity.Merchants, merchant with { NameAr = new string('x', 121) }));
        Assert.False(CatalogValidation.IsValid(CatalogEntity.Merchants, merchant with { Category = "Dining" }));
    }

    [Theory]
    [InlineData("exact", true)]
    [InlineData("prefix", true)]
    [InlineData("token", true)]
    [InlineData("fuzzy", false)]
    [InlineData("Exact", false)]
    public void AnAliasMatchIsOneOfThreeModes(string match, bool valid)
    {
        Assert.Equal(valid, CatalogValidation.IsValid(CatalogEntity.Aliases, new CatalogFields { Match = match }));
    }

    [Theory]
    [InlineData(0, true)]
    [InlineData(100, true)]
    [InlineData(-1, false)]
    [InlineData(101, false)]
    public void AKeywordWeightIsZeroToOneHundred(int weight, bool valid)
    {
        Assert.Equal(valid, CatalogValidation.IsValid(CatalogEntity.Keywords, new CatalogFields { Category = "dining", Weight = weight }));
    }

    [Fact]
    public void ThePublishNoteIsBounded()
    {
        Assert.True(CatalogValidation.IsValidNote(null));
        Assert.True(CatalogValidation.IsValidNote(new string('x', 200)));
        Assert.False(CatalogValidation.IsValidNote(new string('x', 201)));
        Assert.False(CatalogValidation.IsValidNote("a\u0000b"));
    }
}
