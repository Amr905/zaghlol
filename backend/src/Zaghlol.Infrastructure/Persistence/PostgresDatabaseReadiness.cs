using System.Data.Common;
using System.Net.Sockets;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Npgsql;
using Zaghlol.Application.Health;

namespace Zaghlol.Infrastructure.Persistence;

/// <summary>
/// Readiness for <c>GET /v1/health</c> (FU-003): <c>SELECT 1</c> as the API's <c>app_rw</c> login, with a 1 s timeout,
/// the answer cached for 2 s, and at most one probe in flight.
/// </summary>
internal sealed partial class PostgresDatabaseReadiness(
    [FromKeyedServices(DatabaseRole.App)] NpgsqlDataSource dataSource,
    TimeProvider clock,
    ILogger<PostgresDatabaseReadiness> logger) : IDatabaseReadiness, IDisposable
{
    public static readonly TimeSpan ProbeTimeout = TimeSpan.FromSeconds(1);
    public static readonly TimeSpan CacheDuration = TimeSpan.FromSeconds(2);

    private readonly SemaphoreSlim gate = new(1, 1);
    private Snapshot? last;

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
        try
        {
            await using var connection = await dataSource.OpenConnectionAsync(timeout.Token);
            await using var command = new NpgsqlCommand("SELECT 1", connection);
            return await command.ExecuteScalarAsync(timeout.Token) is 1;
        }
        catch (Exception ex) when (ex is DbException or OperationCanceledException or TimeoutException or SocketException
                                       or InvalidOperationException)
        {
            // Only the exception type: messages can carry host names or other connection details.
            LogNotReady(logger, ex.GetType().Name);

            // Pooled connections are likely dead (server restart, failover); don't hand them out after recovery.
            dataSource.Clear();
            return false;
        }
    }

    [LoggerMessage(Level = LogLevel.Warning, Message = "Database readiness probe failed ({ExceptionType})")]
    private static partial void LogNotReady(ILogger logger, string exceptionType);

    private sealed record Snapshot(DateTimeOffset ValidUntil, bool Ready);
}
