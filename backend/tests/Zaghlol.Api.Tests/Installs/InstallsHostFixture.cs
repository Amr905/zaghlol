using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Serilog;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Endpoints.V1;
using Zaghlol.Api.Idempotency;
using Zaghlol.Api.Json;
using Zaghlol.Api.Signing;
using Zaghlol.Domain;
using Zaghlol.Infrastructure;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Logging;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Persistence.Entities;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Installs;

/// <summary>A clock the tests move; timers stay real.</summary>
public sealed class ManualClock : TimeProvider
{
    // Whole seconds, so values round-trip through PostgreSQL (microseconds) and the second-precision serverTime unchanged.
    private long ticks = WholeSecond(DateTimeOffset.UtcNow.UtcTicks);

    public DateTimeOffset Now => new(Interlocked.Read(ref ticks), TimeSpan.Zero);

    public override DateTimeOffset GetUtcNow() => Now;

    public void Advance(TimeSpan by) => Interlocked.Add(ref ticks, by.Ticks);

    private static long WholeSecond(long utcTicks) => utcTicks - (utcTicks % TimeSpan.TicksPerSecond);
}

/// <summary>The real pseudonymizer, or a failing one while <see cref="Fail"/> is set (F7).</summary>
public sealed class SwitchablePseudonymizer(LogPseudonymizer inner) : ILogPseudonymizer
{
    private volatile bool fail;

    public bool Fail
    {
        get => fail;
        set => fail = value;
    }

    public ValueTask<string> InstallHashAsync(InstallId installId, CancellationToken cancellationToken) =>
        fail ? throw new KmsUnavailableException() : inner.InstallHashAsync(installId, cancellationToken);
}

/// <summary>
/// The real pipeline (<c>ApiPipeline</c>), install endpoints and stores over a migrated PostgreSQL 17 and the fake KMS, in the
/// <c>Testing</c> environment, with a movable clock, captured logs and test-only routes: an install-scoped
/// <c>GET /v1/t/whoami</c>, an idempotent <c>POST /v1/t/idem</c> (operation <c>verifyPurchase</c>) and
/// <c>POST /v1/t/rotate</c>. <c>X-Test-Peer</c> sets the connection's remote address before the forwarded-headers rule.
/// </summary>
public class InstallsHostFixture : IAsyncLifetime, IDisposable
{
    public const string PeerHeader = "X-Test-Peer";
    public const string TrustedProxy = "10.9.9.9";

    private readonly SemaphoreSlim gate = new(0);
    private WebApplication? app;
    private int runs;

    public FakeKms Kms { get; } = FakeKms.CreateDefault();

    public ManualClock Clock { get; } = new();

    public CapturingSink LogSink { get; } = new();

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public HttpClient Client { get; private set; } = null!;

    public IServiceProvider Services => app!.Services;

    public SwitchablePseudonymizer Pseudonymizer => (SwitchablePseudonymizer)app!.Services.GetRequiredService<ILogPseudonymizer>();

    /// <summary>How often the idempotent test handler has run.</summary>
    public int Runs => Volatile.Read(ref runs);

    /// <summary>Signalled when a <c>slow</c> idempotent request is inside its handler.</summary>
    public SemaphoreSlim Entered { get; } = new(0);

    protected virtual bool WithDatabase => true;

    protected virtual IReadOnlyDictionary<string, string?> Settings { get; } = new Dictionary<string, string?>
    {
        ["RateLimits:PerNetwork:TokenLimit"] = "100000",
        ["RateLimits:PerNetwork:TokensPerPeriod"] = "100000",
        ["RateLimits:PerNetwork:PeriodSeconds"] = "60",
        ["RateLimits:Register:TokenLimit"] = "100000",
        ["RateLimits:Register:TokensPerPeriod"] = "100000",
        ["RateLimits:Register:PeriodSeconds"] = "60",
        ["RateLimits:PerToken:TokenLimit"] = "20",
        ["RateLimits:PerToken:TokensPerPeriod"] = "1",
        ["RateLimits:PerToken:PeriodSeconds"] = "3600",
    };

    /// <summary>Extra services of a derived host (registered after the install services).</summary>
    protected virtual void ConfigureServices(IServiceCollection services)
    {
    }

