using System.Text.Json.Serialization;
using Zaghlol.Api.Signing;
using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// <c>PurchaseVerifyRequest</c> (backend-api §4.3): the OpenAPI <c>oneOf</c> on <c>platform</c> as one closed type. Android carries
/// <c>productId</c> and <c>purchaseToken</c>; iOS <c>signedTransaction</c> and optional <c>seatKeys</c>; a member of the other
/// platform is <c>400 UNKNOWN_FIELD</c>, anything else too (BR-SYNC-03: only the purchase token class of data). Secrets are
/// <see cref="Sensitive{T}"/>.
/// </summary>
public sealed class PurchaseVerifyRequest
{
    public required string Platform { get; init; }

    public string? ProductId { get; init; }

    public Sensitive<string>? PurchaseToken { get; init; }

    public Sensitive<string>? SignedTransaction { get; init; }

    public Sensitive<IReadOnlyList<VerifySeatKeyInput>>? SeatKeys { get; init; }
}

/// <summary>OpenAPI <c>SeatKeyProof</c> (iOS, T-131/T-182 verify it).</summary>
public sealed class VerifySeatKeyInput
{
    public required string PublicKey { get; init; }

    public required string Signature { get; init; }
}

/// <summary><c>PurchaseVerifyResponse</c>: signed, echoes the time nonce, never carries <c>rotateInstallToken</c> (S-3).</summary>
public sealed class PurchaseVerifyResponse : IAnchoredResponse
{
    public required string Status { get; init; }

    [JsonIgnore(Condition = JsonIgnoreCondition.Never)]
    public required PurchaseEntitlementDto? Entitlement { get; init; }

    public required bool SeatHeldElsewhere { get; init; }

    public required bool AccountRequired { get; init; }

    [JsonIgnore(Condition = JsonIgnoreCondition.Never)]
    public required DateTimeOffset? NextMoveAt { get; init; }

    public required DateTimeOffset ServerTime { get; init; }

    [JsonIgnore(Condition = JsonIgnoreCondition.Never)]
    public required string? TimeNonce { get; init; }
}

/// <summary>OpenAPI <c>Entitlement</c>: the ES256 JWS (T-132 issues it).</summary>
public sealed class PurchaseEntitlementDto
{
    public required Sensitive<string> Token { get; init; }
}
