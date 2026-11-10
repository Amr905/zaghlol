using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Serilog;
using Zaghlol.Api.Endpoints.V1;
using Zaghlol.Api.Idempotency;
using Zaghlol.Api.Signing;
using Zaghlol.Api.Tests.Installs;
using Zaghlol.Application.Catalog;
using Zaghlol.Application.Prices;
using Zaghlol.Application.Sync;
using Zaghlol.Domain;
using Zaghlol.Infrastructure;
using Zaghlol.Infrastructure.Catalog;
using Zaghlol.Infrastructure.Flags;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Logging;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Prices;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Sync;

/// <summary>
/// The real pipeline, install and sync endpoints over a migrated PostgreSQL 17 and the fake KMS, with a movable clock, captured
/// logs, a seeded catalog (versions 1 and 2), one flag and a price cache, and switchable faults in front of the catalog reader,
/// the price reader, the entitlement extension point and the install hasher.
/// </summary>
public sealed class SyncHostFixture : IAsyncLifetime, IDisposable
{
    public const string FullUrl2 = "https://cdn.zaghlol.test/v1/catalog/2/full";

    private WebApplication? app;

    public FakeKms Kms { get; } = FakeKms.CreateDefault();

    public ManualClock Clock { get; } = new();

    public CapturingSink LogSink { get; } = new();

    public SyncFaults Faults { get; } = new();

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public HttpClient Client { get; private set; } = null!;

    public IServiceProvider Services => app!.Services;

