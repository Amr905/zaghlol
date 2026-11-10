using System.Globalization;
using System.IO.Compression;
using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using Zaghlol.Application.Audit;
using Zaghlol.Application.Catalog;
using Zaghlol.Infrastructure.Audit;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Catalog;

/// <summary>
/// The draft workspace and publish on the <c>ops_rw</c> login (T-125 design note). Every method is one transaction that first
/// takes <c>pg_advisory_xact_lock</c>, so operators are serialised, and writes its audit row in the same transaction. The audit
/// row names the operator, the action and the path id, never alias text beyond that and never a publish note.
/// </summary>
internal sealed class CatalogAdminStore(
    IZaghlolDbContextFactory contexts,
    ISigner signer,
    ICatalogSnapshotStore snapshots,
    IAuditWriter audit,
    TimeProvider clock) : ICatalogAdminStore
{
    private const long LockKey = 7_125_001;

    public async Task<DraftPage> ListAsync(CatalogEntity entity, int cursor, int limit, CancellationToken cancellationToken)
    {
        var name = CatalogEntities.Name(entity);
        await using var db = Open();
        var rows = await db.CatalogDrafts.AsNoTracking()
            .Where(e => e.Entity == name && !e.Deleted && e.Seq > cursor)
            .OrderBy(e => e.Seq)
            .Take(limit + 1)
            .ToListAsync(cancellationToken);
        var page = rows.Take(limit).ToList();
        var next = rows.Count > limit ? page[^1].Seq.ToString(CultureInfo.InvariantCulture) : null;
        return new DraftPage([.. page.Select(CatalogMapping.FromDraft)], next);
    }

    public async Task<DraftChange> CreateMerchantAsync(Guid operatorId, CatalogFields fields, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(fields);

        await using var db = Open();
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        await LockAsync(db, cancellationToken);

        if (!await IsLiveAsync(db, CatalogEntity.Categories, fields.Category!, cancellationToken)
            || await CanonicalTakenAsync(db, fields.Canonical!, string.Empty, cancellationToken))
        {
            return new DraftChange(DraftStatus.Conflict);
        }

        var id = await AllocateMerchantAsync(db, fields, clock.GetUtcNow(), cancellationToken);
        var key = CatalogKeys.FromStorage(CatalogEntity.Merchants, id.ToString(CultureInfo.InvariantCulture));
        await db.SaveChangesAsync(cancellationToken);
        await AuditAsync(db, operatorId, CatalogDraftAction.Create, key, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new DraftChange(DraftStatus.Ok, new CatalogOp(key, false, fields));
    }

    public async Task<DraftChange> PutAsync(Guid operatorId, CatalogEntryKey key, CatalogFields fields, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(key);
        ArgumentNullException.ThrowIfNull(fields);

        await using var db = Open();
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        await LockAsync(db, cancellationToken);

        var change = await ApplyPutAsync(db, key, fields, cancellationToken);
        if (change.Status != DraftStatus.Ok)
        {
            return change;
        }

        await db.SaveChangesAsync(cancellationToken);
        await AuditAsync(db, operatorId, CatalogDraftAction.Put, key, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return change;
    }

    public async Task<DraftChange> DeleteAsync(Guid operatorId, CatalogEntryKey key, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(key);

        await using var db = Open();
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        await LockAsync(db, cancellationToken);

        var name = CatalogEntities.Name(key.Entity);
        var storageKey = key.StorageKey;
        var existing = await db.CatalogDrafts.SingleOrDefaultAsync(e => e.Entity == name && e.EntryKey == storageKey, cancellationToken);
        if (existing is null || existing.Deleted)
        {
            return new DraftChange(DraftStatus.NotFound);
        }

        var now = clock.GetUtcNow();
        if (key.Entity == CatalogEntity.Categories)
        {
            if (await CategoryInUseAsync(db, storageKey, cancellationToken))
            {
                return new DraftChange(DraftStatus.Conflict);
            }
        }
        else if (key.Entity == CatalogEntity.Merchants)
        {
            // The merchant's aliases go with it (their tombstones sort before the merchant's in a delta).
            var prefix = storageKey + ":";
            var aliases = await db.CatalogDrafts
                .Where(e => e.Entity == "aliases" && !e.Deleted && e.EntryKey.StartsWith(prefix))
                .ToListAsync(cancellationToken);
            foreach (var alias in aliases)
            {
                Tombstone(db, alias, now);
            }
        }

        Tombstone(db, existing, now);
        await db.SaveChangesAsync(cancellationToken);
        await AuditAsync(db, operatorId, CatalogDraftAction.Delete, key, cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new DraftChange(DraftStatus.Ok);
    }

    public async Task<PublishResult> PublishAsync(Guid operatorId, string? note, CancellationToken cancellationToken)
    {
        await using var db = Open();
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        await LockAsync(db, cancellationToken);

        if (!await db.CatalogDrafts.AnyAsync(e => e.Changed, cancellationToken))
        {
            return new PublishResult(true, 0, default, null);
        }

        var version = (await db.CatalogVersions.MaxAsync(v => (int?)v.Version, cancellationToken) ?? 0) + 1;
        var now = clock.GetUtcNow();

        await WriteLiveRowsAsync(db, version, cancellationToken);
        var ops = await ReadLiveAsync(db, cancellationToken);
        var json = CatalogJson.Snapshot(version, ops);
        if (json.Length > CatalogLimits.MaxSnapshotBytes)
        {
            throw new CatalogTooLargeException();
        }

        // Sign the JSON bytes (what the app verifies after gunzip), then store both objects. A KMS or storage failure throws
        // before the commit, so no version exists without its snapshot.
        var signature = await signer.SignAsync(SigningPurpose.Sync, json, cancellationToken);
        var url = await snapshots.PutAsync(version, Compress(json), signature.HeaderValue, cancellationToken);

        db.CatalogVersions.Add(new CatalogVersion
        {
            Version = version,
            PublishedAt = now,
            PublishedBy = operatorId,
            Notes = note,
            FullSnapshotUrl = url,
            FullSnapshotSha256 = SHA256.HashData(json),
        });
        await db.SaveChangesAsync(cancellationToken);
        await audit.WriteAsync(db, operatorId, new CatalogPublishAudit(version, ops.Count), cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return new PublishResult(false, version, now, url);
    }

    public async Task<SeedImportResult> ImportSeedAsync(Guid operatorId, CatalogSeed seed, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(seed);

        await using var db = Open();
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        await LockAsync(db, cancellationToken);

        var aliasCount = 0;
        foreach (var category in seed.Categories)
        {
            await SeedPutAsync(db, CatalogEntity.Categories, category.Code, category.Fields, cancellationToken);
        }

        foreach (var merchant in seed.Merchants)
        {
            var id = await SeedMerchantAsync(db, merchant.Fields, cancellationToken);
            foreach (var alias in merchant.Aliases)
            {
                await SeedPutAsync(
                    db,
                    CatalogEntity.Aliases,
                    CatalogKeys.AliasPathId(id, alias.Alias),
                    new CatalogFields { Match = alias.Match },
                    cancellationToken);
                aliasCount++;
            }
        }

        foreach (var keyword in seed.Keywords)
        {
            await SeedPutAsync(
                db,
                CatalogEntity.Keywords,
                CatalogKeys.KeywordPathId(keyword.Lang, keyword.Keyword),
                keyword.Fields,
                cancellationToken);
        }

        var result = new SeedImportResult(seed.Categories.Count, seed.Merchants.Count, aliasCount, seed.Keywords.Count);
        await db.SaveChangesAsync(cancellationToken);
        await audit.WriteAsync(
            db,
            operatorId,
            new CatalogSeedImportAudit(result.Categories, result.Merchants, result.Aliases, result.Keywords),
            cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return result;
    }

    private static CatalogSeedFormatException BadSeedRow() =>
        new("A seed row is invalid or conflicts with the draft catalog.");

    private static Task<int> LockAsync(ZaghlolDbContext db, CancellationToken cancellationToken) =>
        db.Database.ExecuteSqlAsync($"SELECT pg_advisory_xact_lock({LockKey})", cancellationToken);

    private static Task<bool> IsLiveAsync(ZaghlolDbContext db, CatalogEntity entity, string storageKey, CancellationToken cancellationToken)
    {
        var name = CatalogEntities.Name(entity);
        return db.CatalogDrafts.AsNoTracking().AnyAsync(e => e.Entity == name && e.EntryKey == storageKey && !e.Deleted, cancellationToken);
    }

    /// <summary>True when another draft merchant (any state, as the live table's unique index sees it) has this canonical name.</summary>
    private static Task<bool> CanonicalTakenAsync(ZaghlolDbContext db, string canonical, string exceptKey, CancellationToken cancellationToken) =>
        db.CatalogDrafts
            .FromSql($"SELECT * FROM zaghlol.catalog_drafts WHERE entity = 'merchants' AND body ->> 'canonical' = {canonical} AND entry_key <> {exceptKey}")
            .AsNoTracking()
            .AnyAsync(cancellationToken);

    private static Task<bool> CategoryInUseAsync(ZaghlolDbContext db, string code, CancellationToken cancellationToken) =>
        db.CatalogDrafts
            .FromSql($"SELECT * FROM zaghlol.catalog_drafts WHERE entity IN ('merchants', 'keywords') AND NOT deleted AND body ->> 'category' = {code}")
            .AsNoTracking()
            .AnyAsync(cancellationToken);

    /// <summary>Adds the row, then renames its key to its own identity value: the allocated, never reused merchant id.</summary>
    private static async Task<int> AllocateMerchantAsync(ZaghlolDbContext db, CatalogFields fields, DateTimeOffset now, CancellationToken cancellationToken)
    {
        var entry = new CatalogDraftEntry
        {
            Entity = "merchants",
            EntryKey = Guid.NewGuid().ToString("N"),
            Body = fields.ToJson(),
            Deleted = false,
            Published = false,
            Changed = true,
            UpdatedAt = now,
        };
        db.CatalogDrafts.Add(entry);
        await db.SaveChangesAsync(cancellationToken);

        var seq = entry.Seq;
        var id = seq.ToString(CultureInfo.InvariantCulture);
        await db.CatalogDrafts.Where(e => e.Seq == seq).ExecuteUpdateAsync(s => s.SetProperty(e => e.EntryKey, id), cancellationToken);
        db.Entry(entry).State = EntityState.Detached;
        return seq;
    }

    private async Task<DraftChange> ApplyPutAsync(ZaghlolDbContext db, CatalogEntryKey key, CatalogFields fields, CancellationToken cancellationToken)
    {
        var name = CatalogEntities.Name(key.Entity);
        var storageKey = key.StorageKey;
        var existing = await db.CatalogDrafts.SingleOrDefaultAsync(e => e.Entity == name && e.EntryKey == storageKey, cancellationToken);
        if (key.Entity == CatalogEntity.Merchants && existing is null)
        {
            return new DraftChange(DraftStatus.NotFound);
        }

        var referencesAreLive = key.Entity switch
        {
            CatalogEntity.Merchants or CatalogEntity.Keywords =>
                await IsLiveAsync(db, CatalogEntity.Categories, fields.Category!, cancellationToken),
            CatalogEntity.Aliases =>
                await IsLiveAsync(db, CatalogEntity.Merchants, key.MerchantId.ToString(CultureInfo.InvariantCulture), cancellationToken),
            _ => true,
        };
        if (!referencesAreLive
            || (key.Entity == CatalogEntity.Merchants && await CanonicalTakenAsync(db, fields.Canonical!, storageKey, cancellationToken)))
        {
            return new DraftChange(DraftStatus.Conflict);
        }

        var now = clock.GetUtcNow();
        var json = fields.ToJson();
        if (existing is null)
        {
            db.CatalogDrafts.Add(new CatalogDraftEntry
            {
                Entity = name,
                EntryKey = storageKey,
                Body = json,
                Deleted = false,
                Published = false,
                Changed = true,
                UpdatedAt = now,
            });
        }
        else if (existing.Deleted || CatalogFields.FromJson(existing.Body) != fields)
        {
            existing.Body = json;
            existing.Deleted = false;
            existing.Changed = true;
            existing.UpdatedAt = now;
        }

        await db.SaveChangesAsync(cancellationToken);

        // A seed import calls this thousands of times in one context; keep change detection cheap.
        db.ChangeTracker.Clear();
        return new DraftChange(DraftStatus.Ok, new CatalogOp(key, false, fields));
    }

    /// <summary>A published entry becomes a tombstone for the next publish; a never-published one is removed outright.</summary>
    private static void Tombstone(ZaghlolDbContext db, CatalogDraftEntry row, DateTimeOffset now)
    {
        if (row.Published)
        {
            row.Deleted = true;
            row.Changed = true;
            row.UpdatedAt = now;
        }
        else
        {
            db.CatalogDrafts.Remove(row);
        }
    }

    /// <summary>The draft edit's audit row, in the edit's transaction (the shared writer, T-136).</summary>
    private Task<long> AuditAsync(ZaghlolDbContext db, Guid operatorId, CatalogDraftAction kind, CatalogEntryKey key, CancellationToken cancellationToken) =>
        audit.WriteAsync(db, operatorId, new CatalogDraftAudit(kind, CatalogEntities.Name(key.Entity), key.PathId), cancellationToken);

    private async Task SeedPutAsync(ZaghlolDbContext db, CatalogEntity entity, string pathId, CatalogFields fields, CancellationToken cancellationToken)
    {
        if (!CatalogKeys.TryParse(entity, pathId, out var key) || !CatalogValidation.IsValid(entity, fields))
        {
            throw BadSeedRow();
        }

        var change = await ApplyPutAsync(db, key, fields, cancellationToken);
        if (change.Status != DraftStatus.Ok)
        {
            throw BadSeedRow();
        }
    }

    /// <summary>The id of the draft merchant with this canonical name (replaced), or of a newly allocated one.</summary>
    private async Task<int> SeedMerchantAsync(ZaghlolDbContext db, CatalogFields fields, CancellationToken cancellationToken)
    {
        if (!CatalogValidation.IsValid(CatalogEntity.Merchants, fields))
        {
            throw BadSeedRow();
        }

        var canonical = fields.Canonical!;
        var existingKey = await db.CatalogDrafts
            .FromSql($"SELECT * FROM zaghlol.catalog_drafts WHERE entity = 'merchants' AND body ->> 'canonical' = {canonical}")
            .AsNoTracking()
            .Select(e => e.EntryKey)
            .FirstOrDefaultAsync(cancellationToken);
        if (existingKey is not null)
        {
            await SeedPutAsync(db, CatalogEntity.Merchants, existingKey, fields, cancellationToken);
            return int.Parse(existingKey, CultureInfo.InvariantCulture);
        }

        if (!await IsLiveAsync(db, CatalogEntity.Categories, fields.Category!, cancellationToken))
        {
            throw BadSeedRow();
        }

        return await AllocateMerchantAsync(db, fields, clock.GetUtcNow(), cancellationToken);
    }

    /// <summary>
    /// Copies every changed draft entry into the live tables with the new version, set-based. Parents first (the foreign keys),
    /// then marks the drafts as published and unchanged. Merchant ids are written as given (<c>OVERRIDING SYSTEM VALUE</c>):
    /// the draft identity allocated them.
    /// </summary>
    private static async Task WriteLiveRowsAsync(ZaghlolDbContext db, int version, CancellationToken cancellationToken)
    {
        await db.Database.ExecuteSqlAsync(
            $"""
            INSERT INTO zaghlol.catalog_categories (code, parent_code, name_ar, name_en, icon, color, bucket, sort, version, deleted)
            SELECT d.entry_key, NULL, d.body ->> 'nameAr', d.body ->> 'nameEn', d.body ->> 'icon', d.body ->> 'color',
                   d.body ->> 'bucket', (d.body ->> 'sort')::integer, {version}, d.deleted
            FROM zaghlol.catalog_drafts d WHERE d.entity = 'categories' AND d.changed
            ON CONFLICT (code) DO UPDATE SET name_ar = EXCLUDED.name_ar, name_en = EXCLUDED.name_en, icon = EXCLUDED.icon,
                color = EXCLUDED.color, bucket = EXCLUDED.bucket, sort = EXCLUDED.sort, version = EXCLUDED.version,
                deleted = EXCLUDED.deleted
            """,
            cancellationToken);
        await db.Database.ExecuteSqlAsync(
            $"""
            INSERT INTO zaghlol.catalog_merchants (id, canonical, name_ar, name_en, category_code, version, deleted)
            OVERRIDING SYSTEM VALUE
            SELECT d.entry_key::integer, d.body ->> 'canonical', d.body ->> 'nameAr', NULL, d.body ->> 'category', {version}, d.deleted
            FROM zaghlol.catalog_drafts d WHERE d.entity = 'merchants' AND d.changed
            ON CONFLICT (id) DO UPDATE SET canonical = EXCLUDED.canonical, name_ar = EXCLUDED.name_ar,
                category_code = EXCLUDED.category_code, version = EXCLUDED.version, deleted = EXCLUDED.deleted
            """,
            cancellationToken);
        await db.Database.ExecuteSqlAsync(
            $"""
            INSERT INTO zaghlol.catalog_aliases (merchant_id, alias_norm, match, version, deleted)
            SELECT split_part(d.entry_key, ':', 1)::integer, substr(d.entry_key, position(':' in d.entry_key) + 1),
                   d.body ->> 'match', {version}, d.deleted
            FROM zaghlol.catalog_drafts d WHERE d.entity = 'aliases' AND d.changed
            ON CONFLICT (alias_norm, merchant_id) DO UPDATE SET match = EXCLUDED.match, version = EXCLUDED.version,
                deleted = EXCLUDED.deleted
            """,
            cancellationToken);
        await db.Database.ExecuteSqlAsync(
            $"""
            INSERT INTO zaghlol.catalog_keywords (keyword_norm, lang, category_code, weight, version, deleted)
            SELECT substr(d.entry_key, position(':' in d.entry_key) + 1), split_part(d.entry_key, ':', 1),
                   d.body ->> 'category', (d.body ->> 'weight')::integer, {version}, d.deleted
            FROM zaghlol.catalog_drafts d WHERE d.entity = 'keywords' AND d.changed
            ON CONFLICT (keyword_norm, lang) DO UPDATE SET category_code = EXCLUDED.category_code, weight = EXCLUDED.weight,
                version = EXCLUDED.version, deleted = EXCLUDED.deleted
            """,
            cancellationToken);
        await db.Database.ExecuteSqlAsync(
            $"UPDATE zaghlol.catalog_drafts SET changed = false, published = true WHERE changed",
            cancellationToken);
    }

    /// <summary>The live (not tombstoned) catalog as upserts, in the deterministic snapshot order.</summary>
    private static async Task<IReadOnlyList<CatalogOp>> ReadLiveAsync(ZaghlolDbContext db, CancellationToken cancellationToken)
    {
        var ops = new List<CatalogOp>();
        ops.AddRange((await db.CatalogCategories.AsNoTracking().Where(c => !c.Deleted).ToListAsync(cancellationToken))
            .Select(CatalogMapping.FromCategory));
        ops.AddRange((await db.CatalogMerchants.AsNoTracking().Where(m => !m.Deleted).ToListAsync(cancellationToken))
            .Select(CatalogMapping.FromMerchant));
        ops.AddRange((await db.CatalogAliases.AsNoTracking().Where(a => !a.Deleted).ToListAsync(cancellationToken))
            .Select(CatalogMapping.FromAlias));
        ops.AddRange((await db.CatalogKeywords.AsNoTracking().Where(k => !k.Deleted).ToListAsync(cancellationToken))
            .Select(CatalogMapping.FromKeyword));
        return CatalogDeltaOrder.Order(ops);
    }

    private static byte[] Compress(byte[] json)
    {
        using var output = new MemoryStream();
        using (var gzip = new GZipStream(output, CompressionLevel.SmallestSize, leaveOpen: true))
        {
            gzip.Write(json);
        }

        return output.ToArray();
    }

    private ZaghlolDbContext Open() => contexts.CreateDbContext(DatabaseRole.Admin);
}
