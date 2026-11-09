using Zaghlol.Application.Catalog;

namespace Zaghlol.Application.Tests.Catalog;

public class CatalogSeedCsvTests
{
    private const string Header = "entity,code,nameAr,nameEn,icon,color,bucket,sort,canonical,category,alias,match,keyword,lang,weight\n";

    [Fact]
    public void ARepresentativeFileParsesIntoItsFourKinds()
    {
        var csv = "\uFEFF" + Header
            + "category,dining,\u0623\u0643\u0644,Dining,restaurant,#FFB86B,wants,3,,,,,,,\r\n"
            + "\n"
            + "merchant,,\u0643\u0634\u0631\u064A,,,,,,\"Koshary, El Tahrir\",dining,,,,,\n"
            + "alias,,,,,,,,\"Koshary, El Tahrir\",,\"koshary el tahrir\",exact,,,\n"
            + "alias,,,,,,,,\"Koshary, El Tahrir\",,tahrir,prefix,,,\n"
            + "keyword,,,,,,,,,dining,,,\u0645\u0637\u0639\u0645,ar,70\n";

        var seed = CatalogSeedCsv.Parse(csv);

        var category = Assert.Single(seed.Categories);
        Assert.Equal("dining", category.Code);
        Assert.Equal(3, category.Fields.Sort);
        Assert.Equal("#FFB86B", category.Fields.Color);
        var merchant = Assert.Single(seed.Merchants);
        Assert.Equal("Koshary, El Tahrir", merchant.Canonical);
        Assert.Equal("dining", merchant.Fields.Category);
        Assert.Equal(new[] { "koshary el tahrir", "tahrir" }, merchant.Aliases.Select(a => a.Alias));
        Assert.Equal(new[] { "exact", "prefix" }, merchant.Aliases.Select(a => a.Match));
        var keyword = Assert.Single(seed.Keywords);
        Assert.Equal(("ar", "\u0645\u0637\u0639\u0645", 70), (keyword.Lang, keyword.Keyword, keyword.Fields.Weight));
    }

    [Fact]
    public void AnAliasOfAnUnknownMerchantIsRejected()
    {
        var csv = Header + "alias,,,,,,,,Nobody,,x,exact,,,\n";

        Assert.Throws<CatalogSeedFormatException>(() => CatalogSeedCsv.Parse(csv));
    }

    [Theory]
    [InlineData("entity,code\ncategory,dining\n")]
    [InlineData("")]
    public void AMissingHeaderColumnOrAnEmptyFileIsRejected(string csv)
    {
        Assert.Throws<CatalogSeedFormatException>(() => CatalogSeedCsv.Parse(csv));
    }

    [Fact]
    public void AnUnknownEntityABadNumberOrAnOpenQuoteIsRejectedWithItsLine()
    {
        var unknown = Assert.Throws<CatalogSeedFormatException>(() => CatalogSeedCsv.Parse(Header + "\nplace,,,,,,,,,,,,,,\n"));
        var number = Assert.Throws<CatalogSeedFormatException>(() => CatalogSeedCsv.Parse(Header + "keyword,,,,,,,,,dining,,,x,en,heavy\n"));
        var quote = Assert.Throws<CatalogSeedFormatException>(() => CatalogSeedCsv.Parse(Header + "merchant,,\"open\n"));

        Assert.Equal(3, unknown.Line);
        Assert.Equal(2, number.Line);
        Assert.Equal(2, quote.Line);
        Assert.Equal(CatalogSeedFormatException.DefaultMessage, unknown.Message);
    }
}
