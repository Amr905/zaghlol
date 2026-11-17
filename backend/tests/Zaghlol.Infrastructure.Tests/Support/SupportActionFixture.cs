using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Seats;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Application.Support;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Audit;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Support;
using Zaghlol.Infrastructure.Tests.Seats;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Support;

/// <summary>PostgreSQL 17 with the Admin login and the real support store (T-186). Store calls are a counting fake.</summary>
public sealed class SupportActionFixture : IAsyncLifetime
{
    private ServiceProvider? services;

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public ISupportActionStore Store { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["ConnectionStrings:Admin"] = Database.Admin })
            .Build();
        var collection = new ServiceCollection();
        collection.AddSingleton<IConfiguration>(configuration);
        collection.AddZaghlolDatabase(DatabaseRole.Admin);
        services = collection.BuildServiceProvider();
        Store = new SupportActionStore(services, new AuditWriter());
    }

    public async Task DisposeAsync()
    {
        if (services is not null)
        {
            await services.DisposeAsync();
        }

        if (Database is not null)
        {
            await Database.DisposeAsync();
        }
    }

    public SupportActionService Service(FakeOwnership ownership, RecordingSupportAlerts alerts, TimeProvider? time = null) =>
        new(Store, ownership, new SeatService(new SeatKeyHasher(new FixedSeatMac(), new NullSeatKeyMetrics()), new RecordingSeatTelemetry(), TimeProvider.System), alerts, time ?? TimeProvider.System);

    /// <summary>An <c>operators</c> row; the audit table's foreign key needs it.</summary>
    public async Task<Guid> OperatorAsync(params string[] roles)
    {
        var id = Guid.NewGuid();
        await ExecAsync(
            "INSERT INTO zaghlol.operators (id, oidc_subject, display_name, roles) VALUES (@a, @b, 'Test', @c)",
            id,
            "sub-" + id.ToString("N"),
            roles);
        return id;
    }

    public async Task ExecAsync(string sql, params object[] values)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        Bind(command, values);
        await command.ExecuteNonQueryAsync();
    }

    public async Task<List<object?[]>> RowsAsync(string sql, params object[] values)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        Bind(command, values);
        await using var reader = await command.ExecuteReaderAsync();
        var rows = new List<object?[]>();
        while (await reader.ReadAsync())
        {
            var row = new object?[reader.FieldCount];
            reader.GetValues(row!);
            rows.Add([.. row.Select(v => v switch { DBNull => null, DateTime t => new DateTimeOffset(DateTime.SpecifyKind(t, DateTimeKind.Utc)), _ => v })]);
        }

        return rows;
    }

    private static void Bind(NpgsqlCommand command, object[] values)
    {
        for (var i = 0; i < values.Length; i++)
        {
            command.Parameters.Add(new NpgsqlParameter(((char)('a' + i)).ToString(), values[i]));
        }
    }
}

/// <summary>Counts store calls and remembers whether the order ID reached it (it must, once, and nowhere else).</summary>
public sealed class FakeOwnership : ISupportOwnershipCheck
{
    public OwnershipOutcome Next { get; set; } = OwnershipOutcome.Pass;

    public int Calls { get; private set; }

    public List<string> OrderIds { get; } = [];

    public Task<OwnershipOutcome> CheckAsync(SupportPurchase purchase, Sensitive<string> orderId, CancellationToken cancellationToken)
    {
        Calls++;
        OrderIds.Add(orderId.Reveal());
        return Task.FromResult(Next);
    }
}

/// <summary>Records the support alerts.</summary>
public sealed class RecordingSupportAlerts : ISupportAlerts
{
    public List<string> Raised { get; } = [];

    public void DisputeFrozen(Guid purchaseId) => Raised.Add("dispute_frozen:" + purchaseId);

    public void Unfreeze(Guid purchaseId) => Raised.Add("unfreeze:" + purchaseId);

    public void MovesPerPurchase(Guid purchaseId) => Raised.Add("moves:" + purchaseId);

    public void ActionsPerOperator(Guid operatorId) => Raised.Add("actions:" + operatorId);

    public void OwnershipFailuresPerOperator(Guid operatorId) => Raised.Add("ownership_failures:" + operatorId);
}

/// <summary>One <c>audit_log</c> row of a purchase.</summary>
public sealed record AuditRow(long Id, Guid Operator, string Action, JsonElement Details)
{
    public string Outcome => Details.GetProperty("outcome").GetString()!;

    public string OwnershipOutcome => Details.GetProperty("ownership_outcome").GetString()!;
}