    /// <summary>When the seeded prices were fetched.</summary>
    public DateTimeOffset PricesAsOf { get; private set; }

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        PricesAsOf = Clock.Now;
        await SeedAsync();

        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = "Testing" });
        builder.WebHost.UseTestServer();
        var settings = new Dictionary<string, string?>(Kms.Settings())
        {
            ["ConnectionStrings:App"] = Database.Api,
            ["RateLimits:PerNetwork:TokenLimit"] = "100000",
            ["RateLimits:PerNetwork:TokensPerPeriod"] = "100000",
            ["RateLimits:PerNetwork:PeriodSeconds"] = "60",
            ["RateLimits:Register:TokenLimit"] = "100000",
            ["RateLimits:Register:TokensPerPeriod"] = "100000",
            ["RateLimits:Register:PeriodSeconds"] = "60",
            ["RateLimits:PerToken:TokenLimit"] = "100000",
            ["RateLimits:PerToken:TokensPerPeriod"] = "100000",
            ["RateLimits:PerToken:PeriodSeconds"] = "60",
        };
        builder.Configuration.AddInMemoryCollection(settings);
        builder.Host.UseSerilog((_, _, logger) => logger.ConfigureZaghlol("api").WriteTo.Sink(LogSink));

        var services = builder.Services;
        services.AddSingleton<TimeProvider>(Clock);
        services.AddInfrastructure();
        services.AddZaghlolKms();
        Kms.Use(services);
        services.AddZaghlolDatabase(DatabaseRole.App);
        services.AddZaghlolHttp();
        services.AddZaghlolLogPseudonymizer();
        services.AddZaghlolInstalls();
        services.AddZaghlolCatalog();
        services.AddZaghlolFlagReader();
        services.AddZaghlolPrices();
        services.AddSingleton<ISyncEntitlementBlock>(Faults.Entitlement);
        services.AddZaghlolSync();
        Decorate<ICatalogReader>(services, inner => new FaultyCatalogReader(inner, Faults));
        Decorate<IPriceReader>(services, inner => new FaultyPriceReader(inner, Faults));
        Decorate<IInstallHasher>(services, inner => new FaultyHasher(inner, Faults));

        app = builder.Build();
        app.UseZaghlolPipeline();
        app.MapInstalls();
        app.MapSync();
        await app.StartAsync();
        Client = app.GetTestClient();
    }

    public async Task DisposeAsync()
    {
        Client?.Dispose();
        if (app is not null)
        {
            await app.StopAsync();
            await app.DisposeAsync();
        }

        if (Database is not null)
        {
            await Database.DisposeAsync();
        }
    }

    public void Dispose() => Kms.Dispose();

    /// <summary>The published Sync keys, to verify <c>Zaghlol-Signature</c>.</summary>
    public IReadOnlyList<SigningKey> SyncKeys => Services.GetRequiredService<ISigner>().PublishedKeys(SigningPurpose.Sync);

    /// <summary>A unique app version, so daily-active rows of one test are its own.</summary>
    public static string UniqueAppVersion() => "1.0.0-t" + Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(4));

    /// <summary>
    /// A unique merchant or bank name of letters only: random hex could form a 6-digit run and be filtered (or rejected by the
    /// database CHECK), which is not what the test means to exercise.
    /// </summary>
    public static string UniqueName(string label) =>
        "sync " + label + " " + string.Concat(RandomNumberGenerator.GetBytes(10).Select(b => (char)('a' + (b % 26))));

    /// <summary>16 random bytes as a canonical time nonce.</summary>
    public static string NewNonce() => System.Buffers.Text.Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(16));

    /// <summary>Registers a new install on <paramref name="appVersion"/>; returns its ID and token.</summary>
    public async Task<(string InstallId, string Token)> NewInstallAsync(string appVersion = "1.0.0", string platform = "android")
    {
        var installId = InstallsHostFixture.NewInstallId();
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/installs");
        request.Content = new StringContent(InstallsHostFixture.InstallBody(installId, platform, appVersion), Encoding.UTF8, "application/json");
        request.Headers.Add(IdempotencyKeys.HeaderName, InstallsHostFixture.NewKey());
        using var response = await Client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (installId, await InstallsHostFixture.TokenOf(response));
    }

    public async Task<HttpResponseMessage> SyncAsync(
        string token,
        string body,
        string? nonce = null,
        string? app = "android/1.0.0 (42)",
        IReadOnlyDictionary<string, string>? headers = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/sync");
        request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        if (nonce is not null)
        {
            request.Headers.TryAddWithoutValidation(TimeNonceFilter.HeaderName, nonce);
        }

        if (app is not null)
        {
            request.Headers.TryAddWithoutValidation(SyncEndpoints.AppHeader, app);
        }

        foreach (var (name, value) in headers ?? new Dictionary<string, string>())
        {
            request.Headers.TryAddWithoutValidation(name, value);
        }

        request.Content = new StringContent(body, Encoding.UTF8);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        return await Client.SendAsync(request);
    }

    public static string AppHeader(string appVersion, string platform = "android") => $"{platform}/{appVersion} (7)";

    public static string Body(int catalogVersion = 0, int flagsVersion = 0, string? pricesAsOf = null, string extra = "")
    {
        var builder = new StringBuilder("{\"catalogVersion\":")
            .Append(catalogVersion.ToString(CultureInfo.InvariantCulture))
            .Append(",\"flagsVersion\":")
            .Append(flagsVersion.ToString(CultureInfo.InvariantCulture));
        if (pricesAsOf is not null)
        {
            builder.Append(",\"pricesAsOf\":\"").Append(pricesAsOf).Append('"');
        }

        return builder.Append(extra).Append('}').ToString();
    }

    public static string Contributions(params (string Merchant, string Institution, string Category)[] items) =>
        ",\"contributions\":[" + string.Join(',', items.Select(i =>
            "{\"merchantNorm\":" + JsonSerializer.Serialize(i.Merchant) + ",\"institutionCode\":\"" + i.Institution + "\",\"categoryCode\":\"" + i.Category + "\"}")) + "]";

    public static string BankRequests(params (string Name, string Country, string Channel)[] items) =>
        ",\"bankRequests\":[" + string.Join(',', items.Select(i =>
            "{\"institutionName\":" + JsonSerializer.Serialize(i.Name) + ",\"country\":\"" + i.Country + "\",\"channel\":\"" + i.Channel + "\"}")) + "]";

    public async Task<object?> ScalarAsync(string sql, params object[] parameters)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        foreach (var parameter in parameters)
        {
            command.Parameters.Add(new NpgsqlParameter { Value = parameter });
        }

        var value = await command.ExecuteScalarAsync();
        return value is DBNull ? null : value;
    }

    public async Task<long> DailyActiveAsync(string appVersion) =>
        (long?)(int?)await ScalarAsync(
            "SELECT installs FROM zaghlol.daily_active_counts WHERE day = $1 AND app_version = $2",
            DateOnly.FromDateTime(Clock.Now.UtcDateTime),
            appVersion) ?? 0;

    private static void Decorate<T>(IServiceCollection services, Func<T, T> wrap)
        where T : class
    {
        var descriptor = services.Last(d => d.ServiceType == typeof(T));
        services.Remove(descriptor);
        services.AddSingleton(provider =>
        {
            var inner = descriptor.ImplementationInstance as T
                ?? descriptor.ImplementationFactory?.Invoke(provider) as T
                ?? (T)ActivatorUtilities.CreateInstance(provider, descriptor.ImplementationType!);
            return wrap(inner);
        });
    }

    private async Task SeedAsync()
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO zaghlol.catalog_categories (code, name_ar, name_en, icon, color, bucket, sort, version) VALUES
              ('dining', 'مطاعم', 'Dining', 'fork', '#0F7A55', 'wants', 1, 1),
              ('groceries', 'بقالة', 'Groceries', 'cart', '#0F7A55', 'needs', 2, 2);
            INSERT INTO zaghlol.catalog_versions (version, published_at, published_by, full_snapshot_url, full_snapshot_sha256) VALUES
              (1, @t, gen_random_uuid(), 'https://cdn.zaghlol.test/v1/catalog/1/full', decode(repeat('00', 32), 'hex')),
              (2, @t, gen_random_uuid(), 'https://cdn.zaghlol.test/v1/catalog/2/full', decode(repeat('00', 32), 'hex'));
            INSERT INTO zaghlol.feature_flags (key, enabled, rules, version, updated_at, updated_by)
              VALUES ('zakah', true, '{}'::jsonb, 1, @t, gen_random_uuid());
            INSERT INTO zaghlol.price_quotes (symbol, currency, price, per_unit, as_of, source, is_override, override_expires_at, feed_price, feed_as_of)
              VALUES ('XAU24_G', 'EGP', 4820, 'g', @t, 'fake', false, NULL, 4820, @t);
            INSERT INTO zaghlol.fx_rates (base, quote, rate, as_of, source) VALUES ('USD', 'EGP', 48.95, @t, 'fake');
            """,
            connection);
        command.Parameters.AddWithValue("t", PricesAsOf);
        await command.ExecuteNonQueryAsync();
    }
}

/// <summary>Fault switches the tests flip (always reset in a <c>finally</c>).</summary>
public sealed class SyncFaults
{
    public bool Catalog { get; set; }

    public bool Prices { get; set; }

    public bool Hasher { get; set; }

    public SwitchableEntitlementBlock Entitlement { get; } = new();
}

/// <summary>The entitlement extension point: nulls by default, a fixed result or a failure on demand; records what it was given.</summary>
public sealed class SwitchableEntitlementBlock : ISyncEntitlementBlock
{
    public bool Fail { get; set; }

    public SyncEntitlementResult Result { get; set; } = SyncEntitlementResult.None;

    public SyncEntitlementContext? LastContext { get; private set; }

    public Task<SyncEntitlementResult> ComposeAsync(SyncEntitlementContext context, CancellationToken cancellationToken)
    {
        LastContext = context;
        return Fail ? throw new InvalidOperationException("entitlement block down") : Task.FromResult(Result);
    }
}

internal sealed class FaultyCatalogReader(ICatalogReader inner, SyncFaults faults) : ICatalogReader
{
    public Task<CatalogVersionInfo?> FindVersionAsync(int version, CancellationToken cancellationToken) =>
        faults.Catalog ? throw new InvalidOperationException("catalog down") : inner.FindVersionAsync(version, cancellationToken);

    public Task<int> LatestVersionAsync(CancellationToken cancellationToken) =>
        faults.Catalog ? throw new InvalidOperationException("catalog down") : inner.LatestVersionAsync(cancellationToken);

    public Task<IReadOnlyList<CatalogOp>> DeltaAsync(int fromVersion, int toVersion, CancellationToken cancellationToken) =>
        inner.DeltaAsync(fromVersion, toVersion, cancellationToken);

    public Task<IReadOnlySet<string>> CategoryCodesAsync(CancellationToken cancellationToken) => inner.CategoryCodesAsync(cancellationToken);
}

internal sealed class FaultyPriceReader(IPriceReader inner, SyncFaults faults) : IPriceReader
{
    public Task<IReadOnlyList<PriceRow>> ListGoldAsync(CancellationToken cancellationToken) =>
        faults.Prices ? throw new InvalidOperationException("prices down") : inner.ListGoldAsync(cancellationToken);

    public Task<IReadOnlyList<FxRow>> ListFxAsync(CancellationToken cancellationToken) => inner.ListFxAsync(cancellationToken);
}

internal sealed class FaultyHasher(IInstallHasher inner, SyncFaults faults) : IInstallHasher
{
    public ValueTask<byte[]> HashAsync(InstallId installId, CancellationToken cancellationToken) =>
        faults.Hasher ? throw new KmsUnavailableException() : inner.HashAsync(installId, cancellationToken);
}
