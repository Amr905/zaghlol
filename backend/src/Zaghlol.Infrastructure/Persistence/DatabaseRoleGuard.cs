using System.Data.Common;
using System.Net.Sockets;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Npgsql;

namespace Zaghlol.Infrastructure.Persistence;

/// <summary>
/// SEC F11: a runtime connection must log in as a member of exactly its own group role, and must not be a superuser,
/// the schema owner or a member of <c>migrator</c>. Otherwise a wrong credential in <c>ConnectionStrings:App</c> (for
/// example the migrator's) would silently bypass every grant and the two-login injection boundary.
/// </summary>
public static class DatabaseRoleGuard
{
    // Why a login was rejected. Stable values, safe to log (no names or secrets).
    public const string RejectPrivileged = "privileged_login";
    public const string RejectOwner = "schema_owner";
    public const string RejectMigrator = "migrator_member";
    public const string RejectWrongGroups = "wrong_group_membership";

    /// <summary>One row about <c>current_user</c>: privilege flags, owner, migrator, then each group membership.</summary>
    public const string Query = """
        SELECT r.rolsuper OR r.rolbypassrls OR r.rolcreaterole OR r.rolcreatedb OR r.rolreplication,
               coalesce((SELECT n.nspowner = r.oid FROM pg_catalog.pg_namespace n WHERE n.nspname = 'zaghlol'), false),
               pg_catalog.pg_has_role(current_user, 'migrator', 'MEMBER'),
               pg_catalog.pg_has_role(current_user, 'app_rw', 'MEMBER'),
               pg_catalog.pg_has_role(current_user, 'ops_rw', 'MEMBER'),
               pg_catalog.pg_has_role(current_user, 'worker_rw', 'MEMBER'),
               pg_catalog.pg_has_role(current_user, 'ops_ro', 'MEMBER')
        FROM pg_catalog.pg_roles r WHERE r.rolname = current_user
        """;

    private static readonly string[] Groups = [GrantMatrix.AppRw, GrantMatrix.OpsRw, GrantMatrix.WorkerRw, GrantMatrix.OpsRo];

    /// <summary>The only group a runtime role's login may belong to.</summary>
    public static string ExpectedGroup(DatabaseRole role) => role switch
    {
        DatabaseRole.App => GrantMatrix.AppRw,
        DatabaseRole.Admin => GrantMatrix.OpsRw,
        DatabaseRole.Worker => GrantMatrix.WorkerRw,
        _ => throw new ArgumentOutOfRangeException(nameof(role), role, "the migrator is not a runtime role"),
    };

    /// <summary>Null when the connection's login is acceptable for <paramref name="role"/>; otherwise one of the <c>Reject*</c> values.</summary>
    public static async Task<string?> CheckAsync(NpgsqlConnection connection, DatabaseRole role, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(connection);

        var expected = ExpectedGroup(role);
        await using var command = new NpgsqlCommand(Query, connection);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return RejectWrongGroups;
        }

        if (reader.GetBoolean(0))
        {
            return RejectPrivileged;
        }

        if (reader.GetBoolean(1))
        {
            return RejectOwner;
        }

        if (reader.GetBoolean(2))
        {
            return RejectMigrator;
        }

        for (var i = 0; i < Groups.Length; i++)
        {
            if (reader.GetBoolean(3 + i) != string.Equals(Groups[i], expected, StringComparison.Ordinal))
            {
                return RejectWrongGroups;
            }
        }

        return null;
    }
}

/// <summary>
/// Checks every registered runtime role once the database is reachable and stops the host when a login is wrong, so
/// the process never runs as the owner or with another group's grants. While the database is unreachable it retries
/// quietly (readiness reports 503 meanwhile); it does not block startup.
/// </summary>
internal sealed partial class DatabaseRoleGuardService(
    IServiceProvider services,
    IOptions<DatabaseConnectionOptions> options,
    IHostApplicationLifetime lifetime,
    TimeProvider clock,
    ILogger<DatabaseRoleGuardService> logger) : BackgroundService
{
    public static readonly TimeSpan RetryInterval = TimeSpan.FromSeconds(5);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var pending = options.Value.ConnectionStrings.Keys.ToHashSet();
        while (pending.Count > 0 && !stoppingToken.IsCancellationRequested)
        {
            foreach (var role in pending.ToList())
            {
                try
                {
                    var dataSource = services.GetRequiredKeyedService<NpgsqlDataSource>(role);
                    await using var connection = await dataSource.OpenConnectionAsync(stoppingToken);
                    var reason = await DatabaseRoleGuard.CheckAsync(connection, role, stoppingToken);
                    if (reason is not null)
                    {
                        LogRejected(logger, role, reason);
                        lifetime.StopApplication();
                        return;
                    }

                    pending.Remove(role);
                    LogVerified(logger, role);
                }
                catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
                {
                    return;
                }
                catch (Exception ex) when (ex is DbException or TimeoutException or SocketException or InvalidOperationException)
                {
                    var exceptionType = ex.GetType().Name;
                    LogUnreachable(logger, role, exceptionType);
                }
            }

            if (pending.Count > 0)
            {
                try
                {
                    await Task.Delay(RetryInterval, clock, stoppingToken);
                }
                catch (OperationCanceledException)
                {
                    return;
                }
            }
        }
    }

    [LoggerMessage(Level = LogLevel.Critical, Message = "Database login for role {Role} rejected ({Reason}); stopping")]
    private static partial void LogRejected(ILogger logger, DatabaseRole role, string reason);

    [LoggerMessage(Level = LogLevel.Information, Message = "Database login for role {Role} verified")]
    private static partial void LogVerified(ILogger logger, DatabaseRole role);

    [LoggerMessage(Level = LogLevel.Debug, Message = "Database login check for role {Role} deferred ({ExceptionType})")]
    private static partial void LogUnreachable(ILogger logger, DatabaseRole role, string exceptionType);
}
