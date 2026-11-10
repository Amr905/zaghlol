using Zaghlol.Application.Catalog;
using Zaghlol.Application.Flags;
using Zaghlol.Application.Prices;
using Zaghlol.Domain;

namespace Zaghlol.Application.Sync;

/// <summary>One opt-in merchant contribution as received (OpenAPI <c>ContributionInput</c>, BR-SYNC-03/04).</summary>
public sealed record SyncContribution(string MerchantNorm, string InstitutionCode, string CategoryCode);

/// <summary>One "request my bank" submission as received (OpenAPI <c>BankRequestInput</c>, FR-PAR-14).</summary>
public sealed record SyncBankRequest(string InstitutionName, string Country, string Channel);

/// <summary>
/// What the sync handler accepts from the app, already shape-checked by the API (closed DTOs, caps of 50 / 10). Nothing else
/// from the request reaches the application layer; <c>registryVersion</c> is diagnostic and not used.
/// </summary>
public sealed record SyncRequestData(
    int CatalogVersion,
    int FlagsVersion,
    DateTimeOffset? PricesAsOf,
    DateTimeOffset? EntitlementIssuedAt,
    IReadOnlyList<SyncContribution> Contributions,
    IReadOnlyList<SyncBankRequest> BankRequests);

/// <summary>The install row as the sync sees it: platform and app version before this call, and the throttle state.</summary>
public sealed record SyncInstall(string Platform, string AppVersion, DateTimeOffset? LastSyncAt);

/// <summary>Catalog modes on the wire (OpenAPI <c>CatalogDelta.mode</c>) and the metric tag <c>none</c>.</summary>
public static class CatalogModes
{
    public const string None = "none";
    public const string Delta = "delta";
    public const string Full = "full";
}

/// <summary>The <c>catalog</c> block: <see cref="Ops"/> is empty in full mode, where the app fetches <see cref="FullUrl"/>.</summary>
public sealed record SyncCatalogBlock(int FromVersion, int ToVersion, string Mode, Uri? FullUrl, IReadOnlyList<CatalogOp> Ops);

/// <summary>Rows actually inserted by this call (valid and not already stored).</summary>
public sealed record SyncAcceptedCounts(int Contributions, int BankRequests);

/// <summary>What the sync decided.</summary>
public abstract record SyncResult;

/// <summary>The install no longer exists (tombstoned between authentication and the sync): <c>401</c>.</summary>
public sealed record SyncInstallGone : SyncResult
{
    public static SyncInstallGone Instance { get; } = new();
}

/// <summary>Inside the window: only the two times (and the nonce echo, added by the API). Nothing was written.</summary>
public sealed record SyncThrottled(DateTimeOffset ServerTime, DateTimeOffset NextSyncNotBefore) : SyncResult;

/// <summary>The full answer. A <c>null</c> block is unchanged for this install.</summary>
public sealed record SyncCompleted(
    DateTimeOffset ServerTime,
    DateTimeOffset NextSyncNotBefore,
    SyncCatalogBlock? Catalog,
    FlagSnapshot? Flags,
    PricesBlock? Prices,
    SyncEntitlementResult Entitlement,
    SyncAcceptedCounts Accepted) : SyncResult
{
    /// <summary>NFR-BE-03: nothing the app must apply (drives the <c>up_to_date</c> tag of the size metric).</summary>
    public bool UpToDate => Catalog is null && Flags is null && Prices is null && Entitlement.Entitlement is null;
}

/// <summary>Settings of the sync (<c>Sync:*</c>).</summary>
/// <param name="ThrottleWindow">At most one effective sync per install per window (<c>Sync:ThrottleWindow</c>, default 24 h).</param>
/// <param name="MaxDeltaOps">A delta with more ops is sent as <c>mode: full</c> instead (<c>Sync:MaxDeltaOps</c>, default 2000).</param>
public sealed record SyncOptions(TimeSpan ThrottleWindow, int MaxDeltaOps)
{
    /// <summary>A client more than this many versions behind gets <c>mode: full</c> (backend-api §4.2).</summary>
    public const int MaxVersionsBehindForDelta = 20;

    public static SyncOptions Default { get; } = new(TimeSpan.FromHours(24), 2000);
}

/// <summary>A normalized contribution that passed every filter, ready to insert.</summary>
public sealed record PreparedContribution(string MerchantNorm, string InstitutionCode, string CategoryCode);

/// <summary>A normalized bank request that passed every filter, ready to insert.</summary>
public sealed record PreparedBankRequest(string InstitutionNameNorm, string Country, string Channel);

/// <summary>
/// The one write of a sync (backend-api §4.2, T-128 design note §3): claim the window, insert the intake, count the install
/// as active today, all in one short transaction.
/// </summary>
/// <param name="InstallHash">HMAC of the install ID; <c>null</c> when there is no intake (or the hasher was down).</param>
public sealed record SyncClaim(
    InstallId InstallId,
    DateTimeOffset Now,
    TimeSpan Window,
    int CatalogVersion,
    string Platform,
    string AppVersion,
    ReadOnlyMemory<byte>? InstallHash,
    IReadOnlyList<PreparedContribution> Contributions,
    IReadOnlyList<PreparedBankRequest> BankRequests);

/// <summary>What the write did. Nothing at all was written when <see cref="Claimed"/> is false.</summary>
public sealed record SyncClaimResult(bool Claimed, int ContributionsInserted, int BankRequestsInserted)
{
    public static SyncClaimResult Lost { get; } = new(false, 0, 0);
}
