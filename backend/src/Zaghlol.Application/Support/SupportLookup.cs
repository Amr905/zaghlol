using System.Text;
using Zaghlol.Domain;

namespace Zaghlol.Application.Support;

/// <summary>How the operator identified the user: an exact install ID or an exact account e-mail.</summary>
public enum SupportLookupKind
{
    Install,
    Email,
}

/// <summary>
/// One purchase as the lookup store reads it. Relations to the looked-up install are booleans computed in SQL, so no other
/// install's ID ever leaves the database. Enum columns are the database strings (backend-schema §2), which equal the API's.
/// </summary>
public sealed record SupportPurchaseRow(
    Guid PurchaseId,
    string Plan,
    string State,
    string Store,
    DateTimeOffset? ExpiresAt,
    bool AccountLinked,
    string? LinkedBy,
    DateTimeOffset? DisputeFrozenUntil,
    bool SeatHeld,
    bool LookedUpIsHolder,
    bool LookedUpIsClaimant,
    bool LookedUpIsBuyer,
    DateTimeOffset? LastMovedAt,
    DateTimeOffset? NextMoveAt,
    long PendingClaimants,
    bool BuyingInstallSilent,
    long RebindsLast30Days);

/// <summary>One purchase of <c>SupportEntitlement.purchases</c> (OpenAPI <c>SupportPurchase</c>).</summary>
public sealed record SupportPurchaseView(
    Guid PurchaseId,
    string Plan,
    string State,
    string Store,
    string Seat,
    bool AccountLinked,
    string? LinkedBy,
    DateTimeOffset? LastMovedAt,
    DateTimeOffset? NextMoveAt,
    int PendingClaimants,
    bool BuyingInstallSilent,
    bool? IsBuyingInstall,
    DateTimeOffset? DisputeFrozenUntil,
    int RebindsLast30Days);

/// <summary>OpenAPI <c>SupportEntitlement</c>: entitlement and seat status only.</summary>
public sealed record SupportEntitlementView(
    string Status,
    IReadOnlyList<SupportPurchaseView> Purchases,
    string? Plan,
    DateTimeOffset? Exp,
    DateTimeOffset? GraceUntil);

/// <summary>
/// The audited support lookup (backend-api §5.2) on the admin login. Each call reads the related purchases and writes its
/// <c>support_lookup</c> audit row in one transaction; a failed audit insert fails the lookup.
/// </summary>
public interface ISupportLookupStore
{
    Task<SupportEntitlementView> LookupInstallAsync(Guid operatorId, InstallId installId, CancellationToken cancellationToken);

    /// <param name="normalizedEmail">The output of <see cref="SupportEmail.TryNormalize"/>.</param>
    Task<SupportEntitlementView> LookupEmailAsync(Guid operatorId, string normalizedEmail, CancellationToken cancellationToken);
}

/// <summary>Builds <see cref="SupportEntitlementView"/> from the rows (pure, unit-tested).</summary>
public static class SupportEntitlementBuilder
{
    /// <summary>The response's <c>maxItems</c>.</summary>
    public const int MaxPurchases = 20;

    public const int MaxPendingClaimants = 3;
    public const int MaxRebinds = 2;

    /// <summary>Pending claimants are kept 7 days (backend-api §4.3).</summary>
    public static readonly TimeSpan ClaimantWindow = TimeSpan.FromDays(7);

    /// <summary>The rebind cap's rolling window (D-63) and the attach gate's silence (D-57(d)).</summary>
    public static readonly TimeSpan ThirtyDays = TimeSpan.FromDays(30);

