using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Zaghlol.Application.Entitlements;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Seats;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Entitlements;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Seats;
using Zaghlol.Infrastructure.Tests.Seats;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Entitlements;

/// <summary>PostgreSQL 17 with the App and Admin logins (T-132): the real store, seat service and verify grant, a recording signer.</summary>
public sealed class EntitlementFixture : IAsyncLifetime
{
    public static readonly DateTimeOffset Start = new DateTimeOffset(2026, 11, 13, 10, 17, 23, TimeSpan.Zero).AddTicks(4567890);

    private ServiceProvider? services;

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public SeatDb Db => new(Database);

    internal IServiceProvider Services => services!;

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:App"] = Database.Api,
                ["ConnectionStrings:Admin"] = Database.Admin,
            })
            .Build();
        var collection = new ServiceCollection();
        collection.AddSingleton<IConfiguration>(configuration);
        collection.AddZaghlolDatabase(DatabaseRole.App, DatabaseRole.Admin);
        services = collection.BuildServiceProvider();
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

    internal Rig NewRig(DateTimeOffset? now = null) => new(services!, Database, now ?? Start);

    public Task ExecAsync(string sql) => ZaghlolTestDatabase.ExecuteAsync(Database.Superuser, sql);

    public async Task<T?> ScalarAsync<T>(string sql)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        var value = await command.ExecuteScalarAsync();
        return value is null or DBNull ? default : (T)value;
    }
}

/// <summary>An account validator that accepts the header <c>valid:&lt;accountId&gt;</c> (the real one is covered by its own tests).</summary>
internal sealed class HeaderAccountValidator : IAccountTokenValidator
{
    public Task<ValidatedAccountToken?> ValidateAsync(Sensitive<string>? token, InstallId caller, DateTimeOffset now, CancellationToken cancellationToken) =>
        Task.FromResult(token?.Reveal() is { } text && text.StartsWith("valid:", StringComparison.Ordinal)
            ? new ValidatedAccountToken(Guid.Parse(text["valid:".Length..]), now.AddDays(20))
            : null);
}

internal sealed class CapturingSigner : IEntitlementSigner
{
    public List<EntitlementClaims> Entitlements { get; } = [];

    public Task<string> SignEntitlementAsync(EntitlementClaims claims, CancellationToken cancellationToken)
    {
        lock (Entitlements)
        {
            Entitlements.Add(claims);
        }

        return Task.FromResult("jws");
    }

    public Task<string> SignAccountTokenAsync(AccountTokenClaims claims, CancellationToken cancellationToken) => Task.FromResult("acct");
}

/// <summary>One test's wiring: a manual clock, the real services over the fixture's logins.</summary>
internal sealed class Rig
{
    public Rig(IServiceProvider services, ZaghlolTestDatabase database, DateTimeOffset now)
    {
        Time = new ManualTime(now);
        Signer = new CapturingSigner();
        Store = new EntitlementStore(services);
        Telemetry = new RecordingSeatTelemetry();
        var seatService = new SeatService(new SeatKeyHasher(new FixedSeatMac(), new NullSeatKeyMetrics()), Telemetry, Time);
        Entitlements = new EntitlementService(Store, Signer, new HeaderAccountValidator(), Time);
        Grant = new VerifyGrant(
            new SeatTransactionFactory(services),
            seatService,
            new SeatKeyProofVerifier(new NullSeatKeyMetrics()),
            new HeaderAccountValidator(),
            Entitlements);
        Transactions = new SeatTransactionFactory(services);
        Seats = seatService;
        Db = new SeatDb(database);
    }

    public ManualTime Time { get; }

    public CapturingSigner Signer { get; }

    public EntitlementStore Store { get; }

    public EntitlementService Entitlements { get; }

    public VerifyGrant Grant { get; }

    public SeatTransactionFactory Transactions { get; }

    public SeatService Seats { get; }

    public RecordingSeatTelemetry Telemetry { get; }

    public SeatDb Db { get; }

    public DateTimeOffset Now => Time.Now;

    /// <summary>The verify step after the store checks passed (an active, written purchase).</summary>
    public Task<VerifyGrantResult> VerifyAsync(
        InstallId caller,
        Guid purchase,
        bool newPayment,
        string? account = null,
        IReadOnlyList<SeatKeyProofInput?>? seatKeys = null,
        string? signedTransaction = null) =>
        Grant.ComposeAsync(
            new StoreVerificationResult(VerifyStatus.Active, null, purchase, GoldPlan.Monthly, null, PurchaseEnvironment.Production, null, true, newPayment),
            new VerifyContext(
                caller,
                account is null ? null : new Sensitive<string>(account),
                Now,
                seatKeys,
                signedTransaction is null ? null : new Sensitive<string>(signedTransaction)),
            CancellationToken.None);

    /// <summary>The claims of a fresh token for the install (as GET /v1/entitlement would issue it).</summary>
    public async Task<EntitlementClaims> TokenAsync(InstallId install, string? account = null)
    {
        var issue = await Entitlements.GetAsync(install, account is null ? null : new Sensitive<string>(account), CancellationToken.None);
        return issue.Claims;
    }
}
