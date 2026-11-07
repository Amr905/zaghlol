using System.Data.Common;
using System.Net.Sockets;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Npgsql;
using Zaghlol.Application.Health;

namespace Zaghlol.Infrastructure.Persistence;

/// <summary>
/// Readiness for <c>GET /v1/health</c> (FU-003). The probe runs as the API's <c>app_rw</c> login on a pool of its own
/// with one connection (<see cref="DataSourceKey"/>), so it never competes with or disturbs the <c>/v1</c> pool: a slow
/// or exhausted App pool isn't reported as "database down", and a failed probe never clears anybody's connections.
/// The probe query is the login check of <see cref="DatabaseRoleGuard"/>, so the API is never "ready" as the wrong
/// role (SEC F11). 1 s timeout, answer cached for 2 s, at most one probe in flight.
/// </summary>
internal sealed partial class PostgresDatabaseReadiness(
    [FromKeyedServices(PostgresDatabaseReadiness.DataSourceKey)] NpgsqlDataSource probeSource,
    TimeProvider clock,
    ILogger<PostgresDatabaseReadiness> logger) : IDatabaseReadiness, IDisposable
{
    /// <summary>Keyed-service key of the probe's own one-connection data source.</summary>
    public const string DataSourceKey = "zaghlol-readiness";

    public static readonly TimeSpan ProbeTimeout = TimeSpan.FromSeconds(1);
    public static readonly TimeSpan CacheDuration = TimeSpan.FromSeconds(2);

    private readonly SemaphoreSlim gate = new(1, 1);
    private Snapshot? last;

    /// <summary>The probe's data source: the App connection string with a pool of one and its own application name.</summary>
    public static NpgsqlDataSource CreateProbeSource(string appConnectionString)
    {
        var builder = new NpgsqlDataSourceBuilder(appConnectionString);
        builder.ConnectionStringBuilder.MaxPoolSize = 1;
        builder.ConnectionStringBuilder.MinPoolSize = 0;
        builder.ConnectionStringBuilder.ApplicationName = "zaghlol-api-readiness";
        return builder.Build();
    }

    public async ValueTask<bool> IsReadyAsync(CancellationToken cancellationToken)
    {
        if (TryGetFresh(out var cached))
        {
            return cached;
        }

        await gate.WaitAsync(cancellationToken);
        try
        {
            if (TryGetFresh(out cached))
            {
                return cached;
            }

            // The probe ignores the caller's token: one client hanging up must not record "not ready" for everyone.
            var ready = await ProbeAsync();
            Volatile.Write(ref last, new Snapshot(clock.GetUtcNow() + CacheDuration, ready));
            return ready;
        }
        finally
        {
            gate.Release();
        }
    }

    public void Dispose() => gate.Dispose();

    private bool TryGetFresh(out bool ready)
    {
        var snapshot = Volatile.Read(ref last);
        ready = snapshot?.Ready ?? false;
        return snapshot is not null && clock.GetUtcNow() < snapshot.ValidUntil;
    }

    private async Task<bool> ProbeAsync()
    {
        using var timeout = new CancellationTokenSource(ProbeTimeout, clock);
        var probe = QueryAsync(timeout.Token);
        try
        {
            // The driver doesn't honour cancellation in every phase (a server that accepts TCP but never answers the
            // startup handshake holds OpenAsync until the connection Timeout), so the 1 s bound is enforced here too.
            var reason = await probe.WaitAsync(ProbeTimeout, clock);
            if (reason is not null)
            {
                LogWrongLogin(logger, reason);
                return false;
            }

            return true;
        }
        catch (Exception ex) when (ex is DbException or OperationCanceledException or TimeoutException or SocketException
                                       or InvalidOperationException)
        {
            // An abandoned probe finishes (or fails) on its own; observe it so its exception is never unobserved.
            _ = probe.ContinueWith(
                static t => _ = t.Exception,
                CancellationToken.None,
                TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously,
                TaskScheduler.Default);

            // Only the exception type: messages can carry host names or other connection details. No pool is cleared:
            // Npgsql discards broken connections itself, and the probe's pool holds at most one.
            LogNotReady(logger, ex.GetType().Name);
            return false;
        }
    }

    private async Task<string?> QueryAsync(CancellationToken cancellationToken)
    {
        await using var connection = await probeSource.OpenConnectionAsync(cancellationToken);
        return await DatabaseRoleGuard.CheckAsync(connection, DatabaseRole.App, cancellationToken);
    }

    [LoggerMessage(Level = LogLevel.Warning, Message = "Database readiness probe failed ({ExceptionType})")]
    private static partial void LogNotReady(ILogger logger, string exceptionType);

    [LoggerMessage(Level = LogLevel.Error, Message = "Database readiness: the App login is not acceptable ({Reason})")]
    private static partial void LogWrongLogin(ILogger logger, string reason);

    private sealed record Snapshot(DateTimeOffset ValidUntil, bool Ready);
}
