using System.Globalization;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Seats;

namespace Zaghlol.Application.Entitlements;

/// <summary>The token's <c>status</c> (backend-api §4.3 <i>Entitlement token</i>).</summary>
public enum EntitlementStatus
{
    Active,
    Grace,
    Expired,
    Refunded,
    Moved,
    Paused,
    None,
}

/// <summary>One <c>src[]</c> element: which store and product the token's status rests on (no order, token or account data).</summary>
public sealed record EntitlementSource(string Store, string Product);

/// <summary>
/// The signed payload (JWS ES256). Serialized by the signer with web defaults, so the members are the wire names: <c>iss</c>,
/// <c>sub</c>, <c>acct</c>, <c>plan</c>, <c>status</c>, <c>exp</c>, <c>graceUntil</c>, <c>iat</c>, <c>nextMoveAt</c>, <c>movedBy</c>,
/// <c>src</c>, <c>v</c>. Times are Unix seconds, except <c>nextMoveAt</c>, an ISO-8601 UTC timestamp on a whole hour (like the
/// 409's), or <c>null</c> while no cooldown runs.
/// </summary>
public sealed record EntitlementClaims(
    string Iss,
    string Sub,
    string? Acct,
    string Plan,
    string Status,
    long Exp,
    long GraceUntil,
    long Iat,
    string? NextMoveAt,
    string? MovedBy,
    IReadOnlyList<EntitlementSource> Src,
    int V);

/// <summary>The account token's payload (backend-api §3): <c>{sub: accountId, iid: installId, iat, exp}</c>, <c>kid</c> in the header.</summary>
public sealed record AccountTokenClaims(string Sub, string Iid, long Iat, long Exp);

/// <summary>A purchase whose seat the install holds, in any stored state (so a refund or expiry is visible).</summary>
public sealed record HeldPurchase(
    Guid PurchaseId,
    PurchaseStore Store,
    string ProductId,
    GoldPlan Plan,
    StoredPurchaseState State,
    DateTimeOffset? ExpiresAt,
    Guid? AccountId,
    SeatProofKind Proof,
    DateTimeOffset? NextMoveAt);

/// <summary>An entitling purchase this install bought whose seat another install now holds.</summary>
public sealed record LostPurchase(
    Guid PurchaseId,
    PurchaseStore Store,
    string ProductId,
    GoldPlan Plan,
    DateTimeOffset? NextMoveAt,
    SeatMovedBy MovedBy);

public sealed record EntitlementFacts(IReadOnlyList<HeldPurchase> Held, IReadOnlyList<LostPurchase> Lost)
{
    public static EntitlementFacts Empty { get; } = new([], []);
}

/// <summary>A token with what the response needs next to it.</summary>
/// <param name="SupportNotice"><c>gold_linked_by_support</c> when the token was issued together with the notice (R4-7(2)).</param>
public sealed record EntitlementIssue(string Token, string? SupportNotice, EntitlementClaims Claims);

/// <summary>The wire spellings of the enums.</summary>
public static class EntitlementWire
{
    public const string Issuer = "zaghlol";
    public const int Version = 1;
    public const string SupportNoticeLinked = "gold_linked_by_support";
    public const string NoPlan = "none";

    public static string Status(EntitlementStatus status) => status switch
    {
        EntitlementStatus.Active => "active",
        EntitlementStatus.Grace => "grace",
        EntitlementStatus.Expired => "expired",
        EntitlementStatus.Refunded => "refunded",
        EntitlementStatus.Moved => "moved",
        EntitlementStatus.Paused => "paused",
        EntitlementStatus.None => "none",
        _ => throw new ArgumentOutOfRangeException(nameof(status)),
    };

    public static string Store(PurchaseStore store) => store switch
    {
        PurchaseStore.GooglePlay => "google_play",
        PurchaseStore.AppStore => "app_store",
        _ => throw new ArgumentOutOfRangeException(nameof(store)),
    };

    public static string Plan(GoldPlan plan) => plan switch
    {
        GoldPlan.Monthly => "monthly",
        GoldPlan.Yearly => "yearly",
        GoldPlan.Lifetime => "lifetime",
        _ => throw new ArgumentOutOfRangeException(nameof(plan)),
    };

    public static string Moment(DateTimeOffset value) => value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);
}
