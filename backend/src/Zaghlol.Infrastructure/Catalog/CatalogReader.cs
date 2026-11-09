using Microsoft.EntityFrameworkCore;
using Zaghlol.Application.Catalog;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Catalog;

/// <summary>The published catalog on the <c>app_rw</c> login (read only).</summary>
internal sealed class CatalogReader(IAppDbContextFactory contexts) : ICatalogReader
{
    public async Task<CatalogVersionInfo?> FindVersionAsync(int version, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext();
        var row = await db.CatalogVersions.AsNoTracking()
            .Where(v => v.Version == version)
            .SingleOrDefaultAsync(cancellationToken);
        return row is null ? null : new CatalogVersionInfo(row.Version, row.PublishedAt, row.FullSnapshotSha256, row.FullSnapshotUrl);
    }

    public async Task<int> LatestVersionAsync(CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext();
        return await db.CatalogVersions.MaxAsync(v => (int?)v.Version, cancellationToken) ?? 0;
    }

    public async Task<IReadOnlyList<CatalogOp>> DeltaAsync(int fromVersion, int toVersion, CancellationToken cancellationToken)
    {
        if (fromVersion >= toVersion)
        {
            return [];
        }

        await using var db = contexts.CreateDbContext();
        var ops = new List<CatalogOp>();
        ops.AddRange((await db.CatalogCategories.AsNoTracking()
            .Where(c => c.Version > fromVersion && c.Version <= toVersion)
            .ToListAsync(cancellationToken)).Select(CatalogMapping.FromCategory));
        ops.AddRange((await db.CatalogMerchants.AsNoTracking()
            .Where(m => m.Version > fromVersion && m.Version <= toVersion)
            .ToListAsync(cancellationToken)).Select(CatalogMapping.FromMerchant));
        ops.AddRange((await db.CatalogAliases.AsNoTracking()
            .Where(a => a.Version > fromVersion && a.Version <= toVersion)
            .ToListAsync(cancellationToken)).Select(CatalogMapping.FromAlias));
        ops.AddRange((await db.CatalogKeywords.AsNoTracking()
            .Where(k => k.Version > fromVersion && k.Version <= toVersion)
            .ToListAsync(cancellationToken)).Select(CatalogMapping.FromKeyword));
        return CatalogDeltaOrder.Order(ops);
    }
}
