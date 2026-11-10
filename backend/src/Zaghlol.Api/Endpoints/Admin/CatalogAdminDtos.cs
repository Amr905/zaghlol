namespace Zaghlol.Api.Endpoints.Admin;

// The five catalog admin bodies (OpenAPI MerchantDraftRequest, AliasDraftRequest, KeywordDraftRequest, CategoryDraftRequest,
// CatalogPublishRequest). All closed: any other member is 400 UNKNOWN_FIELD. Key fields are never in a body (backend-api §5.2).

/// <summary><c>MerchantDraftRequest</c>: the non-key fields of a merchant (the id is allocated by the server or in the path).</summary>
public sealed class MerchantDraftRequest
{
    public required string Canonical { get; init; }

    public required string NameAr { get; init; }

    public required string Category { get; init; }
}

/// <summary><c>AliasDraftRequest</c>: <c>exact</c>, <c>prefix</c> or <c>token</c>.</summary>
public sealed class AliasDraftRequest
{
    public required string Match { get; init; }
}

/// <summary><c>KeywordDraftRequest</c>: the category and a weight from 0 to 100.</summary>
public sealed class KeywordDraftRequest
{
    public required string Category { get; init; }

    public required int Weight { get; init; }
}

/// <summary><c>CategoryDraftRequest</c>.</summary>
public sealed class CategoryDraftRequest
{
    public required string NameAr { get; init; }

    public required string NameEn { get; init; }

    public required string Icon { get; init; }

    public required string Color { get; init; }

    public required string Bucket { get; init; }

    public required int Sort { get; init; }
}

/// <summary><c>CatalogPublishRequest</c>: an optional note of up to 200 characters, kept with the version.</summary>
public sealed class CatalogPublishRequest
{
    public string? Note { get; init; }
}

/// <summary><c>CatalogPublishResponse</c>.</summary>
public sealed record CatalogPublishResponse(int Version, DateTimeOffset PublishedAt, string SnapshotUrl);
