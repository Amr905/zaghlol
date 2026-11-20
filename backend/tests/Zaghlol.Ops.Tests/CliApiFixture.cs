using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using Zaghlol.Api.Auth;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Support;
using Zaghlol.Domain;
using Zaghlol.Ops.Tests.Support;
using Zaghlol.Testing;

namespace Zaghlol.Ops.Tests;

/// <summary>The real API over a migrated PostgreSQL with the real operator validator against the in-process IdP (Entra profile, Advisory MFA).</summary>
public sealed class CliApiFixture : IAsyncLifetime
{
    private readonly FakeKms kms = FakeKms.CreateDefault();
    private WebApplicationFactory<Program>? factory;

    internal CliTestIdp Idp { get; } = new();

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    internal RecordingOwnership Ownership { get; } = new();

    internal HttpMessageHandler ApiHandler => factory!.Server.CreateHandler();

    public string SnapshotDirectory { get; } = Path.Combine(Path.GetTempPath(), "zaghlol-t137-" + Guid.NewGuid().ToString("N"));

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            var settings = new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["ConnectionStrings:App"] = Database.Api,
                ["ConnectionStrings:Admin"] = Database.Admin,
                ["OperatorAuth:Enabled"] = "true",
                ["OperatorAuth:Profile"] = "Entra",
                ["OperatorAuth:AllowedTenants:0"] = FakeOidcIssuer.TenantId,
                ["OperatorAuth:Issuer"] = FakeOidcIssuer.DefaultIssuer,
                ["OperatorAuth:Audiences:0"] = FakeOidcIssuer.CliAudience,
                ["OperatorAuth:Audiences:1"] = FakeOidcIssuer.AdminAudience,
                ["OperatorAuth:PhishingResistantMode"] = "Advisory",
                ["Catalog:Snapshots:Directory"] = SnapshotDirectory,
                ["Catalog:Snapshots:BaseUrl"] = "https://api.zaghlol.test",
                ["RateLimits:PerNetwork:TokenLimit"] = "100000",
                ["RateLimits:PerNetwork:TokensPerPeriod"] = "100000",
                ["RateLimits:PerNetwork:PeriodSeconds"] = "60",
                ["RateLimits:PerToken:TokenLimit"] = "100000",
                ["RateLimits:PerToken:TokensPerPeriod"] = "100000",
                ["RateLimits:PerToken:PeriodSeconds"] = "60",
                ["RateLimits:SupportLookup:TokenLimit"] = "1000",
                ["RateLimits:SupportLookup:TokensPerPeriod"] = "1000",
                ["RateLimits:SupportLookup:PeriodSeconds"] = "60",
            };
            foreach (var (key, value) in settings)
            {
                builder.UseSetting(key, value);
            }

            foreach (var (key, value) in kms.Settings())
            {
                builder.UseSetting(key, value);
            }

            builder.ConfigureServices(services =>
            {
                kms.Use(services);
                services.AddHttpClient(OidcKeyCache.HttpClientName).ConfigurePrimaryHttpMessageHandler(() => Idp.Issuer.CreateHandler());
                services.RemoveAll<ISupportOwnershipCheck>();
                services.AddSingleton<ISupportOwnershipCheck>(Ownership);
            });
        });
        _ = factory.Server;
    }

    public async Task DisposeAsync()
    {
        if (factory is not null)
        {
            await factory.DisposeAsync();
        }

        if (Database is not null)
        {
            await Database.DisposeAsync();
        }

        kms.Dispose();
        Idp.Dispose();
        if (Directory.Exists(SnapshotDirectory))
        {
            Directory.Delete(SnapshotDirectory, recursive: true);
        }
    }

    /// <summary>A new <c>operators</c> row (as <c>seed-operator.sql</c> makes it) and the IdP subject to sign in with.</summary>
    public async Task<(Guid Id, string Subject)> NewOperatorAsync(params string[] roles)
    {
        var id = Guid.NewGuid();
        var subject = "sub-" + Guid.NewGuid().ToString("N");
        await using var connection = new NpgsqlConnection(Database.Migrator);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("INSERT INTO zaghlol.operators (id, oidc_subject, display_name, roles) VALUES (@id, @sub, 'T-137 operator', @roles)", connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("sub", subject);
        command.Parameters.AddWithValue("roles", roles);
        await command.ExecuteNonQueryAsync();
        return (id, subject);
    }

    public async Task<object?> ScalarAsync(string sql, params (string Name, object Value)[] parameters)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        foreach (var (name, value) in parameters)
        {
            command.Parameters.AddWithValue(name, value);
        }

        var result = await command.ExecuteScalarAsync();
        return result is DBNull ? null : result;
    }

    public async Task ExecuteAsync(string sql, params (string Name, object Value)[] parameters)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        foreach (var (name, value) in parameters)
        {
            command.Parameters.AddWithValue(name, value);
        }

        await command.ExecuteNonQueryAsync();
    }

    public async Task<long> AuditAsync(string action, Guid? operatorId = null) =>
        (long)(await ScalarAsync("SELECT count(*) FROM zaghlol.audit_log WHERE action = @a AND (@o::uuid IS NULL OR operator_id = @o::uuid)", ("a", action), ("o", (object?)operatorId ?? DBNull.Value)))!;

    /// <summary>A purchase held by one install, in cooldown, with one fresh pending claimant and no account link (as in the T-186 contract tests).</summary>
    public async Task<(Guid Purchase, Guid Holder, Guid Claimant, string Email)> SeedMovableAsync()
    {
        var holder = Guid.NewGuid();
        var claimant = Guid.NewGuid();
        var purchase = Guid.NewGuid();
        var account = Guid.NewGuid();
        var email = "cli-" + Guid.NewGuid().ToString("N")[..8] + "@example.com";
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO zaghlol.installs (id, token_hash, platform, app_version) VALUES (@holder, @h1, 'android', '1.2.0'), (@claimant, @h2, 'android', '1.2.0');
            INSERT INTO zaghlol.accounts (id, provider, provider_subject, email) VALUES (@account, 'google', @subject, @email);
            INSERT INTO zaghlol.purchases (id, store, product_id, plan, store_key, state, environment, last_verified_at, install_id)
              VALUES (@purchase, 'google_play', 'zaghlol_gold_monthly', 'monthly', @key, 'active', 'production', now(), @holder);
            INSERT INTO zaghlol.purchase_seats (purchase_id, install_id, proof, bound_at, last_moved_at, next_move_at)
              VALUES (@purchase, @holder, 'attested', now(), date_trunc('hour', now()) + interval '10 days' - interval '30 days', date_trunc('hour', now()) + interval '10 days');
            INSERT INTO zaghlol.seat_claimants (purchase_id, install_id, claimed_at, channel) VALUES (@purchase, @claimant, now() - interval '1 hour', 'restore');
            INSERT INTO zaghlol.account_installs (account_id, install_id) VALUES (@account, @holder);
            """,
            connection);
        command.Parameters.AddWithValue("holder", holder);
        command.Parameters.AddWithValue("claimant", claimant);
        command.Parameters.AddWithValue("h1", System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));
        command.Parameters.AddWithValue("h2", System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));
        command.Parameters.AddWithValue("account", account);
        command.Parameters.AddWithValue("subject", Guid.NewGuid().ToString("N"));
        command.Parameters.AddWithValue("email", email);
        command.Parameters.AddWithValue("purchase", purchase);
        command.Parameters.AddWithValue("key", "cli-" + Guid.NewGuid().ToString("N"));
        await command.ExecuteNonQueryAsync();
        return (purchase, holder, claimant, email);
    }
}

/// <summary>The store order check as a fake that passes and keeps what it was given (the server side of the D-57 proof).</summary>
internal sealed class RecordingOwnership : ISupportOwnershipCheck
{
    public List<string> OrderIds { get; } = [];

    public OwnershipOutcome Next { get; set; } = OwnershipOutcome.Pass;

    public Task<OwnershipOutcome> CheckAsync(SupportPurchase purchase, Sensitive<string> orderId, CancellationToken cancellationToken)
    {
        OrderIds.Add(orderId.Reveal());
        return Task.FromResult(Next);
    }
}
