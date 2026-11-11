using Zaghlol.Application.Catalog;

namespace Zaghlol.Application.Tests.Catalog;

/// <summary>
/// T-030: the CSV written by <c>tools/catalog_build</c> (the same merchants the app bundles) must be accepted whole by the
/// backend's seed reader and field rules, so the app seed and the first backend snapshot are one catalog.
/// </summary>
public class BundledSeedCsvTests
{
    private static CatalogSeed Load() =>
        CatalogSeedCsv.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "catalog", "catalog_seed.csv")));

    [Fact]
    public void TheFileParsesIntoFourteenCategoriesAndTheMerchantList()
    {
        var seed = Load();

        Assert.Equal(14, seed.Categories.Count);
        Assert.InRange(seed.Merchants.Count, 120, 200);
        Assert.NotEmpty(seed.Keywords);
        Assert.All(seed.Merchants, m => Assert.NotEmpty(m.Aliases));
    }

    [Fact]
    public void EveryRowPassesTheBackendFieldRules()
    {
        var seed = Load();

        Assert.All(seed.Categories, c => Assert.True(CatalogValidation.IsValid(CatalogEntity.Categories, c.Fields), c.Code));
        Assert.All(seed.Merchants, m => Assert.True(CatalogValidation.IsValid(CatalogEntity.Merchants, m.Fields), m.Canonical));
        Assert.All(
            seed.Merchants.SelectMany(m => m.Aliases),
            a => Assert.True(CatalogValidation.IsValid(CatalogEntity.Aliases, new CatalogFields { Match = a.Match }), a.Alias));
        Assert.All(seed.Keywords, k => Assert.True(CatalogValidation.IsValid(CatalogEntity.Keywords, k.Fields), k.Keyword));
    }

    [Fact]
    public void EveryAliasIsInTheNormalizedMerchantKeyForm()
    {
        var seed = Load();

        Assert.All(
            seed.Merchants.SelectMany(m => m.Aliases),
            a =>
            {
                Assert.True(CatalogText.IsNormalized(a.Alias), a.Alias);
                Assert.True(CatalogText.IsAsciiText(a.Alias), a.Alias);
            });
    }

    [Fact]
    public void EveryCategoryReferenceExistsAndMerchantsAreUnique()
    {
        var seed = Load();
        var codes = seed.Categories.Select(c => c.Code).ToHashSet(StringComparer.Ordinal);

        Assert.All(seed.Merchants, m => Assert.Contains(m.Fields.Category!, codes));
        Assert.All(seed.Keywords, k => Assert.Contains(k.Fields.Category!, codes));
        Assert.Equal(seed.Merchants.Count, seed.Merchants.Select(m => m.Canonical).Distinct(StringComparer.Ordinal).Count());
        var aliases = seed.Merchants.SelectMany(m => m.Aliases.Select(a => a.Alias)).ToList();
        Assert.Equal(aliases.Count, aliases.Distinct(StringComparer.Ordinal).Count());
    }
}
