using Zaghlol.Domain;

namespace Zaghlol.Application.Catalog;

/// <summary>A published catalog version (<c>catalog_versions</c>).</summary>
/// <param name="Version">The immutable version number.</param>
/// <param name="PublishedAt">When it was published.</param>
/// <param name="Sha256">SHA-256 of the uncompressed snapshot JSON, which is also what the signature covers.</param>
/// <param name="SnapshotUrl">Where the full snapshot is served from.</param>
public sealed record CatalogVersionInfo(int Version, DateTimeOffset PublishedAt, ReadOnlyMemory<byte> Sha256, Uri SnapshotUrl);

/// <summary>Read side of the published catalog, on the public <c>/v1</c> database login.</summary>
public interface ICatalogReader
{
    /// <summary>The published version, or <c>null</c> when there is none with that number.</summary>
    Task<CatalogVersionInfo?> FindVersionAsync(int version, CancellationToken cancellationToken);

    /// <summary>The newest published version, or 0 before the first publish.</summary>
    Task<int> LatestVersionAsync(CancellationToken cancellationToken);

    /// <summary>
    /// The delta <c>(fromVersion, toVersion]</c>: every entry whose version is in that range, tombstones included, in
    /// <see cref="CatalogDeltaOrder"/>. Empty when <paramref name="fromVersion"/> is not below <paramref name="toVersion"/>
    /// (an up-to-date client).
    /// </summary>
    Task<IReadOnlyList<CatalogOp>> DeltaAsync(int fromVersion, int toVersion, CancellationToken cancellationToken);
}

/// <summary>
/// Object storage for the immutable full snapshots (<c>full.json.gz</c> and the <c>full.json.sig</c> next to it). The shipped
/// adapter writes to a directory; a CDN or bucket adapter is deployment work (T-140).
/// </summary>
public interface ICatalogSnapshotStore
{
    /// <summary>Stores the gzip of the snapshot JSON and the <c>Zaghlol-Signature</c> header value over the JSON; returns its URL.</summary>
    Task<Uri> PutAsync(int version, ReadOnlyMemory<byte> gzipJson, string signature, CancellationToken cancellationToken);

    /// <summary>The stored gzip, or <c>null</c> when this version has no stored snapshot.</summary>
    Task<byte[]?> GetAsync(int version, CancellationToken cancellationToken);
}

public enum DraftStatus
{
    /// <summary>Done.</summary>
    Ok,

    /// <summary>Missing or already deleted key (404).</summary>
    NotFound,

    /// <summary>The change conflicts with the draft (409 ADMIN_CONFLICT).</summary>
    Conflict,
}

/// <summary>The outcome of a draft write; <see cref="Op"/> is the stored entry for create and put.</summary>
public sealed record DraftChange(DraftStatus Status, CatalogOp? Op = null);

/// <summary>One page of draft entries; <see cref="NextCursor"/> is <c>null</c> on the last page.</summary>
public sealed record DraftPage(IReadOnlyList<CatalogOp> Items, string? NextCursor);

/// <summary>The outcome of a publish. <see cref="NothingToPublish"/> means no entry changed since the last publish (409).</summary>
public sealed record PublishResult(bool NothingToPublish, int Version, DateTimeOffset PublishedAt, Uri? SnapshotUrl);

/// <summary>What a seed import wrote into the draft.</summary>
public sealed record SeedImportResult(int Categories, int Merchants, int Aliases, int Keywords);

/// <summary>
/// The operator side of the catalog (admin database login). Every write is audited in its own transaction with the operator
/// named, and runs under one lock, so operators are serialised.
/// </summary>
public interface ICatalogAdminStore
{
    /// <summary>Live (not tombstoned) draft entries of one kind in creation order; <paramref name="cursor"/> 0 starts at the top.</summary>
    Task<DraftPage> ListAsync(CatalogEntity entity, int cursor, int limit, CancellationToken cancellationToken);

    /// <summary>Allocates a merchant id (never reused) and stores the draft merchant; <see cref="DraftStatus.Conflict"/> when the category or canonical name clashes.</summary>
    Task<DraftChange> CreateMerchantAsync(Guid operatorId, CatalogFields fields, CancellationToken cancellationToken);

    /// <summary>Creates or replaces an entry, or revives a tombstone. Merchants must exist (<see cref="DraftStatus.NotFound"/>).</summary>
    Task<DraftChange> PutAsync(Guid operatorId, CatalogEntryKey key, CatalogFields fields, CancellationToken cancellationToken);

    /// <summary>Tombstones an entry (removes it when it was never published); a merchant also tombstones its aliases.</summary>
    Task<DraftChange> DeleteAsync(Guid operatorId, CatalogEntryKey key, CancellationToken cancellationToken);

    /// <summary>Publishes the draft as the next immutable version: live rows, signed snapshot, stored objects, one audit row.</summary>
    Task<PublishResult> PublishAsync(Guid operatorId, string? note, CancellationToken cancellationToken);

    /// <summary>Loads a seed into the draft in one transaction with one audit row. Does not publish.</summary>
    Task<SeedImportResult> ImportSeedAsync(Guid operatorId, CatalogSeed seed, CancellationToken cancellationToken);
}

/// <summary>Size limits of the catalog.</summary>
public static class CatalogLimits
{
    /// <summary>
    /// The largest full snapshot (uncompressed JSON) the backend publishes or serves. A 10 000-op catalog is about 1 MB, so this
    /// leaves room for growth; the signing buffer of <c>GET /v1/catalog/{version}/full</c> is sized to it (T-123 I-5).
    /// </summary>
    public const int MaxSnapshotBytes = 8 * 1024 * 1024;
}

/// <summary>The catalog is too large to publish as one snapshot. Constant message.</summary>
public sealed class CatalogTooLargeException : SafeException
{
    public const string DefaultMessage = "The full catalog snapshot exceeds the size limit.";

    public CatalogTooLargeException()
        : base(DefaultMessage)
    {
    }

    public CatalogTooLargeException(string message)
        : base(message)
    {
    }

    public CatalogTooLargeException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>A published version's stored snapshot is missing or does not match its recorded hash. Constant message.</summary>
public sealed class CatalogSnapshotCorruptException : SafeException
{
    public const string DefaultMessage = "The stored catalog snapshot is missing or does not match its recorded hash.";

    public CatalogSnapshotCorruptException()
        : base(DefaultMessage)
    {
    }

    public CatalogSnapshotCorruptException(string message)
        : base(message)
    {
    }

    public CatalogSnapshotCorruptException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
