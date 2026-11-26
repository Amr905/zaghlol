using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Llm.Categorise;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Llm.Categorise;

/// <summary>
/// <c>llm_cat_answer_cache</c> on the App login (llm-categorise §4). Raw SQL, parameters only. The rows hold the merchant_norm, the code, the confidence,
/// the provider and prompt ids and times; there is no column for an install, account, IP or app version, and none is ever joined to it.
/// </summary>
internal sealed class CategoriseAnswerCacheRepository([FromKeyedServices(DatabaseRole.App)] NpgsqlDataSource source) : ICategoriseAnswerCache
{
    private const string HitSql = """
        UPDATE zaghlol.llm_cat_answer_cache SET hits = hits + 1
        WHERE merchant_norm = ANY(@keys) AND expires_at > @now
        RETURNING merchant_norm, category_code, confidence
        """;

    private const string UpsertSql = """
        INSERT INTO zaghlol.llm_cat_answer_cache (merchant_norm, category_code, confidence, provider_id, prompt_version, created_at, expires_at, hits)
        VALUES (@key, @code, @p, @provider, @prompt, @now, @expires, 0)
        ON CONFLICT (merchant_norm) DO UPDATE
          SET category_code = EXCLUDED.category_code, confidence = EXCLUDED.confidence, provider_id = EXCLUDED.provider_id,
              prompt_version = EXCLUDED.prompt_version, created_at = EXCLUDED.created_at, expires_at = EXCLUDED.expires_at
        """;

    public async Task<IReadOnlyDictionary<string, CachedAnswer>> GetAsync(IReadOnlyList<string> keys, DateTimeOffset now, CancellationToken cancellationToken)
    {
        var found = new Dictionary<string, CachedAnswer>(StringComparer.Ordinal);
        await using var command = source.CreateCommand(HitSql);
        command.Parameters.Add(new("keys", NpgsqlDbType.Array | NpgsqlDbType.Text) { Value = keys.ToArray() });
        command.Parameters.Add(new("now", NpgsqlDbType.TimestampTz) { Value = now.ToUniversalTime() });
        await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
        while (await reader.ReadAsync(cancellationToken).ConfigureAwait(false))
        {
            found[reader.GetString(0)] = new CachedAnswer(reader.GetString(1), reader.GetInt16(2));
        }

        return found;
    }

    public async Task PutAsync(IReadOnlyList<CacheWrite> rows, DateTimeOffset now, CancellationToken cancellationToken)
    {
        foreach (var row in rows)
        {
            await using var command = source.CreateCommand(UpsertSql);
            command.Parameters.Add(new("key", NpgsqlDbType.Text) { Value = row.Key });
            command.Parameters.Add(new("code", NpgsqlDbType.Text) { Value = row.Category });
            command.Parameters.Add(new("p", NpgsqlDbType.Smallint) { Value = (short)row.Confidence });
            command.Parameters.Add(new("provider", NpgsqlDbType.Text) { Value = row.ProviderId });
            command.Parameters.Add(new("prompt", NpgsqlDbType.Text) { Value = row.PromptVersion });
            command.Parameters.Add(new("now", NpgsqlDbType.TimestampTz) { Value = now.ToUniversalTime() });
            command.Parameters.Add(new("expires", NpgsqlDbType.TimestampTz) { Value = (now + CategoriseCacheDefaults.Lifetime).ToUniversalTime() });
            await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
        }
    }
}

/// <summary>
/// The published catalog for categorise on the App login (read only): the live top-level category codes and the alias index, rebuilt when the newest
/// published version changes. The version is rechecked at most every <see cref="Recheck"/> (one <c>MAX</c> query), so a publish reaches this endpoint
/// within a minute, and a database fault on a recheck keeps the last snapshot (it is only a free-answer shortcut).
/// </summary>
internal sealed class CategoriseCatalogSource(IAppDbContextFactory contexts, TimeProvider clock) : ICategoriseCatalog, IDisposable
{
    public static readonly TimeSpan Recheck = TimeSpan.FromSeconds(60);

    private readonly SemaphoreSlim gate = new(1, 1);
    private CategoriseCatalog? current;
    private DateTimeOffset checkedAt;

    public async Task<CategoriseCatalog> GetAsync(CancellationToken cancellationToken)
    {
        var snapshot = current;
        if (snapshot is not null && clock.GetUtcNow() - checkedAt < Recheck)
        {
            return snapshot;
        }

        await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (current is not null && clock.GetUtcNow() - checkedAt < Recheck)
            {
                return current;
            }

            try
            {
                await ReloadAsync(cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
#pragma warning disable CA1031 // A failed recheck keeps the last snapshot (only a free-answer shortcut); with none, the fault reaches the caller, which pauses.
            catch (Exception) when (current is not null)
#pragma warning restore CA1031
            {
                checkedAt = clock.GetUtcNow();
            }

            return current!;
        }
        finally
        {
            gate.Release();
        }
    }

    private async Task ReloadAsync(CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext();
        var version = await db.CatalogVersions.AsNoTracking().MaxAsync(v => (int?)v.Version, cancellationToken).ConfigureAwait(false) ?? 0;
        if (current is null || current.Version != version)
        {
            var codes = await db.CatalogCategories.AsNoTracking()
                .Where(c => !c.Deleted && c.ParentCode == null)
                .OrderBy(c => c.Sort).ThenBy(c => c.Code)
                .Select(c => c.Code)
                .ToListAsync(cancellationToken).ConfigureAwait(false);
            var merchants = await db.CatalogMerchants.AsNoTracking()
                .Where(m => !m.Deleted)
                .ToDictionaryAsync(m => m.Id, m => m.CategoryCode, cancellationToken).ConfigureAwait(false);
            var aliases = await db.CatalogAliases.AsNoTracking()
                .Where(a => !a.Deleted)
                .Select(a => new CatalogAliasEntry(a.MerchantId, a.AliasNorm, a.Match))
                .ToListAsync(cancellationToken).ConfigureAwait(false);
            current = new CategoriseCatalog(version, codes, new CatalogAliasIndex(aliases, merchants));
        }

        checkedAt = clock.GetUtcNow();
    }

    public void Dispose() => gate.Dispose();
}

public static class CategoriseServiceCollectionExtensions
{
    /// <summary>
    /// The <c>POST /v1/categorise</c> pipeline (T-352): the service over the shared gate chain (<c>AddZaghlolAskPlan</c> registers it), the published
    /// catalog read model and the answer cache. Call after <c>AddZaghlolAskPlan</c> and <c>AddZaghlolRemoteConfig</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolCategorise(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);
        services.TryAddSingleton(TimeProvider.System);
        services.AddSingleton<ICategoriseCatalog, CategoriseCatalogSource>();
        services.AddSingleton<ICategoriseAnswerCache, CategoriseAnswerCacheRepository>();
        services.TryAddTransient<CategoriseService>();
        return services;
    }
}
