using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using Zaghlol.Application.Operators;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Operators;

/// <summary>
/// <c>operators</c> on the Admin login. <c>ops_rw</c> holds SELECT only on this table (no runtime role writes operators,
/// FU-024), so the lookup is read-only by grant, not just by code. Rows are provisioned by
/// <c>backend/deploy/db/seed-operator.sql</c> as <c>migrator</c>.
/// </summary>
internal sealed class OperatorDirectory(IZaghlolDbContextFactory contexts) : IOperatorDirectory
{
    private const string FindSql = "SELECT id, roles, disabled_at IS NOT NULL FROM zaghlol.operators WHERE oidc_subject = @sub";

    public async Task<OperatorRecord?> FindBySubjectAsync(string subject, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(subject);

        await using var db = contexts.CreateDbContext(DatabaseRole.Admin);
        await db.Database.OpenConnectionAsync(cancellationToken);
        var connection = (NpgsqlConnection)db.Database.GetDbConnection();
        await using var command = new NpgsqlCommand(FindSql, connection);
        command.Parameters.AddWithValue("sub", subject);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        return new OperatorRecord(reader.GetGuid(0), reader.GetFieldValue<string[]>(1), reader.GetBoolean(2));
    }
}

public static class OperatorServiceCollectionExtensions
{
    /// <summary>The operator directory on the Admin login. Call after <c>AddZaghlolDatabase</c> with <c>DatabaseRole.Admin</c>.</summary>
    public static IServiceCollection AddZaghlolOperators(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<IOperatorDirectory, OperatorDirectory>();
        return services;
    }
}
