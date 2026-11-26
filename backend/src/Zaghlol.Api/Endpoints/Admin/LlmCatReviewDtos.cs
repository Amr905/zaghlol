namespace Zaghlol.Api.Endpoints.Admin;

// The AI-category review bodies (OpenAPI LlmCat*). Requests are closed: any other member is 400 UNKNOWN_FIELD. Answers carry groups
// only: no install id, no hash, no per-install row.

/// <summary><c>LlmCatCorrectionsQueryRequest</c>.</summary>
public sealed class LlmCatCorrectionsQueryRequest
{
    public string? Status { get; init; }

    public int? Limit { get; init; }

    public string? Cursor { get; init; }
}

/// <summary><c>LlmCatConfirmedQueryRequest</c>.</summary>
public sealed class LlmCatConfirmedQueryRequest
{
    public int? Limit { get; init; }

    public string? Cursor { get; init; }
}

/// <summary><c>LlmCatCorrectionResolveRequest</c>.</summary>
public sealed class LlmCatCorrectionResolveRequest
{
    public required string MerchantNorm { get; init; }

    public required string AiCategory { get; init; }

    public required string UserCategory { get; init; }

    public required string Action { get; init; }
}

/// <summary><c>LlmCatConfirmedResolveRequest</c>.</summary>
public sealed class LlmCatConfirmedResolveRequest
{
    public required string MerchantNorm { get; init; }

    public required string Category { get; init; }

    public required string Action { get; init; }
}

/// <summary><c>LlmCatCorrectionGroup</c>; the days are UTC dates (<c>yyyy-MM-dd</c>).</summary>
public sealed record LlmCatCorrectionGroupDto(
    string MerchantNorm,
    string AiCategory,
    string UserCategory,
    int Votes,
    string FirstSeen,
    string LastSeen,
    string Status);

/// <summary><c>LlmCatCorrectionPage</c>.</summary>
public sealed record LlmCatCorrectionPageDto(IReadOnlyList<LlmCatCorrectionGroupDto> Items, string? NextCursor);

/// <summary><c>LlmCatConfirmedGroup</c>.</summary>
public sealed record LlmCatConfirmedGroupDto(string MerchantNorm, string Category, int Votes, string FirstSeen, string LastSeen);

/// <summary><c>LlmCatConfirmedPage</c>.</summary>
public sealed record LlmCatConfirmedPageDto(IReadOnlyList<LlmCatConfirmedGroupDto> Items, string? NextCursor);

/// <summary><c>LlmCatResolveResult</c>: the new status, the rows it moved and, for a promote, the draft merchant.</summary>
public sealed record LlmCatResolveResultDto(string Status, int Rows, int? MerchantId);
