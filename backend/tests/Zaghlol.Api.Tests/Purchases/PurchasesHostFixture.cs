using System.Collections.Concurrent;
using System.Diagnostics.Metrics;
using System.Net;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Npgsql;
using Zaghlol.Api.Endpoints.V1;
using Zaghlol.Api.Signing;
using Zaghlol.Api.Tests.Installs;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Purchases;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Purchases;

/// <summary>
/// The install host plus <c>POST /v1/purchases/verify</c> (T-130) over PostgreSQL 17 and a WireMock Play Developer API, with the
/// real pipeline (install token, time nonce, idempotency claims, response signing). <see cref="SweeperAsync"/> builds the worker
/// side (Worker login) against the same database and the same Play stand-in.
/// </summary>
public class PurchasesHostFixture : InstallsHostFixture
{
    private readonly MeterListener meters = new();
    private int metersStarted;

    public PlayWireMock Play { get; } = new();

    /// <summary>The grant step: grants for the installs a test opts in, nothing for the rest (like the T-130 placeholder).</summary>
    public GrantingVerifyGrant Grant { get; } = new();

    public ConcurrentQueue<(string Instrument, long Value, Dictionary<string, string?> Tags)> Measurements { get; } = new();

    protected override IReadOnlyDictionary<string, string?> Settings
    {
        get
        {
            var settings = new Dictionary<string, string?>(base.Settings);
            foreach (var (key, value) in Play.Settings())
            {
                settings[key] = value;
            }

            settings["RateLimits:PerToken:TokenLimit"] = "1000";
            settings["RateLimits:PerToken:TokensPerPeriod"] = "1000";
            return settings;
        }
    }

    public static string Nonce() => System.Buffers.Text.Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(16));

    public static string NewPlayToken() => "tok." + Guid.NewGuid().ToString("N") + "_" + Guid.NewGuid().ToString("N");

    public static string AndroidBody(string productId, string token) =>
        "{\"platform\":\"android\",\"productId\":\"" + productId + "\",\"purchaseToken\":\"" + token + "\"}";

    public void StartMeters()
    {
        if (Interlocked.Exchange(ref metersStarted, 1) == 1)
        {
            return;
        }

        meters.InstrumentPublished = (instrument, listener) =>
        {
            if (instrument.Meter.Name == ZaghlolMetrics.MeterName)
            {
                listener.EnableMeasurementEvents(instrument);
            }
        };
        meters.SetMeasurementEventCallback<long>((instrument, value, tags, _) =>
            Measurements.Enqueue((instrument.Name, value, tags.ToArray().ToDictionary(t => t.Key, t => t.Value as string, StringComparer.Ordinal))));
        meters.Start();
    }

    public void RecordGauges() => meters.RecordObservableInstruments();

    public async Task<HttpResponseMessage> VerifyAsync(string token, string body, string? key = null, string? nonce = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/purchases/verify");
        request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        request.Headers.Add(Idempotency.IdempotencyKeys.HeaderName, key ?? NewKey());
        if (nonce is not null)
        {
            request.Headers.Add(TimeNonceFilter.HeaderName, nonce);
        }

        request.Content = new StringContent(body, System.Text.Encoding.UTF8, "application/json");
        return await Client.SendAsync(request);
    }

    /// <summary>The purchases row of a token (superuser read), or <c>null</c>.</summary>
    public async Task<(Guid Id, string State, bool Acknowledged, Guid? InstallId, string Environment, string? Linked)?> RowAsync(string playToken)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "SELECT id, state, acknowledged, install_id, environment, linked_purchase_token FROM zaghlol.purchases WHERE store = 'google_play' AND store_key = @k",
            connection);
        command.Parameters.AddWithValue("k", playToken);
        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
        {
            return null;
        }

        return (reader.GetGuid(0), reader.GetString(1), reader.GetBoolean(2), reader.IsDBNull(3) ? null : reader.GetGuid(3), reader.GetString(4), reader.IsDBNull(5) ? null : reader.GetString(5));
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

    /// <summary>The worker side: the acknowledge sweeper job on the Worker login, against the same database and Play stand-in.</summary>
    public ServiceProvider SweeperServices()
    {
        var settings = new Dictionary<string, string?>(Play.Settings()) { ["ConnectionStrings:Worker"] = Database.Worker };
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(settings).Build();
        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(configuration);
        services.AddSingleton<IHostEnvironment>(new TestingEnvironment());
        services.AddSingleton<TimeProvider>(Clock);
        services.AddLogging();
        services.AddInfrastructure();
        services.AddZaghlolDatabase(DatabaseRole.Worker);
        services.AddZaghlolPlayAckSweeper();
        return services.BuildServiceProvider();
    }

    public async Task<AckSweepRun> SweeperAsync()
    {
        await using var services = SweeperServices();
        return await services.GetRequiredService<PlayAckSweepJob>().RunOnceAsync(CancellationToken.None);
    }

    protected override void ConfigureServices(IServiceCollection services)
    {
        services.AddSingleton<IVerifyGrant>(Grant);
        services.AddZaghlolGooglePlay();
        services.AddZaghlolPurchaseVerification();
    }

    protected override void MapEndpoints(WebApplication application) => application.MapPurchases();

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            meters.Dispose();
            Play.Dispose();
        }

        base.Dispose(disposing);
    }

    private sealed class TestingEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = "Testing";

        public string ApplicationName { get; set; } = "t";

        public string ContentRootPath { get; set; } = "/";

        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = null!;
    }
}

/// <summary>The S-2 host: the App pool capped at 3 connections, 5 s pool timeout.</summary>
public sealed class SmallPoolPurchasesHostFixture : PurchasesHostFixture
{
    protected override string AppConnectionString(string api) => api + ";Maximum Pool Size=3;Timeout=5";
}
