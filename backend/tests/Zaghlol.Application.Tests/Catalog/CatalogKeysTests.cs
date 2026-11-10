using Zaghlol.Application.Catalog;

namespace Zaghlol.Application.Tests.Catalog;

/// <summary>FU-009: path keys must be canonical (backend-api §5.2).</summary>
public class CatalogKeysTests
{
    // b64u("koshary el tahrir") from backend-api §5.2; the last character carries 2 spare bits that must be zero.
    private const string KosharyAlias = "a29zaGFyeSBlbCB0YWhyaXI";

    // b64u("Koshary"): decodes cleanly but is not in normalized (lower-case) form.
    private const string UpperCaseAlias = "S29zaGFyeQ";

    private const string PharmacyKeyword = "2LXZitiv2YTZitip";

    private const string Pharmacy = "\u0635\u064A\u062F\u0644\u064A\u0629";

    [Fact]
    public void ACanonicalAliasKeyParses()
    {
        Assert.True(CatalogKeys.TryParse(CatalogEntity.Aliases, "812:" + KosharyAlias, out var key));

        Assert.Equal(812, key.MerchantId);
        Assert.Equal("koshary el tahrir", key.Text);
        Assert.Equal("812:koshary el tahrir", key.StorageKey);
        Assert.Equal("812:" + KosharyAlias, key.PathId);
    }

    [Fact]
    public void AnAliasKeyWithPaddingIsRejected()
    {
        Assert.False(CatalogKeys.TryParse(CatalogEntity.Aliases, "812:" + KosharyAlias + "=", out _));
    }

    [Fact]
    public void AnAliasKeyWithNonZeroTrailingBitsIsRejected()
    {
        // 'J' (001001) instead of 'I' (001000): the same 17 bytes would decode, but re-encoding gives 'I'.
        var tampered = KosharyAlias[..^1] + "J";

        Assert.False(CatalogKeys.TryParse(CatalogEntity.Aliases, "812:" + tampered, out _));
    }

    [Fact]
    public void AnAliasKeyThatDecodesToNonNormalizedTextIsRejected()
    {
        Assert.False(CatalogKeys.TryParse(CatalogEntity.Aliases, "812:" + UpperCaseAlias, out _));
    }

    [Fact]
    public void AKeywordKeyRoundTrips()
    {
        Assert.True(CatalogKeys.TryParse(CatalogEntity.Keywords, "ar:" + PharmacyKeyword, out var key));

        Assert.Equal("ar", key.Lang);
        Assert.Equal(Pharmacy, key.Text);
        Assert.Equal("ar:" + PharmacyKeyword, CatalogKeys.KeywordPathId(key.Lang!, key.Text!));
        Assert.Equal("ar:" + Pharmacy, key.StorageKey);
        Assert.Equal(key.PathId, CatalogKeys.FromStorage(CatalogEntity.Keywords, key.StorageKey).PathId);
    }

    [Theory]
    [InlineData("__4")] // 0xFF 0xFE: not UTF-8
    [InlineData("YQ==")]
    [InlineData("Y")] // one character is never valid base64
    [InlineData("a b")]
    [InlineData("YQ/+")]
    public void AKeywordKeyThatIsNotCanonicalBase64UrlOfUtf8IsRejected(string encoded)
    {
        Assert.False(CatalogKeys.TryParse(CatalogEntity.Keywords, "en:" + encoded, out _));
    }

    [Fact]
    public void AnAliasMustBeAsciiAndAtMost64Characters()
    {
        Assert.False(CatalogKeys.TryParse(CatalogEntity.Aliases, "812:" + PharmacyKeyword, out _));
        Assert.True(CatalogKeys.TryParse(CatalogEntity.Aliases, "1:" + CatalogKeys.EncodeText(new string('a', 64)), out _));
        Assert.False(CatalogKeys.TryParse(CatalogEntity.Aliases, "1:" + CatalogKeys.EncodeText(new string('a', 65)), out _));
    }

    [Theory]
    [InlineData("xx:YQ")] // lang must be two letters of a-z: this is fine
    public void AKeywordLangIsTwoLowercaseLetters(string id)
    {
        Assert.True(CatalogKeys.TryParse(CatalogEntity.Keywords, id, out _));
    }

    [Theory]
    [InlineData("AR:YQ")]
    [InlineData("a:YQ")]
    [InlineData("arb:YQ")]
    [InlineData("a1:YQ")]
    [InlineData(":YQ")]
    public void AKeywordLangThatIsNotTwoLowercaseLettersIsRejected(string id)
    {
        Assert.False(CatalogKeys.TryParse(CatalogEntity.Keywords, id, out _));
    }

    [Theory]
    [InlineData("dining", true)]
    [InlineData("a1", true)]
    [InlineData("Dining", false)]
    [InlineData("1dining", false)]
    [InlineData("a", false)]
    [InlineData("has-dash", false)]
    [InlineData("812", false)]
    public void CategoryKeysAreLowercaseSlugs(string id, bool valid)
    {
        Assert.Equal(valid, CatalogKeys.TryParse(CatalogEntity.Categories, id, out _));
    }

    [Theory]
    [InlineData("812", true)]
    [InlineData("1", true)]
    [InlineData("999999999", true)]
    [InlineData("0", false)]
    [InlineData("0812", false)]
    [InlineData("1000000000", false)]
    [InlineData("-5", false)]
    [InlineData("8a", false)]
    [InlineData("\u0668\u0661\u0662", false)] // Arabic-Indic digits
    public void MerchantKeysAreIntegersWithoutLeadingZero(string id, bool valid)
    {
        Assert.Equal(valid, CatalogKeys.TryParse(CatalogEntity.Merchants, id, out _));
    }

    [Fact]
    public void AnAliasKeyNeedsAMerchantIdAndAText()
    {
        Assert.False(CatalogKeys.TryParse(CatalogEntity.Aliases, KosharyAlias, out _));
        Assert.False(CatalogKeys.TryParse(CatalogEntity.Aliases, "0:" + KosharyAlias, out _));
        Assert.False(CatalogKeys.TryParse(CatalogEntity.Aliases, "812:", out _));
        Assert.False(CatalogKeys.TryParse(CatalogEntity.Aliases, null, out _));
        Assert.False(CatalogKeys.TryParse(CatalogEntity.Aliases, new string('a', CatalogKeys.MaxPathLength + 1), out _));
    }

    [Fact]
    public void EntityNamesRoundTrip()
    {
        foreach (var entity in Enum.GetValues<CatalogEntity>())
        {
            Assert.True(CatalogEntities.TryParse(CatalogEntities.Name(entity), out var parsed));
            Assert.Equal(entity, parsed);
        }

        Assert.False(CatalogEntities.TryParse("Merchants", out _));
        Assert.False(CatalogEntities.TryParse(null, out _));
    }
}
