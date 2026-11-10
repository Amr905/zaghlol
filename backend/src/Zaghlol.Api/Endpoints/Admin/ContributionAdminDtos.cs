namespace Zaghlol.Api.Endpoints.Admin;

// The contribution review bodies (OpenAPI ContributionKey, ContributionPromoteRequest, ContributionAggregate, ContributionQueue,
// ContributionDecision). Requests are closed: any other member is 400 UNKNOWN_FIELD.

/// <summary><c>ContributionKey</c> (the body of <c>:reject</c>).</summary>
public sealed class ContributionKeyRequest
{
    public required string MerchantNorm { get; init; }

    public required string InstitutionCode { get; init; }
}

/// <summary><c>ContributionPromoteRequest</c>.</summary>
public sealed class ContributionPromoteRequest
{
    public required string MerchantNorm { get; init; }

    public required string InstitutionCode { get; init; }

    public int? MerchantId { get; init; }

    public string? CategoryCode { get; init; }
}

/// <summary><c>ContributionAggregate</c>.</summary>
public sealed record ContributionAggregateDto(string MerchantNorm, string InstitutionCode, string CategoryCode, int DistinctInstalls, string Status);

/// <summary><c>ContributionQueue</c>.</summary>
public sealed record ContributionQueueDto(IReadOnlyList<ContributionAggregateDto> Items);

/// <summary><c>ContributionDecision</c>.</summary>
public sealed record ContributionDecisionDto(string MerchantNorm, string InstitutionCode, string Status, int? MerchantId);
