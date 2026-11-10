using System.Globalization;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Prices;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Prices;

/// <summary><c>price_quotes</c> and <c>fx_rates</c> on the Worker login (<c>worker_rw</c>): the price fetcher is their only feed writer.</summary>
internal sealed class PriceFeedStore(IZaghlolDbContextFactory contexts) : IPriceFeedStore
{
    // One statement per quote. The feed columns always move; the served columns move only when no unexpired override is on the row.
    private const string GoldSql = """
        INSERT INTO zaghlol.price_quotes AS q
          (symbol, currency, price, per_unit, as_of, source, is_override, override_expires_at, feed_price, feed_as_of)
        VALUES (@symbol, @currency, @price, @unit, @now, @source, false, NULL, @price, @now)
        ON CONFLICT (symbol, currency) DO UPDATE SET
          feed_price = EXCLUDED.feed_price,
          feed_as_of = EXCLUDED.feed_as_of,
          price = CASE WHEN q.is_override AND q.override_expires_at > @now THEN q.price ELSE EXCLUDED.price END,
          as_of = CASE WHEN q.is_override AND q.override_expires_at > @now THEN q.as_of ELSE EXCLUDED.as_of END,
          source = CASE WHEN q.is_override AND q.override_expires_at > @now THEN q.source ELSE EXCLUDED.source END,
          per_unit = EXCLUDED.per_unit,
          override_expires_at = CASE WHEN q.is_override AND q.override_expires_at > @now THEN q.override_expires_at ELSE NULL END,
          is_override = (q.is_override AND q.override_expires_at > @now)
        """;

    private const string FxSql = """
        INSERT INTO zaghlol.fx_rates (base, quote, rate, as_of, source)
        VALUES (@base, @quote, @rate, @now, @source)
        ON CONFLICT (base, quote) DO UPDATE SET rate = EXCLUDED.rate, as_of = EXCLUDED.as_of, source = EXCLUDED.source
        """;

    public async Task ApplyFeedAsync(NormalizedPrices prices, DateTimeOffset now, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(prices);

        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        foreach (var gold in prices.Gold)
        {
            await using var command = new NpgsqlCommand(GoldSql, connection, transaction);
            command.Parameters.AddWithValue("symbol", gold.Symbol);
            command.Parameters.AddWithValue("currency", gold.Currency);
            command.Parameters.AddWithValue("price", NpgsqlDbType.Numeric, gold.Price);
            command.Parameters.AddWithValue("unit", PriceSymbols.PerGram);
            command.Parameters.AddWithValue("now", now.ToUniversalTime());
            command.Parameters.AddWithValue("source", gold.Source);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        foreach (var fx in prices.Fx)
        {
            await using var command = new NpgsqlCommand(FxSql, connection, transaction);
            command.Parameters.AddWithValue("base", PriceSymbols.FxBase);
            command.Parameters.AddWithValue("quote", fx.Quote);
            command.Parameters.AddWithValue("rate", NpgsqlDbType.Numeric, fx.Rate);
            command.Parameters.AddWithValue("now", now.ToUniversalTime());
            command.Parameters.AddWithValue("source", fx.Source);
            await command.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
    }

    public async Task<IReadOnlyDictionary<string, DateTimeOffset>> FeedTimesAsync(CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Worker);
        var rows = await db.PriceQuotes.AsNoTracking()
            .Where(q => q.Currency == PriceSymbols.Egp && q.FeedAsOf != null)
            .Select(q => new { q.Symbol, FeedAsOf = q.FeedAsOf!.Value })
            .ToListAsync(cancellationToken);
        return rows.ToDictionary(r => r.Symbol, r => r.FeedAsOf, StringComparer.Ordinal);
    }
}

/// <summary>The price cache on the App login (<c>app_rw</c>, SELECT only), for the sync response.</summary>
internal sealed class PriceReader(IAppDbContextFactory contexts) : IPriceReader
{
    public async Task<IReadOnlyList<PriceRow>> ListGoldAsync(CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext();
        var rows = await db.PriceQuotes.AsNoTracking().ToListAsync(cancellationToken);
        return rows.Select(PriceRows.ToRow).ToList();
    }

    public async Task<IReadOnlyList<FxRow>> ListFxAsync(CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext();
        var rows = await db.FxRates.AsNoTracking().Where(r => r.Base == PriceSymbols.FxBase).ToListAsync(cancellationToken);
        return rows.Select(r => new FxRow(r.Quote, r.Rate, r.AsOf, r.Source)).ToList();
    }
}

internal static class PriceRows
{
    public static PriceRow ToRow(PriceQuote q) =>
        new(q.Symbol, q.Currency, q.Price, q.AsOf, q.Source, q.IsOverride, q.OverrideExpiresAt, q.FeedPrice, q.FeedAsOf);
}

/// <summary>Override writes on the Admin login (<c>ops_rw</c>), each with one <c>audit_log</c> row in the same transaction.</summary>
internal sealed class PriceAdminStore(IZaghlolDbContextFactory contexts) : IPriceAdminStore
{
    /// <summary>The audit actions (<c>audit_log.action</c>).</summary>
    public const string OverrideAction = "price_override";
    public const string ClearAction = "price_override_clear";

