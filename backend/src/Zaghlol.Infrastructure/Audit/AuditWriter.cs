using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Audit;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Audit;

/// <summary>
/// The one writer of <c>audit_log</c> (T-136 design note §5), shared by the flag, catalog and support stores. It inserts in
/// the caller's transaction, so a call leaves exactly one row or, when anything rolls back, none; a failed insert throws and
/// fails the write. <c>at</c> is left to the database clock (the RLS policy only accepts rows stamped now).
/// </summary>
internal interface IAuditWriter
{
    /// <summary>Inserts the row and returns its id.</summary>
    Task<long> WriteAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid operatorId,
        AuditEntry entry,
        CancellationToken cancellationToken);
}

internal sealed class AuditWriter : IAuditWriter
{
    private const string InsertSql = """
        INSERT INTO zaghlol.audit_log (operator_id, action, target, details)
        VALUES (@operator, @action, @target, @details)
        RETURNING id
        """;

    public async Task<long> WriteAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction transaction,
        Guid operatorId,
        AuditEntry entry,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(transaction);
        ArgumentNullException.ThrowIfNull(entry);

        await using var command = new NpgsqlCommand(InsertSql, connection, transaction);
        command.Parameters.AddWithValue("operator", operatorId);
        command.Parameters.AddWithValue("action", entry.Action);
        command.Parameters.AddWithValue("target", entry.Target);
        command.Parameters.Add(new NpgsqlParameter("details", NpgsqlDbType.Jsonb) { Value = entry.Details() });
        var id = await command.ExecuteScalarAsync(cancellationToken);
        return id is long value ? value : throw new InvalidOperationException("The audit insert returned no id.");
    }
}

internal static class AuditWriterExtensions
{
    /// <summary>Writes through <paramref name="writer"/> on the EF context's open connection and current transaction.</summary>
    public static Task<long> WriteAsync(
        this IAuditWriter writer,
        ZaghlolDbContext db,
        Guid operatorId,
        AuditEntry entry,
        CancellationToken cancellationToken)
    {
        var transaction = db.Database.CurrentTransaction
            ?? throw new InvalidOperationException("An audit row is written only inside the write's transaction.");
        return writer.WriteAsync(
            (NpgsqlConnection)db.Database.GetDbConnection(),
            (NpgsqlTransaction)transaction.GetDbTransaction(),
            operatorId,
            entry,
            cancellationToken);
    }
}

public static class AuditServiceCollectionExtensions
{
    /// <summary>The shared audit writer. Called by every store registration that writes audit rows.</summary>
    public static IServiceCollection AddZaghlolAudit(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<IAuditWriter, AuditWriter>();
        return services;
    }
}