    /// <summary>
    /// Per purchase: <c>seat</c> is <c>holder|claimant|none</c> for an install lookup and <c>held|vacant</c> for an e-mail
    /// lookup; <c>isBuyingInstall</c> is <c>null</c> for an e-mail lookup; a dispute freeze that already ended is <c>null</c>;
    /// counters are clamped to the documented ranges. Top-level <c>status</c>: the best entitling seat the key holds
    /// (<c>active</c> over <c>grace</c> over <c>paused</c>); otherwise <c>moved</c> when the looked-up install bought or claimed
    /// a purchase whose live seat is elsewhere; otherwise <c>refunded</c>, <c>expired</c> or <c>none</c>. <c>graceUntil</c> is
    /// the store expiry while in grace.
    /// </summary>
    public static SupportEntitlementView Build(SupportLookupKind kind, IReadOnlyList<SupportPurchaseRow> rows, DateTimeOffset now)
    {
        ArgumentNullException.ThrowIfNull(rows);

        var purchases = rows.Take(MaxPurchases).Select(row => View(kind, row, now)).ToList();

        var held = rows.Where(row => kind == SupportLookupKind.Install ? row.LookedUpIsHolder : row.SeatHeld)
            .Select(row => (Row: row, Status: EntitlingStatus(row.State)))
            .Where(x => x.Status is not null)
            .OrderBy(x => Rank(x.Status!))
            .ThenByDescending(x => x.Row.ExpiresAt ?? DateTimeOffset.MaxValue)
            .FirstOrDefault();
        if (held.Row is { } best)
        {
            var status = held.Status!;
            return new SupportEntitlementView(status, purchases, best.Plan, best.ExpiresAt, status == "grace" ? best.ExpiresAt : null);
        }

        if (kind == SupportLookupKind.Install
            && rows.Any(row => row.SeatHeld && !row.LookedUpIsHolder && (row.LookedUpIsBuyer || row.LookedUpIsClaimant)
                               && EntitlingStatus(row.State) is not null))
        {
            return new SupportEntitlementView("moved", purchases, null, null, null);
        }

        foreach (var (states, status) in new[] { (RefundedStates, "refunded"), (ExpiredStates, "expired") })
        {
            if (rows.FirstOrDefault(row => states.Contains(row.State, StringComparer.Ordinal)) is { } ended)
            {
                return new SupportEntitlementView(status, purchases, ended.Plan, ended.ExpiresAt, null);
            }
        }

        return new SupportEntitlementView("none", purchases, null, null, null);
    }

    private static readonly string[] RefundedStates = ["refunded", "revoked"];
    private static readonly string[] ExpiredStates = ["expired"];

    private static SupportPurchaseView View(SupportLookupKind kind, SupportPurchaseRow row, DateTimeOffset now)
    {
        var byInstall = kind == SupportLookupKind.Install;
        var seat = byInstall
            ? row.LookedUpIsHolder ? "holder" : row.LookedUpIsClaimant ? "claimant" : "none"
            : row.SeatHeld ? "held" : "vacant";
        return new SupportPurchaseView(
            row.PurchaseId,
            row.Plan,
            row.State,
            row.Store,
            seat,
            row.AccountLinked,
            row.AccountLinked ? row.LinkedBy : null,
            row.LastMovedAt,
            row.NextMoveAt,
            (int)Math.Clamp(row.PendingClaimants, 0, MaxPendingClaimants),
            row.BuyingInstallSilent,
            byInstall ? row.LookedUpIsBuyer : (bool?)null,
            row.DisputeFrozenUntil is { } until && until > now ? until : (DateTimeOffset?)null,
            (int)Math.Clamp(row.RebindsLast30Days, 0, MaxRebinds));
    }

    /// <summary><c>active</c>, <c>grace</c> or <c>paused</c> for a state that keeps Gold (or pauses it), else <c>null</c>.</summary>
    private static string? EntitlingStatus(string state) => state switch
    {
        "active" or "canceled_active" => "active",
        "in_grace" => "grace",
        "on_hold" or "paused" => "paused",
        _ => null,
    };

    private static int Rank(string status) => status switch
    {
        "active" => 0,
        "grace" => 1,
        _ => 2,
    };
}

/// <summary>The e-mail key of a support lookup: validated, then normalised as <c>NFC(trim(lower(email)))</c>.</summary>
public static class SupportEmail
{
    /// <summary>OpenAPI <c>SupportLookupByEmail.email.maxLength</c>.</summary>
    public const int MaxLength = 254;

    /// <summary>
    /// False for anything that isn't one plausible address: empty after trimming, longer than 254 characters, a control
    /// character or inner whitespace, or not exactly one <c>@</c> with text on both sides. The value is never echoed.
    /// </summary>
    public static bool TryNormalize(string? raw, out string normalized)
    {
        normalized = string.Empty;
        if (raw is null || raw.Length > MaxLength)
        {
            return false;
        }

#pragma warning disable CA1308 // backend-api §5.2 defines the key as lower(email).
        var value = raw.ToLowerInvariant().Trim();
#pragma warning restore CA1308
        if (!value.IsNormalized(NormalizationForm.FormC))
        {
            value = value.Normalize(NormalizationForm.FormC);
        }

        var at = value.IndexOf('@', StringComparison.Ordinal);
        if (value.Length is 0 or > MaxLength
            || at <= 0
            || at == value.Length - 1
            || value.IndexOf('@', at + 1) >= 0
            || value.Any(c => char.IsControl(c) || char.IsWhiteSpace(c)))
        {
            return false;
        }

        normalized = value;
        return true;
    }
}
