using Zaghlol.Application.Flags;
using Zaghlol.Application.Prices;

namespace Zaghlol.Application.Sync;

/// <summary>Pure block rules of the sync (T-128 design note §1). No I/O, no clock.</summary>
public static class SyncComposer
{
    /// <summary>
    /// Which catalog answer a client at <paramref name="clientVersion"/> gets when <paramref name="latest"/> is published:
    /// <see cref="CatalogModes.None"/> when it is current or nothing is published; <see cref="CatalogModes.Full"/> when it has
    /// nothing (0), is ahead of this server, or is more than <see cref="SyncOptions.MaxVersionsBehindForDelta"/> behind;
    /// otherwise <see cref="CatalogModes.Delta"/> (which still becomes full when the delta is too large, <see cref="DeltaTooLarge"/>).
    /// </summary>
    public static string CatalogMode(int clientVersion, int latest)
    {
        if (latest <= 0 || clientVersion == latest)
        {
            return CatalogModes.None;
        }

        if (clientVersion <= 0 || clientVersion > latest || latest - clientVersion > SyncOptions.MaxVersionsBehindForDelta)
        {
            return CatalogModes.Full;
        }

        return CatalogModes.Delta;
    }

    /// <summary>A delta with more ops than <paramref name="maxOps"/> is sent as full mode, which keeps the body bounded.</summary>
    public static bool DeltaTooLarge(int opCount, int maxOps) => opCount > maxOps;

    /// <summary>
    /// The flags block is sent when the snapshot version differs from the client's, or when the app version in this request
    /// differs from the one stored before it (an update can flip a <c>minAppVersion</c> rule without any flag version change).
    /// </summary>
    public static bool SendFlags(FlagSnapshot snapshot, int clientFlagsVersion, string requestAppVersion, string storedAppVersion)
    {
        ArgumentNullException.ThrowIfNull(snapshot);

        return snapshot.Version != clientFlagsVersion || !string.Equals(requestAppVersion, storedAppVersion, StringComparison.Ordinal);
    }

    /// <summary>
    /// The prices block is sent when there is one and its <c>asOf</c> differs from the client's. Both are compared at whole
    /// seconds, the precision of the wire timestamp the client echoes back.
    /// </summary>
    public static bool SendPrices(PricesBlock? block, DateTimeOffset? clientAsOf) =>
        block is not null && (clientAsOf is not { } client || WholeSecond(block.AsOf) != WholeSecond(client));

    /// <summary>True when a sync is allowed now: never synced, or the window since the last effective sync has passed.</summary>
    public static bool ThrottleAllows(DateTimeOffset? lastSyncAt, DateTimeOffset now, TimeSpan window) =>
        lastSyncAt is not { } last || now >= last + window;

    /// <summary>The instant truncated to a whole second, in UTC (the wire precision of <c>UtcTimestamp</c>).</summary>
    public static DateTimeOffset WholeSecond(DateTimeOffset value)
    {
        var utc = value.ToUniversalTime();
        return new DateTimeOffset(utc.Ticks - (utc.Ticks % TimeSpan.TicksPerSecond), TimeSpan.Zero);
    }
}
