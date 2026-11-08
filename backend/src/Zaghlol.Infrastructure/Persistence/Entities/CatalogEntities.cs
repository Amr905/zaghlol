namespace Zaghlol.Infrastructure.Persistence.Entities;

// backend-schema.md section 2, "Catalog" (FR-BE-06, FR-SYNC-02). Published versions are immutable; catalog_drafts is T-125's.

/// <summary><c>catalog_versions</c>.</summary>
public sealed class CatalogVersion
{
    public int Version { get; set; }

    public DateTimeOffset PublishedAt { get; set; }

    public Guid PublishedBy { get; set; }

    public string? Notes { get; set; }

    public required Uri FullSnapshotUrl { get; set; }

    public required byte[] FullSnapshotSha256 { get; set; }
}

/// <summary><c>catalog_categories</c>.</summary>
public sealed class CatalogCategory
{
    public required string Code { get; set; }

    public string? ParentCode { get; set; }

    public required string NameAr { get; set; }

    public required string NameEn { get; set; }

    public required string Icon { get; set; }

    public required string Color { get; set; }

    public required string Bucket { get; set; }

    public int Sort { get; set; }

    public int Version { get; set; }

    public bool Deleted { get; set; }
}

/// <summary><c>catalog_merchants</c>; ids come from an identity sequence and are never reused.</summary>
public sealed class CatalogMerchant
{
    public int Id { get; set; }

    public required string Canonical { get; set; }

    public string? NameAr { get; set; }

    public string? NameEn { get; set; }

    public required string CategoryCode { get; set; }

    public int Version { get; set; }

    public bool Deleted { get; set; }
}

/// <summary><c>catalog_aliases</c>.</summary>
public sealed class CatalogAlias
{
    public int MerchantId { get; set; }

    public required string AliasNorm { get; set; }

    public required string Match { get; set; }

    public int Version { get; set; }

    public bool Deleted { get; set; }
}

/// <summary><c>catalog_keywords</c>: identity is (keyword, lang) (FU-009).</summary>
public sealed class CatalogKeyword
{
    public required string KeywordNorm { get; set; }

    public required string Lang { get; set; }

    public required string CategoryCode { get; set; }

    public int Weight { get; set; }

    public int Version { get; set; }

    public bool Deleted { get; set; }
}
