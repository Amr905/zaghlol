using System.Text;
using Zaghlol.Application.Catalog;

namespace Zaghlol.Application.Tests.Catalog;

public class CatalogOpsTests
{
    [Fact]
    public void ADeltaListsAliasDeletesBeforeTheMerchantDeleteAndParentsBeforeChildren()
    {
        var ops = new[]
        {
            Delete(CatalogEntity.Categories, "old"),
            Delete(CatalogEntity.Merchants, "812"),
            Delete(CatalogEntity.Aliases, "812:koshary"),
            Upsert(CatalogEntity.Keywords, "ar:x", new CatalogFields { Category = "dining", Weight = 5 }),
            Upsert(CatalogEntity.Aliases, "9:abc", new CatalogFields { Match = "exact" }),
            Upsert(CatalogEntity.Merchants, "9", new CatalogFields { Canonical = "Abc", NameAr = "x", Category = "dining" }),
            Delete(CatalogEntity.Keywords, "en:gone"),
            Upsert(CatalogEntity.Categories, "dining", new CatalogFields()),
            Delete(CatalogEntity.Aliases, "812:another"),
        };

        var ordered = CatalogDeltaOrder.Order(ops).Select(o => (o.Delete ? "-" : "+") + CatalogEntities.Name(o.Key.Entity) + "/" + o.Key.StorageKey).ToList();

        string[] expected =
        [
            "+categories/dining", "+merchants/9", "+aliases/9:abc", "+keywords/ar:x",
            "-keywords/en:gone", "-aliases/812:another", "-aliases/812:koshary", "-merchants/812", "-categories/old",
        ];
        Assert.Equal(expected, ordered);
    }

    [Fact]
    public void AnEmptyDeltaStaysEmpty()
    {
        Assert.Empty(CatalogDeltaOrder.Order([]));
    }

    [Fact]
    public void SnapshotJsonHasAFixedShapeAndKeepsArabicReadable()
    {
        var ops = new[]
        {
            Upsert(CatalogEntity.Categories, "dining", new CatalogFields { NameAr = "\u0623\u0643\u0644", NameEn = "Dining", Icon = "restaurant", Color = "#FFB86B", Bucket = "wants", Sort = 3 }),
            Upsert(CatalogEntity.Merchants, "812", new CatalogFields { Canonical = "Koshary", NameAr = "\u0643\u0634\u0631\u064A", Category = "dining" }),
            Upsert(CatalogEntity.Aliases, "812:koshary", new CatalogFields { Match = "prefix" }),
            Upsert(CatalogEntity.Keywords, "ar:" + "\u0635", new CatalogFields { Category = "dining", Weight = 80 }),
        };

        var json = Encoding.UTF8.GetString(CatalogJson.Snapshot(7, ops));

        Assert.Equal(
            "{\"version\":7,\"ops\":["
            + "{\"t\":\"category\",\"op\":\"upsert\",\"code\":\"dining\",\"nameAr\":\"\u0623\u0643\u0644\",\"nameEn\":\"Dining\",\"icon\":\"restaurant\",\"color\":\"#FFB86B\",\"bucket\":\"wants\",\"sort\":3},"
            + "{\"t\":\"merchant\",\"op\":\"upsert\",\"id\":812,\"canonical\":\"Koshary\",\"nameAr\":\"\u0643\u0634\u0631\u064A\",\"category\":\"dining\"},"
            + "{\"t\":\"alias\",\"op\":\"upsert\",\"merchantId\":812,\"alias\":\"koshary\",\"match\":\"prefix\"},"
            + "{\"t\":\"keyword\",\"op\":\"upsert\",\"keyword\":\"\u0635\",\"lang\":\"ar\",\"category\":\"dining\",\"weight\":80}"
            + "]}",
            json);
    }

    [Fact]
    public void TombstonesCarryTheKeyOnly()
    {
        var ops = new[]
        {
            Delete(CatalogEntity.Categories, "old"),
            Delete(CatalogEntity.Merchants, "812"),
            Delete(CatalogEntity.Aliases, "812:koshary"),
            Delete(CatalogEntity.Keywords, "en:gone"),
        };

        var json = Encoding.UTF8.GetString(CatalogJson.Snapshot(2, ops));

        Assert.Equal(
            "{\"version\":2,\"ops\":["
            + "{\"t\":\"category\",\"op\":\"delete\",\"code\":\"old\"},"
            + "{\"t\":\"merchant\",\"op\":\"delete\",\"id\":812},"
            + "{\"t\":\"alias\",\"op\":\"delete\",\"merchantId\":812,\"alias\":\"koshary\"},"
            + "{\"t\":\"keyword\",\"op\":\"delete\",\"keyword\":\"gone\",\"lang\":\"en\"}"
            + "]}",
            json);
    }

    [Fact]
    public void APageWritesItsCursorOrNull()
    {
        var op = Upsert(CatalogEntity.Aliases, "1:a", new CatalogFields { Match = "exact" });

        Assert.Equal(
            "{\"items\":[{\"t\":\"alias\",\"op\":\"upsert\",\"merchantId\":1,\"alias\":\"a\",\"match\":\"exact\"}],\"nextCursor\":\"42\"}",
            Encoding.UTF8.GetString(CatalogJson.Page([op], "42")));
        Assert.Equal("{\"items\":[],\"nextCursor\":null}", Encoding.UTF8.GetString(CatalogJson.Page([], null)));
    }

    [Fact]
    public void FieldsSurviveTheirJsonbForm()
    {
        var fields = new CatalogFields { Canonical = "Koshary \"El\" Tahrir", NameAr = "\u0643\u0634\u0631\u064A", Category = "dining" };

        var json = fields.ToJson();

        Assert.Equal(fields, CatalogFields.FromJson(json));
        Assert.DoesNotContain("null", json, StringComparison.Ordinal);
        Assert.Contains("\"nameAr\"", json, StringComparison.Ordinal);
    }

    private static CatalogOp Upsert(CatalogEntity entity, string storageKey, CatalogFields fields) =>
        new(CatalogKeys.FromStorage(entity, storageKey), false, fields);

    private static CatalogOp Delete(CatalogEntity entity, string storageKey) =>
        new(CatalogKeys.FromStorage(entity, storageKey), true, new CatalogFields());
}
