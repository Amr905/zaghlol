namespace Zaghlol.Api.Endpoints.Admin;

/// <summary><c>PriceOverrideRequest</c>: closed (any other member is <c>400 UNKNOWN_FIELD</c>); <c>price</c> is a decimal string, never a number.</summary>
public sealed class PriceOverrideRequest
{
    public required string Symbol { get; init; }

    public required string Currency { get; init; }

    public required string Price { get; init; }

    public required string Reason { get; init; }

    public DateTimeOffset? ExpiresAt { get; init; }
}

/// <summary><c>PriceOverrideResponse</c>.</summary>
public sealed class PriceOverrideResponse
{
    public required string Symbol { get; init; }

    public required string Currency { get; init; }

    public required string Price { get; init; }

    public required DateTimeOffset AsOf { get; init; }
}
