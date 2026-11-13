using Zaghlol.Domain;

namespace Zaghlol.Application.Sync;

/// <summary>The <c>installs</c> reads and the single write transaction of a sync, on the App login.</summary>
public interface ISyncStore
{
    /// <summary>The live install (one indexed read, the throttle fast path), or <c>null</c> when missing or tombstoned.</summary>
    Task<SyncInstall?> FindInstallAsync(InstallId installId, CancellationToken cancellationToken);

    /// <summary>
    /// One READ COMMITTED transaction: the conditional claim <c>UPDATE installs ... WHERE last_sync_at IS NULL OR
    /// last_sync_at &lt;= now - window</c>; when it hits the row, the contribution and bank-request inserts
    /// (<c>ON CONFLICT DO NOTHING</c>) and the <c>daily_active_counts</c> upsert. When it hits nothing (a concurrent call won,
    /// or the install was deleted) nothing is written and <see cref="SyncClaimResult.Lost"/> is returned.
    /// </summary>
    Task<SyncClaimResult> ClaimAsync(SyncClaim claim, CancellationToken cancellationToken);
}

/// <summary>
/// <c>install_hash</c> for the contribution tables: an HMAC of the install ID under the KMS pepper (<c>IKeyedHasher</c>), so
/// rows count distinct installs without being joinable back to <c>installs</c>. Throws when the KMS is unavailable.
/// </summary>
public interface IInstallHasher
{
    ValueTask<byte[]> HashAsync(InstallId installId, CancellationToken cancellationToken);
}

/// <summary>What <see cref="ISyncEntitlementBlock"/> is told about the call.</summary>
/// <param name="EntitlementIssuedAt">The request's <c>entitlementIssuedAt</c>, unchanged (T-132: the R5-7 delivery proof).</param>
/// <param name="AccountToken">The <c>Zaghlol-Account</c> header, unverified (T-132 validates it); never logged.</param>
public sealed record SyncEntitlementContext(InstallId InstallId, DateTimeOffset? EntitlementIssuedAt, DateTimeOffset Now, Sensitive<string>? AccountToken = null);

/// <summary>The <c>entitlement</c>, <c>accountToken</c> and <c>supportNotice</c> blocks; <c>null</c> members are unchanged.</summary>
/// <param name="Entitlement">A signed entitlement JWS (sent as <c>{"token": ...}</c>).</param>
/// <param name="AccountToken">A refreshed account token JWS.</param>
/// <param name="SupportNotice"><c>gold_linked_by_support</c> or <c>null</c> (R4-7(2)).</param>
public sealed record SyncEntitlementResult(string? Entitlement, string? AccountToken, string? SupportNotice)
{
    public static SyncEntitlementResult None { get; } = new(null, null, null);
}

/// <summary>
/// The extension point T-132 fills (entitlement, account token, support notice). Called after the throttle pre-check passed
/// and before the write transaction, outside any transaction of the sync. Its side effects must be idempotent: if the claim
/// then loses a race the response becomes the throttle answer. An exception from it fails the call with <c>503</c> before
/// anything of the sync is written.
/// </summary>
public interface ISyncEntitlementBlock
{
    Task<SyncEntitlementResult> ComposeAsync(SyncEntitlementContext context, CancellationToken cancellationToken);
}

/// <summary>The T-128 default: every block <c>null</c> until T-132 lands.</summary>
public sealed class NullSyncEntitlementBlock : ISyncEntitlementBlock
{
    public Task<SyncEntitlementResult> ComposeAsync(SyncEntitlementContext context, CancellationToken cancellationToken) =>
        Task.FromResult(SyncEntitlementResult.None);
}

/// <summary>Metric tag values of the sync (fixed sets; no install ID, no merchant or institution text ever).</summary>
public static class SyncTags
{
    public const string Ok = "ok";
    public const string Throttled = "throttled";
    public const string Rejected = "rejected";

    /// <summary>A 503: a required source or the database failed before anything was written (FU-061).</summary>
    public const string Unavailable = "unavailable";

    /// <summary>Why a sync was <see cref="Unavailable"/>: a required block (catalog, flags, entitlement) or the database.</summary>
    public const string CauseSource = "source";
    public const string CauseDatabase = "database";

    public const string Contribution = "contribution";
    public const string BankRequest = "bank_request";

    public const string Accepted = "accepted";
    public const string Filtered = "filtered";
    public const string InvalidCode = "invalid_code";
    public const string Duplicate = "duplicate";
    public const string DroppedHasher = "dropped_hasher";

    public const string CatalogBlock = "catalog";
    public const string FlagsBlock = "flags";
    public const string PricesBlock = "prices";
    public const string EntitlementBlock = "entitlement";

    public static IReadOnlyList<string> Outcomes { get; } = [Ok, Throttled, Rejected, Unavailable];

    public static IReadOnlyList<string> CatalogModeValues { get; } = [CatalogModes.None, CatalogModes.Delta, CatalogModes.Full];

    public static IReadOnlyList<string> IntakeKinds { get; } = [Contribution, BankRequest];

    public static IReadOnlyList<string> IntakeResults { get; } = [Accepted, Filtered, InvalidCode, Duplicate, DroppedHasher];

    public static IReadOnlyList<string> Blocks { get; } = [CatalogBlock, FlagsBlock, PricesBlock, EntitlementBlock];
}

/// <summary>
/// Metrics and fixed-code log events of the sync, implemented by the API (Zaghlol meter, structured logs). Arguments are
/// always values of <see cref="SyncTags"/> or a known flag key, never request data.
/// </summary>
public interface ISyncTelemetry
{
    void Request(string outcome);

    void Catalog(string mode);

    void Intake(string kind, string result, int count);

    /// <param name="block">A value of <see cref="SyncTags.Blocks"/>.</param>
    /// <param name="cause">The exception type name only (never its message), for the log.</param>
    void BlockFailed(string block, string cause);

    /// <summary>A 503: counted as outcome <see cref="SyncTags.Unavailable"/> and logged with a fixed <see cref="SyncTags.CauseSource"/> or <see cref="SyncTags.CauseDatabase"/>.</summary>
    void Unavailable(string cause);

    void FlagRulesInvalid(string flag);

    void InstallHashUnavailable();
}

/// <summary>
/// A source the full answer can't do without (catalog, flags, entitlement) failed: <c>503 UPSTREAM_UNAVAILABLE</c>, nothing
/// written, the window not consumed. Constant message; the block is a fixed tag.
/// </summary>
public sealed class SyncSourceUnavailableException : SafeException
{
    public const string DefaultMessage = "A sync source is unavailable.";

    public SyncSourceUnavailableException()
        : base(DefaultMessage)
    {
    }

    public SyncSourceUnavailableException(string message)
        : base(message)
    {
    }

    public SyncSourceUnavailableException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
