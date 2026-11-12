using Zaghlol.Application.Purchases;
using Zaghlol.Application.Seats;
using Zaghlol.Domain;

namespace Zaghlol.Application.Entitlements;

/// <summary>The lifetimes of D-60 and the refresh rules (backend-api §4.3, §4.2).</summary>
public static class EntitlementLifetimes
{
    /// <summary>Every plan, lifetime included: <c>exp ≤ iat + 3 d</c>.</summary>
    public static readonly TimeSpan MaxLife = TimeSpan.FromDays(3);

    /// <summary>A token covering a <c>basic</c> seat: <c>exp ≤ iat + 2 d</c>.</summary>
    public static readonly TimeSpan BasicMaxLife = TimeSpan.FromDays(2);

    /// <summary><c>graceUntil = exp + 4 d</c>.</summary>
    public static readonly TimeSpan GraceAfterExpiry = TimeSpan.FromDays(4);

    /// <summary>Sync sends a fresh token when the cached one is older than this.</summary>
    public static readonly TimeSpan RefreshAfter = TimeSpan.FromHours(12);

    public static readonly TimeSpan AccountTokenLife = TimeSpan.FromDays(30);

    /// <summary>Sync refreshes the account token with less than this left.</summary>
    public static readonly TimeSpan AccountTokenRefreshWindow = TimeSpan.FromDays(7);
}

/// <summary>
/// The pure entitlement decision: which status, plan and lifetime an install's token gets from the seat and purchase rows (T-132).
/// No I/O. A token covers only purchases whose seat the install holds (never another install's); an account-linked purchase
/// only with a valid account token for its account, else it is <c>paused</c> (D-61(c)).
/// </summary>
public static class EntitlementRules
{
    /// <summary>Best first: an entitling purchase beats a paused one, which beats a lost seat, a refund and an expiry.</summary>
    private static readonly EntitlementStatus[] Priority =
        [EntitlementStatus.Active, EntitlementStatus.Grace, EntitlementStatus.Paused, EntitlementStatus.Moved, EntitlementStatus.Refunded, EntitlementStatus.Expired];

    public static EntitlementClaims Build(InstallId install, EntitlementFacts facts, Guid? presentedAccount, DateTimeOffset now)
    {
        ArgumentNullException.ThrowIfNull(facts);

        var iat = Whole(now);
        var candidates = new List<Candidate>();
        foreach (var held in facts.Held)
        {
            candidates.Add(Classify(held, presentedAccount, now));
        }

        foreach (var lost in facts.Lost)
        {
            candidates.Add(new Candidate(EntitlementStatus.Moved, lost.Plan, lost.Store, lost.ProductId, null, null, false, lost.NextMoveAt, lost.MovedBy));
        }

        var status = Priority.FirstOrDefault(s => candidates.Any(c => c.Status == s), EntitlementStatus.None);
        var group = candidates.Where(c => c.Status == status).ToList();
        var life = group.Any(c => c.Basic) ? EntitlementLifetimes.BasicMaxLife : EntitlementLifetimes.MaxLife;
        var exp = iat + life;
        if (status is EntitlementStatus.Active or EntitlementStatus.Grace)
        {
            // A subscription never outlives its store expiry; a lifetime purchase (no expiry) only the 3 days.
            var storeExpiry = Whole(group.Select(c => c.ExpiresAt ?? DateTimeOffset.MaxValue).Max());
            if (storeExpiry < exp)
            {
                exp = storeExpiry < iat ? iat : storeExpiry;
            }
        }

        var next = group.Where(c => c.NextMoveAt > now).Select(c => c.NextMoveAt).Max();
        var acct = status is EntitlementStatus.Active or EntitlementStatus.Grace
            ? group.Select(c => c.Account).FirstOrDefault(a => a is not null)
            : null;
        var movedBy = status == EntitlementStatus.Moved
            ? (group.Any(c => c.MovedBy == SeatMovedBy.Support) ? "support" : "user")
            : null;
        var plan = group.Count == 0 ? EntitlementWire.NoPlan : EntitlementWire.Plan(group.Max(c => c.Plan));
        var sources = group
            .Select(c => new EntitlementSource(EntitlementWire.Store(c.Store), c.Product))
            .Distinct()
            .OrderBy(s => s.Product, StringComparer.Ordinal)
            .ThenBy(s => s.Store, StringComparer.Ordinal)
            .ToList();

        return new EntitlementClaims(
            EntitlementWire.Issuer,
            install.ToString(),
            acct?.ToString("D", System.Globalization.CultureInfo.InvariantCulture),
            plan,
            EntitlementWire.Status(status),
            exp.ToUnixTimeSeconds(),
            (exp + EntitlementLifetimes.GraceAfterExpiry).ToUnixTimeSeconds(),
            iat.ToUnixTimeSeconds(),
            next is { } n ? EntitlementWire.Moment(n) : null,
            movedBy,
            sources,
            EntitlementWire.Version);
    }

    private static Candidate Classify(HeldPurchase held, Guid? presentedAccount, DateTimeOffset now)
    {
        var entitlingState = held.State is StoredPurchaseState.Active or StoredPurchaseState.InGrace or StoredPurchaseState.CanceledActive;
        var entitling = entitlingState && (held.ExpiresAt is null || held.ExpiresAt > now);
        var status = entitling
            ? held.AccountId is { } linked && presentedAccount != linked
                ? EntitlementStatus.Paused
                : held.State == StoredPurchaseState.InGrace ? EntitlementStatus.Grace : EntitlementStatus.Active
            : held.State is StoredPurchaseState.Refunded or StoredPurchaseState.Revoked ? EntitlementStatus.Refunded : EntitlementStatus.Expired;
        return new Candidate(
            status, held.Plan, held.Store, held.ProductId, held.ExpiresAt, held.AccountId, held.Proof == SeatProofKind.Basic, held.NextMoveAt, null);
    }

    internal static DateTimeOffset Whole(DateTimeOffset value)
    {
        var utc = value.ToUniversalTime();
        return new DateTimeOffset(utc.Ticks - (utc.Ticks % TimeSpan.TicksPerSecond), TimeSpan.Zero);
    }

    private sealed record Candidate(
        EntitlementStatus Status,
        GoldPlan Plan,
        PurchaseStore Store,
        string Product,
        DateTimeOffset? ExpiresAt,
        Guid? Account,
        bool Basic,
        DateTimeOffset? NextMoveAt,
        SeatMovedBy? MovedBy);
}
