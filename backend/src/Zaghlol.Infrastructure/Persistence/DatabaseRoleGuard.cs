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
/// the schema or database owner or a member of <c>migrator</c>. Otherwise a wrong credential in <c>ConnectionStrings:App</c>
/// (for example the migrator's) would silently bypass every grant and the two-login injection boundary.
/// FU-019: every check runs on <c>session_user</c> (the login), and the session must not have switched role
/// (<c>-c role=…</c> or <c>SET ROLE</c>), so a superuser login can't pass as <c>zaghlol_api</c>.
/// FU-023: membership is the full transitive closure, so a grant of <c>pg_write_all_data</c> or a provider admin
/// group (directly or through an intermediate role) is rejected too.
/// </summary>
public static class DatabaseRoleGuard
{
    // Why a login was rejected. Stable values, safe to log (no names or secrets).
    public const string RejectRoleSwitched = "role_switched";
    public const string RejectPrivileged = "privileged_login";
    public const string RejectOwner = "schema_owner";
    public const string RejectMigrator = "migrator_member";
    public const string RejectWrongGroups = "wrong_group_membership";

    /// <summary>
    /// One row about <c>session_user</c> and every role it is transitively a member of: role switched, privilege flags,
    /// owner of the schema or database, migrator membership, then the sorted names of all groups.
    /// </summary>
    public const string Query = """
        WITH RECURSIVE me AS (
            SELECT r.oid FROM pg_catalog.pg_roles r WHERE r.rolname = session_user
        ), groups(roleid) AS (
            SELECT m.roleid FROM pg_catalog.pg_auth_members m JOIN me ON m.member = me.oid
            UNION
            SELECT m.roleid FROM pg_catalog.pg_auth_members m JOIN groups g ON m.member = g.roleid
        ), everyone(oid) AS (
            SELECT oid FROM me UNION SELECT roleid FROM groups
        )
        SELECT session_user <> current_user,
               EXISTS (SELECT 1 FROM pg_catalog.pg_roles r JOIN everyone e ON e.oid = r.oid
                       WHERE r.rolsuper OR r.rolbypassrls OR r.rolcreaterole OR r.rolcreatedb OR r.rolreplication),
               EXISTS (SELECT 1 FROM pg_catalog.pg_namespace n JOIN everyone e ON e.oid = n.nspowner WHERE n.nspname = 'zaghlol')
                 OR EXISTS (SELECT 1 FROM pg_catalog.pg_database d JOIN everyone e ON e.oid = d.datdba
                            WHERE d.datname = pg_catalog.current_database()),
               EXISTS (SELECT 1 FROM groups g JOIN pg_catalog.pg_roles r ON r.oid = g.roleid WHERE r.rolname = 'migrator'),
               coalesce((SELECT array_agg(r.rolname::text ORDER BY r.rolname::text)
                         FROM groups g JOIN pg_catalog.pg_roles r ON r.oid = g.roleid), '{}'::text[])
        FROM me
        """;

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
            return RejectRoleSwitched;
        }

        if (reader.GetBoolean(1))
        {
            return RejectPrivileged;
        }

        if (reader.GetBoolean(2))
        {
            return RejectOwner;
        }

        if (reader.GetBoolean(3))
        {
            return RejectMigrator;
        }

        var groups = reader.GetFieldValue<string[]>(4);
        return groups.Length == 1 && string.Equals(groups[0], expected, StringComparison.Ordinal) ? null : RejectWrongGroups;
    }
}

/// <summary>
/// The process exit code (FU-023): <c>Program</c> returns <see cref="Value"/>, so a host stopped by a guard exits non-zero
/// and the orchestrator sees a failed start instead of a clean exit.
/// </summary>
public sealed class HostExitCode
{
    /// <summary>EX_CONFIG (sysexits.h): a database login was rejected by <see cref="DatabaseRoleGuard"/>.</summary>
    public const int DatabaseLoginRejected = 78;

    private int value;

    public int Value => Volatile.Read(ref value);

    /// <summary>Records the first failure; later calls keep it.</summary>
    public void Fail(int code) => Interlocked.CompareExchange(ref value, code, 0);
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
    HostExitCode exitCode,
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
                        exitCode.Fail(HostExitCode.DatabaseLoginRejected);
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
