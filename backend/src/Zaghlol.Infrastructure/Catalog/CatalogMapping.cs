using Zaghlol.Application.Catalog;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Catalog;

/// <summary>Rows of the draft and live tables as <see cref="CatalogOp"/>s.</summary>
internal static class CatalogMapping
{
    public static CatalogOp FromDraft(CatalogDraftEntry row)
    {
        CatalogEntities.TryParse(row.Entity, out var entity);
        return new CatalogOp(CatalogKeys.FromStorage(entity, row.EntryKey), row.Deleted, CatalogFields.FromJson(row.Body));
    }

    public static CatalogOp FromCategory(CatalogCategory row) => new(
        CatalogKeys.FromStorage(CatalogEntity.Categories, row.Code),
        row.Deleted,
        new CatalogFields
        {
            NameAr = row.NameAr,
            NameEn = row.NameEn,
            Icon = row.Icon,
            Color = row.Color,
            Bucket = row.Bucket,
            Sort = row.Sort,
        });

    public static CatalogOp FromMerchant(CatalogMerchant row) => new(
        CatalogKeys.FromStorage(CatalogEntity.Merchants, row.Id.ToString(System.Globalization.CultureInfo.InvariantCulture)),
        row.Deleted,
        new CatalogFields { Canonical = row.Canonical, NameAr = row.NameAr, Category = row.CategoryCode });

    public static CatalogOp FromAlias(CatalogAlias row) => new(
        CatalogKeys.FromStorage(CatalogEntity.Aliases, CatalogKeys.StorageKeyOf(row.MerchantId, row.AliasNorm)),
        row.Deleted,
        new CatalogFields { Match = row.Match });

    public static CatalogOp FromKeyword(CatalogKeyword row) => new(
        CatalogKeys.FromStorage(CatalogEntity.Keywords, CatalogKeys.StorageKeyOf(row.Lang, row.KeywordNorm)),
        row.Deleted,
        new CatalogFields { Category = row.CategoryCode, Weight = row.Weight });
}
