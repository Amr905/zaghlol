using System.Text.Json.Serialization;
using Zaghlol.Api.Signing;
using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// <c>SignInRequest</c> (backend-api §4.6): exactly the members of BR-SYNC-03's account token class, no others (unknown members are
/// <c>400 UNKNOWN_FIELD</c>). <c>nonce</c> is optional here so a request without one is <c>422 ID_TOKEN_INVALID</c> (R2-9), not a
/// parse error. Every secret is <see cref="Sensitive{T}"/>.
/// </summary>
public sealed class SignInRequestDto
{
    public required string Provider { get; init; }

    public required Sensitive<string> IdToken { get; init; }

    public Sensitive<string>? Nonce { get; init; }

    public Sensitive<string>? AuthorizationCode { get; init; }

    public bool? ReplaceLink { get; init; }

    public Sensitive<IReadOnlyList<VerifySeatKeyInput>>? SeatKeys { get; init; }
}

/// <summary><c>SignInResponse</c>: signed, echoes the time nonce, never carries <c>rotateInstallToken</c>.</summary>
public sealed class SignInResponse : IAnchoredResponse
{
    public required Guid AccountId { get; init; }

    public required Sensitive<string> AccountToken { get; init; }

    public required PurchaseEntitlementDto Entitlement { get; init; }

    public required int LinkedInstalls { get; init; }

    public required bool MovedFromOtherPhone { get; init; }

    public required bool MoveRefused { get; init; }

    public required bool RestoreSuggested { get; init; }

    [JsonIgnore(Condition = JsonIgnoreCondition.Never)]
    public required DateTimeOffset? NextMoveAt { get; init; }

    public required DateTimeOffset ServerTime { get; init; }

    [JsonIgnore(Condition = JsonIgnoreCondition.Never)]
    public required string? TimeNonce { get; init; }
}
