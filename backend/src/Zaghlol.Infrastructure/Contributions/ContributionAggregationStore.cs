using Microsoft.EntityFrameworkCore;
using Npgsql;
using Zaghlol.Application.Contributions;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Contributions;

/// <summary>
/// The aggregation run on the Worker login (<c>worker_rw</c>, FR-BE-07): one transaction that rolls the raw rows up by
/// (<c>merchant_norm</c>, institution), purging raw rows past retention first and the rows of decided aggregates last. Each install has at most one raw row per key (unique with
/// <c>install_hash</c>), so a row count is a distinct-install count and the install hash is never read out of the database.
/// <list type="bullet">
/// <item>A <c>collecting</c> aggregate is refreshed every run and becomes <c>ready_for_review</c> at the threshold (A-48).</item>
/// <item>A <c>ready_for_review</c> aggregate only grows: it is refreshed when the new count is not below the stored one, so the
/// purge of old raw rows never un-readies it or shrinks what the operator is looking at.</item>
/// <item><c>promoted</c> and <c>rejected</c> aggregates are never touched; their raw rows are deleted.</item>
/// <item>A <c>collecting</c> aggregate whose raw rows are all gone is reset to 0 installs (the worker has no DELETE on it).</item>
/// <item>The top category is the most-voted one, ties broken by code, so a run is deterministic.</item>
/// </list>
/// </summary>
internal sealed class ContributionAggregationStore(IZaghlolDbContextFactory contexts) : IContributionAggregationStore
{
    private const string UpsertSql = """
        WITH votes AS (
          SELECT merchant_norm, institution_code, category_code, count(*) AS n
          FROM zaghlol.merchant_contributions
          GROUP BY merchant_norm, institution_code, category_code),
        rolled AS (
          SELECT merchant_norm, institution_code,
                 sum(n)::integer AS installs,
                 (array_agg(category_code ORDER BY n DESC, category_code ASC))[1] AS top_category,
                 jsonb_object_agg(category_code, n) AS category_votes
          FROM votes
          GROUP BY merchant_norm, institution_code)
        INSERT INTO zaghlol.contribution_aggregates AS a
          (merchant_norm, institution_code, distinct_installs, top_category_code, category_votes, status)
        SELECT merchant_norm, institution_code, installs, top_category, category_votes,
               CASE WHEN installs >= @threshold THEN 'ready_for_review' ELSE 'collecting' END
        FROM rolled
        ON CONFLICT (merchant_norm, institution_code) DO UPDATE SET
          distinct_installs = EXCLUDED.distinct_installs,
          top_category_code = EXCLUDED.top_category_code,
          category_votes = EXCLUDED.category_votes,
          status = CASE WHEN a.status = 'collecting' AND EXCLUDED.distinct_installs >= @threshold
                        THEN 'ready_for_review' ELSE a.status END
        WHERE a.status = 'collecting'
           OR (a.status = 'ready_for_review' AND EXCLUDED.distinct_installs >= a.distinct_installs)
        """;

    private const string ResetEmptySql = """
        UPDATE zaghlol.contribution_aggregates a
        SET distinct_installs = 0, category_votes = '{}'::jsonb
        WHERE a.status = 'collecting' AND a.distinct_installs <> 0
          AND NOT EXISTS (SELECT 1 FROM zaghlol.merchant_contributions c
                          WHERE c.merchant_norm = a.merchant_norm AND c.institution_code = a.institution_code)
        """;

    private const string ReadyCountSql = "SELECT count(*) FROM zaghlol.contribution_aggregates WHERE status = 'ready_for_review'";

    private const string PurgeDecidedSql = """
        DELETE FROM zaghlol.merchant_contributions c
        USING zaghlol.contribution_aggregates a
        WHERE a.merchant_norm = c.merchant_norm AND a.institution_code = c.institution_code
          AND a.status IN ('promoted', 'rejected')
        """;

    private const string PurgeExpiredSql = "DELETE FROM zaghlol.merchant_contributions WHERE received_at < @cutoff";

    public async Task<AggregationRun> RunAsync(int minDistinctInstalls, DateTimeOffset rawCutoff, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        // Expired rows go first, so they never count; decided keys' rows go last (their aggregates are not touched either way).
        var purgedExpired = await ExecuteAsync(connection, transaction, PurgeExpiredSql, new NpgsqlParameter("cutoff", rawCutoff.ToUniversalTime()), cancellationToken);
        var readyBefore = await ScalarAsync(connection, transaction, ReadyCountSql, cancellationToken);

        int updated;
        await using (var upsert = new NpgsqlCommand(UpsertSql, connection, transaction))
        {
            upsert.Parameters.AddWithValue("threshold", minDistinctInstalls);
            updated = await upsert.ExecuteNonQueryAsync(cancellationToken);
        }

        await ExecuteAsync(connection, transaction, ResetEmptySql, null, cancellationToken);
        var readyAfter = await ScalarAsync(connection, transaction, ReadyCountSql, cancellationToken);
        var purgedDecided = await ExecuteAsync(connection, transaction, PurgeDecidedSql, null, cancellationToken);

        await transaction.CommitAsync(cancellationToken);
        return new AggregationRun(updated, (int)Math.Max(0, readyAfter - readyBefore), purgedDecided, purgedExpired);
    }

    private static async Task<int> ExecuteAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, string sql, NpgsqlParameter? parameter, CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        if (parameter is not null)
        {
            command.Parameters.Add(parameter);
        }

        return await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private static async Task<long> ScalarAsync(NpgsqlConnection connection, NpgsqlTransaction transaction, string sql, CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(sql, connection, transaction);
        return (long)(await command.ExecuteScalarAsync(cancellationToken))!;
    }
}