    private const string Columns = "symbol, currency, price, per_unit, as_of, source, is_override, override_expires_at, feed_price, feed_as_of";

    // A row that is not an override holds the feed value in price/as_of; keep it as the feed value when feed_* was never set.
    private const string OverrideSql = $"""
        INSERT INTO zaghlol.price_quotes AS q ({Columns})
        VALUES (@symbol, @currency, @price, @unit, @now, @source, true, @expires, NULL, NULL)
        ON CONFLICT (symbol, currency) DO UPDATE SET
          feed_price = COALESCE(q.feed_price, CASE WHEN NOT q.is_override THEN q.price END),
          feed_as_of = COALESCE(q.feed_as_of, CASE WHEN NOT q.is_override THEN q.as_of END),
          price = EXCLUDED.price,
          as_of = EXCLUDED.as_of,
          source = EXCLUDED.source,
          is_override = true,
          override_expires_at = EXCLUDED.override_expires_at
        RETURNING {Columns}
        """;

    // Ends the override now: the expiry becomes `now`, so the feed value (if any) is served at once and the next worker run resets the
    // row. ops_rw has no DELETE on price_quotes, and a row stays useful as the record of the last override.
    private const string ClearSql = """
        UPDATE zaghlol.price_quotes SET override_expires_at = @now
        WHERE symbol = @symbol AND currency = @currency AND is_override AND override_expires_at > @now
        """;

    private const string AuditSql = """
        INSERT INTO zaghlol.audit_log (operator_id, action, target, details)
        VALUES (@operator, @action, @target, @details)
        """;

    public async Task<PriceRow> SetOverrideAsync(
        string symbol,
        string currency,
        decimal price,
        string reason,
        DateTimeOffset now,
        DateTimeOffset expiresAt,
        Guid operatorId,
        CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Admin);
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        PriceRow row;
        await using (var upsert = new NpgsqlCommand(OverrideSql, connection, transaction))
        {
            upsert.Parameters.AddWithValue("symbol", symbol);
            upsert.Parameters.AddWithValue("currency", currency);
            upsert.Parameters.AddWithValue("price", NpgsqlDbType.Numeric, price);
            upsert.Parameters.AddWithValue("unit", PriceSymbols.PerGram);
            upsert.Parameters.AddWithValue("now", now.ToUniversalTime());
            upsert.Parameters.AddWithValue("source", "override");
            upsert.Parameters.AddWithValue("expires", expiresAt.ToUniversalTime());

            await using var reader = await upsert.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                throw new InvalidOperationException("The override upsert returned no row.");
            }

            row = new PriceRow(
                reader.GetString(0),
                reader.GetString(1),
                reader.GetDecimal(2),
                reader.GetFieldValue<DateTimeOffset>(4),
                reader.GetString(5),
                reader.GetBoolean(6),
                reader.IsDBNull(7) ? null : reader.GetFieldValue<DateTimeOffset>(7),
                reader.IsDBNull(8) ? null : reader.GetDecimal(8),
                reader.IsDBNull(9) ? null : reader.GetFieldValue<DateTimeOffset>(9));
        }

        await WriteAuditAsync(connection, transaction, operatorId, OverrideAction, symbol, currency, OverrideDetails(price, expiresAt, reason), cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        return row;
    }

    public async Task<bool> ClearOverrideAsync(string symbol, string currency, DateTimeOffset now, Guid operatorId, CancellationToken cancellationToken)
    {
        await using var db = contexts.CreateDbContext(DatabaseRole.Admin);
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);

        int changed;
        await using (var clear = new NpgsqlCommand(ClearSql, connection, transaction))
        {
            clear.Parameters.AddWithValue("symbol", symbol);
            clear.Parameters.AddWithValue("currency", currency);
            clear.Parameters.AddWithValue("now", now.ToUniversalTime());
            changed = await clear.ExecuteNonQueryAsync(cancellationToken);
        }

        if (changed > 0)
        {
            await WriteAuditAsync(connection, transaction, operatorId, ClearAction, symbol, currency, "{}", cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        return changed > 0;
    }

    private static async Task WriteAuditAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid operatorId,
        string action,
        string symbol,
        string currency,
        string details,
        CancellationToken cancellationToken)
    {
        await using var audit = new NpgsqlCommand(AuditSql, connection, transaction);
        audit.Parameters.AddWithValue("operator", operatorId);
        audit.Parameters.AddWithValue("action", action);
        audit.Parameters.AddWithValue("target", $"price:{symbol}:{currency}");
        audit.Parameters.Add(new NpgsqlParameter("details", NpgsqlDbType.Jsonb) { Value = details });
        await audit.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>The audit payload: the new price, its expiry and the operator's reason. Never an e-mail or an order ID.</summary>
    internal static string OverrideDetails(decimal price, DateTimeOffset expiresAt, string reason)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            writer.WriteString("price", PriceWire.Format(price));
            writer.WriteString("expires_at", expiresAt.ToUniversalTime().ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'", CultureInfo.InvariantCulture));
            writer.WriteString("reason", reason);
            writer.WriteEndObject();
        }

        return Encoding.UTF8.GetString(stream.ToArray());
    }
}