    /// <summary>Extra endpoints of a derived host (mapped after the install endpoints).</summary>
    protected virtual void MapEndpoints(WebApplication application)
    {
    }

    /// <summary>Middleware of a derived host that must run before the pipeline (T-133: the body-read spy).</summary>
    protected virtual void UseBeforePipeline(WebApplication application)
    {
    }

    /// <summary>The App connection string (a derived host may shrink the pool).</summary>
    protected virtual string AppConnectionString(string api) => api;

    /// <summary>Lets one <c>slow</c> idempotent request leave its handler.</summary>
    public void Release() => gate.Release();

    public async Task InitializeAsync()
    {
        const string Unreachable = "Host=127.0.0.1;Port=1;Database=none;Username=none";
        if (WithDatabase)
        {
            Database = await ZaghlolTestDatabase.StartAsync();
        }

        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = "Testing" });
        builder.WebHost.UseTestServer();
        var settings = new Dictionary<string, string?>(Kms.Settings())
        {
            ["ConnectionStrings:App"] = WithDatabase ? AppConnectionString(Database.Api) : Unreachable,
            ["ForwardedHeaders:KnownProxies:0"] = TrustedProxy,
        };
        foreach (var (key, value) in Settings)
        {
            settings[key] = value;
        }

        builder.Configuration.AddInMemoryCollection(settings);
        builder.Host.UseSerilog((_, _, logger) => logger.ConfigureZaghlol("api").WriteTo.Sink(LogSink));

        builder.Services.AddSingleton<TimeProvider>(Clock);
        builder.Services.AddInfrastructure();
        builder.Services.AddZaghlolKms();
        Kms.Use(builder.Services);
        builder.Services.AddZaghlolDatabase(DatabaseRole.App);
        builder.Services.AddZaghlolHttp();
        builder.Services.AddZaghlolLogPseudonymizer();
        builder.Services.AddSingleton<LogPseudonymizer>();
        builder.Services.RemoveAll<ILogPseudonymizer>();
        builder.Services.AddSingleton<ILogPseudonymizer, SwitchablePseudonymizer>();
        builder.Services.AddZaghlolInstalls();
        ConfigureServices(builder.Services);

        app = builder.Build();
        app.Use(async (context, next) =>
        {
            if (context.Request.Headers.TryGetValue(PeerHeader, out var peer))
            {
                context.Connection.RemoteIpAddress = IPAddress.Parse(peer.ToString());
            }

            await next(context);
        });
        UseBeforePipeline(app);
        app.UseZaghlolPipeline();
        app.MapInstalls();
        MapEndpoints(app);
        MapTestEndpoints(app);
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

        if (WithDatabase && Database is not null)
        {
            await Database.DisposeAsync();
        }
    }

    public void Dispose()
    {
        Dispose(true);
        GC.SuppressFinalize(this);
    }

    protected virtual void Dispose(bool disposing)
    {
        if (disposing)
        {
            Kms.Dispose();
            gate.Dispose();
            Entered.Dispose();
        }
    }

    /// <summary>A fresh lowercase UUID v4.</summary>
    public static string NewInstallId() => Guid.NewGuid().ToString("D");

    /// <summary>A fresh 26-character Crockford ULID-shaped key.</summary>
    public static string NewKey()
    {
        const string Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
        var bytes = System.Security.Cryptography.RandomNumberGenerator.GetBytes(26);
        return string.Concat(bytes.Select(b => Alphabet[b % 32]));
    }

    public static string InstallBody(string installId, string platform = "android", string appVersion = "1.0.0") =>
        $"{{\"installId\":\"{installId}\",\"platform\":\"{platform}\",\"appVersion\":\"{appVersion}\"}}";

    public async Task<HttpResponseMessage> RegisterAsync(string body, string? key, string? peer = null, string mediaType = "application/json")
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/installs");
        request.Content = new StringContent(body, Encoding.UTF8);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue(mediaType);
        if (key is not null)
        {
            request.Headers.Add(IdempotencyKeys.HeaderName, key);
        }

        if (peer is not null)
        {
            request.Headers.Add(PeerHeader, peer);
        }

        return await Client.SendAsync(request);
    }

    /// <summary>Registers a new install; returns its ID and token.</summary>
    public async Task<(string InstallId, string Token)> NewInstallAsync()
    {
        var installId = NewInstallId();
        using var response = await RegisterAsync(InstallBody(installId), NewKey());
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (installId, await TokenOf(response));
    }

    public static async Task<string> TokenOf(HttpResponseMessage response)
    {
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return json.RootElement.GetProperty("installToken").GetString()!;
    }

    public async Task<HttpResponseMessage> SendAsync(
        HttpMethod method,
        string path,
        string? token,
        string? body = null,
        string? key = null,
        string? installHeader = null,
        string? authorization = null)
    {
        using var request = new HttpRequestMessage(method, path);
        if (authorization is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", authorization);
        }
        else if (token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        }

        if (body is not null)
        {
            request.Content = new StringContent(body, Encoding.UTF8, "application/json");
        }

        if (key is not null)
        {
            request.Headers.Add(IdempotencyKeys.HeaderName, key);
        }

        if (installHeader is not null)
        {
            request.Headers.TryAddWithoutValidation(InstallTokenAuthentication.InstallHeader, installHeader);
        }

        return await Client.SendAsync(request);
    }

    private void MapTestEndpoints(WebApplication application)
    {
        var scoped = application.MapInstallScoped();
        scoped.MapGet("/t/whoami", (HttpContext context) =>
            TypedResults.Ok(new Dictionary<string, string> { ["installId"] = InstallTokenAuthentication.InstallIdOf(context.User).ToString() }));

        scoped.MapPost("/t/rotate", async (HttpContext context, IInstallTokenRotator rotator) =>
            await rotator.RotateAsync(context, context.RequestAborted) is { } token
                ? Results.Ok(new Dictionary<string, string> { ["rotateInstallToken"] = token.Reveal() })
                : Results.Conflict());

        // The idempotent stand-in for verify/sign-in: the body's "mode" picks the outcome; "run" counts handler runs.
        scoped.MapPost("/t/idem", async (HttpContext context) =>
            {
                var body = await StrictJson.ReadBodyAsync(context);
                using var json = JsonDocument.Parse(body.Bytes);
                var mode = json.RootElement.GetProperty("mode").GetString();
                var marker = json.RootElement.TryGetProperty("marker", out var m) ? m.GetString() : null;
                var run = Interlocked.Increment(ref runs);
                if (mode == "slow")
                {
                    Entered.Release();
                    await gate.WaitAsync(TimeSpan.FromSeconds(30));
                }

                var payload = new Dictionary<string, object?> { ["run"] = run, ["marker"] = marker };
                return mode switch
                {
                    "conflict" => Results.Json(payload, statusCode: StatusCodes.Status409Conflict),
                    "unprocessable" => Results.Json(payload, statusCode: StatusCodes.Status422UnprocessableEntity),
                    "tooMany" => Results.Json(payload, statusCode: StatusCodes.Status429TooManyRequests),
                    "unavailable" => Results.Json(payload, statusCode: StatusCodes.Status503ServiceUnavailable),
                    "throw" => throw new InvalidOperationException("test handler failure"),
                    "rotate" => Results.Json(new Dictionary<string, object?> { ["run"] = run, ["rotateInstallToken"] = "rotated-test-token" }),
                    _ => Results.Json(payload),
                };
            })
            .WithTimeNonce()
            .WithIdempotency(IdempotentOperation.VerifyPurchase)
            .RequireResponseSignature();

        application.MapGet("/t/ping", () => TypedResults.Ok(new Dictionary<string, string> { ["ok"] = "yes" }));
    }
}

/// <summary>No database and small buckets: per network 5 an hour, registration 3 an hour.</summary>
public sealed class RateLimitHostFixture : InstallsHostFixture
{
    protected override bool WithDatabase => false;

    protected override IReadOnlyDictionary<string, string?> Settings { get; } = new Dictionary<string, string?>
    {
        ["RateLimits:PerNetwork:TokenLimit"] = "5",
        ["RateLimits:PerNetwork:TokensPerPeriod"] = "5",
        ["RateLimits:PerNetwork:PeriodSeconds"] = "3600",
        ["RateLimits:Register:TokenLimit"] = "3",
        ["RateLimits:Register:TokensPerPeriod"] = "3",
        ["RateLimits:Register:PeriodSeconds"] = "3600",
    };
}
