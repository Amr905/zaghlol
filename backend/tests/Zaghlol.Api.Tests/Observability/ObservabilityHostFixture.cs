#pragma warning disable CA1848, CA2254 // Test endpoints log through the logger on purpose, with values in placeholders.

using System.Buffers.Text;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Diagnostics.Metrics;
using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Npgsql;
using OpenTelemetry;
using OpenTelemetry.Trace;
using Serilog;
using Serilog.Events;
using Zaghlol.Api.Observability;
using Zaghlol.Api.Signing;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Logging;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Observability;

internal sealed record OwnershipCheck(Sensitive<string> OrderId);

internal sealed record SeatBody(Sensitive<string[]> SeatKeys, OwnershipCheck OwnershipCheck);

/// <summary>A writer that can be read while the logger writes to it.</summary>
internal sealed class SynchronizedWriter : TextWriter
{
    private readonly StringBuilder text = new();
    private readonly object gate = new();

    public override Encoding Encoding => Encoding.UTF8;

    public override void Write(char value)
    {
        lock (gate)
        {
            text.Append(value);
        }
    }

    public override void Write(string? value)
    {
        lock (gate)
        {
            text.Append(value);
        }
    }

    public override string ToString()
    {
        lock (gate)
        {
            return text.ToString();
        }
    }
}

/// <summary>Retries once on a 5xx, logging the URI through a placeholder (which must not reach the output).</summary>
internal sealed class RetryOnceHandler(Microsoft.Extensions.Logging.ILogger logger) : DelegatingHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var response = await base.SendAsync(request, cancellationToken);
        if ((int)response.StatusCode < 500)
        {
            return response;
        }

        response.Dispose();
        logger.LogWarning("Retrying {Uri} after {Status}", request.RequestUri, (int)response.StatusCode);
        using var retry = new HttpRequestMessage(request.Method, request.RequestUri);
        foreach (var option in request.Options)
        {
            ((IDictionary<string, object?>)retry.Options).Add(option);
        }

        return await base.SendAsync(retry, cancellationToken);
    }
}

/// <summary>
/// T-138 sentinel harness: the real API pipeline, logger configuration and telemetry (<c>Production</c> environment) over a
/// fake KMS, with one random sentinel placed in a query, a path key, outbound Play URLs, a 303 <c>Location</c>, the
/// <c>Zaghlol-Time-Nonce</c> and <c>Idempotency-Key</c> headers, a body with <c>seatKeys</c> and an order ID, exception
/// messages and a database unique violation. It captures the final log bytes, the exported spans (after the redacting
/// processor) and every metric tag.
/// </summary>
public abstract class ObservabilityHostFixture : IAsyncLifetime, IDisposable
{
    public const string PlayTokenTemplate = "/androidpublisher/v3/applications/{packageName}/purchases/subscriptionsv2/tokens/{token}";
    public const string PlayOrderTemplate = "/androidpublisher/v3/applications/{packageName}/orders/{orderId}";

    private readonly SynchronizedWriter log = new();
    private readonly List<Activity> exported = [];
    private readonly ConcurrentQueue<string> metricTags = new();
    private readonly ConcurrentDictionary<string, int> playAttempts = new(StringComparer.Ordinal);
    private readonly Lazy<Task> scenario;
    private MeterListener? meterListener;
    private WebApplication? app;
    private WebApplication? play;
    private ZaghlolTestDatabase? database;
    private NpgsqlDataSource? dataSource;

    protected ObservabilityHostFixture() => scenario = new Lazy<Task>(RunScenarioAsync);

    /// <summary>A 22-character canonical time nonce, so the same sentinel can travel in the nonce header too.</summary>
    public string Sentinel { get; } = "ZgS" + Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(13)) + "w";

    protected abstract bool Verbose { get; }

    protected abstract bool WithDatabase { get; }

    public FakeKms Kms { get; } = FakeKms.CreateDefault();

    public IServiceProvider Services => app!.Services;

    public Dictionary<string, HttpStatusCode> Statuses { get; } = new(StringComparer.Ordinal);

    public string LogOutput => log.ToString();

    public IReadOnlyList<string> LogLines => LogOutput.Split('\n', StringSplitOptions.RemoveEmptyEntries);

    public int RequestsSent { get; private set; }

    public IReadOnlyList<Activity> Spans
    {
        get
        {
            lock (exported)
            {
                return [.. exported];
            }
        }
    }

    public IReadOnlyList<string> MetricTags => [.. metricTags];

    public int PlayAttemptsFor(string route) => playAttempts.GetValueOrDefault(route);

    public Task EnsureScenarioAsync() => scenario.Value;

    public async Task InitializeAsync()
    {
        if (WithDatabase)
        {
            database = await ZaghlolTestDatabase.StartAsync();
            await using var setup = NpgsqlDataSource.Create(database.Superuser);
            await using var command = setup.CreateCommand("CREATE TABLE t138_dup (k text PRIMARY KEY)");
            await command.ExecuteNonQueryAsync();
        }

        await StartPlayAsync();

        meterListener = new MeterListener();
        meterListener.InstrumentPublished = (instrument, l) => l.EnableMeasurementEvents(instrument);
        meterListener.SetMeasurementEventCallback<long>((i, v, t, _) => RecordMetric(i, v, t));
        meterListener.SetMeasurementEventCallback<double>((i, v, t, _) => RecordMetric(i, v, t));
        meterListener.SetMeasurementEventCallback<int>((i, v, t, _) => RecordMetric(i, v, t));
        meterListener.Start();

        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = "Production" });
        builder.WebHost.UseTestServer();
        builder.Configuration.AddInMemoryCollection(Kms.Settings());
        builder.Host.UseSerilog((_, _, logger) =>
        {
            logger.ConfigureZaghlol("api", log);
            if (Verbose)
            {
                logger.MinimumLevel.Verbose()
                    .MinimumLevel.Override("Microsoft", LogEventLevel.Verbose)
                    .MinimumLevel.Override("System", LogEventLevel.Verbose);
                foreach (var category in LoggingConfigurationExtensions.QuietCategories)
                {
                    logger.MinimumLevel.Override(category, LogEventLevel.Verbose);
                }
            }
        });
        builder.Services.AddZaghlolKms();
        Kms.Use(builder.Services);
        builder.Services.AddZaghlolHttp();
        builder.Services.AddZaghlolApiTelemetry(builder.Configuration, builder.Environment);
        builder.Services.AddOpenTelemetry().WithTracing(tracing => tracing.AddInMemoryExporter(exported));
        builder.Services.AddZaghlolLogPseudonymizer();
        var playBase = new Uri(play!.Urls.First());
        builder.Services.AddHttpClient("google-play", client => client.BaseAddress = playBase)
            .AddHttpMessageHandler(sp => new RetryOnceHandler(sp.GetRequiredService<ILoggerFactory>().CreateLogger("Test.Retry")));

        app = builder.Build();
        app.UseZaghlolPipeline();
        if (database is not null)
        {
            dataSource = new NpgsqlDataSourceBuilder(database.Superuser)
                .UseLoggerFactory(app.Services.GetRequiredService<ILoggerFactory>())
                .Build();
        }

        MapTestEndpoints(app);
        await app.StartAsync();
    }

    public void Dispose()
    {
        meterListener?.Dispose();
        Kms.Dispose();
    }

    public async Task DisposeAsync()
    {
        if (app is not null)
        {
            await app.StopAsync();
            await app.DisposeAsync();
        }

        if (play is not null)
        {
            await play.StopAsync();
            await play.DisposeAsync();
        }

        if (dataSource is not null)
        {
            await dataSource.DisposeAsync();
        }

        if (database is not null)
        {
            await database.DisposeAsync();
        }
    }

    private async Task StartPlayAsync()
    {
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        play = builder.Build();

        // The first attempt of each route is a 503, so the client's retry handler runs.
        play.MapGet("/androidpublisher/v3/applications/{packageName}/purchases/subscriptionsv2/tokens/{token}", () => Attempt("token"));
        play.MapGet("/androidpublisher/v3/applications/{packageName}/orders/{orderId}", () => Attempt("order"));
        await play.StartAsync();
    }

    private IResult Attempt(string route) =>
        playAttempts.AddOrUpdate(route, 1, (_, n) => n + 1) == 1
            ? Results.StatusCode(StatusCodes.Status503ServiceUnavailable)
            : Results.Ok();

    private void MapTestEndpoints(WebApplication host)
    {
        var sentinel = Sentinel;

        host.MapGet("/test/items/{key}", (string key) => TypedResults.Ok(new Zaghlol.Api.Tests.Signing.PlainBody("item", key.Length)));

        host.MapGet("/test/outbound", async (IHttpClientFactory clients, HttpContext context) =>
        {
            var client = clients.CreateClient("google-play");
            using var token = new HttpRequestMessage(HttpMethod.Get, "/androidpublisher/v3/applications/com.example/purchases/subscriptionsv2/tokens/" + sentinel);
            token.SetUrlTemplate(PlayTokenTemplate);
            using var tokenResponse = await client.SendAsync(token, context.RequestAborted);
            using var order = new HttpRequestMessage(HttpMethod.Get, "/androidpublisher/v3/applications/com.example/orders/" + sentinel);
            order.SetUrlTemplate(PlayOrderTemplate);
            using var orderResponse = await client.SendAsync(order, context.RequestAborted);
            return Results.StatusCode((int)tokenResponse.StatusCode == 200 && (int)orderResponse.StatusCode == 200 ? 200 : 502);
        });

        // The Apple callback's 303 carries tokens in the Location query.
        host.MapGet("/test/redirect", (HttpContext context) =>
        {
            context.Response.Headers.Location = "/test/after?code=" + sentinel;
            return Results.StatusCode(StatusCodes.Status303SeeOther);
        });

        host.MapGet("/t/anchored", (HttpContext context) => TypedResults.Ok(new Zaghlol.Api.Tests.Signing.AnchoredBody(context.TimeNonce(), "ok")))
            .WithTimeNonce()
            .RequireResponseSignature();

        host.MapPost("/test/idem", () => Results.NoContent());

        host.MapPost("/test/body", (SeatBody body, ILoggerFactory loggers) =>
        {
            var logger = loggers.CreateLogger("Test.Body");
            logger.LogInformation("Received {@Body} and {Body} with {SeatKeys}", body, body, body.SeatKeys);
            return Results.Ok();
        });

        host.MapPost("/test/body-throws", IResult (SeatBody body) => throw new InvalidOperationException($"rejected {body} {body.OwnershipCheck.OrderId} {body.SeatKeys}"));

        host.MapGet("/test/throws", IResult () => throw new InvalidOperationException("order " + sentinel));

        host.MapGet("/test/db-duplicate", async () =>
        {
            for (var i = 0; i < 2; i++)
            {
                await using var command = dataSource!.CreateCommand("INSERT INTO t138_dup (k) VALUES (@k)");
                command.Parameters.AddWithValue("k", sentinel);
                await command.ExecuteNonQueryAsync();
            }

            return Results.Ok();
        });
    }

    private async Task RunScenarioAsync()
    {
        using var client = app!.GetTestClient();
        var s = Sentinel;

        await SendAsync(client, "query", HttpMethod.Get, "/test/items/plain?q=" + s);
        await SendAsync(client, "path", HttpMethod.Get, "/test/items/" + s);
        await SendAsync(client, "outbound", HttpMethod.Get, "/test/outbound");
        await SendAsync(client, "redirect", HttpMethod.Get, "/test/redirect");
        await SendAsync(client, "nonce", HttpMethod.Get, "/t/anchored", headers: new() { ["Zaghlol-Time-Nonce"] = s });
        await SendAsync(client, "nonce-malformed", HttpMethod.Get, "/t/anchored", headers: new() { ["Zaghlol-Time-Nonce"] = s + "=" });
        await SendAsync(client, "idempotency", HttpMethod.Post, "/test/idem", headers: new() { ["Idempotency-Key"] = s });

        var json = "{\"seatKeys\":[\"" + s + "\",\"" + s + "-2\"],\"ownershipCheck\":{\"orderId\":\"" + s + "\"}}";
        await SendAsync(client, "body", HttpMethod.Post, "/test/body", json);
        await SendAsync(client, "body-throws", HttpMethod.Post, "/test/body-throws", json);
        await SendAsync(client, "throws", HttpMethod.Get, "/test/throws");
        if (database is not null)
        {
            await SendAsync(client, "database", HttpMethod.Get, "/test/db-duplicate");
        }

        await SendAsync(client, "unmatched", HttpMethod.Get, "/nope/" + s + "?x=" + s);

        // The request log and the request span are written as each request finishes: wait until every request is logged.
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (DateTime.UtcNow < deadline
               && (LogLines.Count(l => l.Contains("\"msg\":\"request completed\"", StringComparison.Ordinal)) < RequestsSent
                   || Spans.Count(a => a.Kind == ActivityKind.Server && a.Source.Name == "Microsoft.AspNetCore") < RequestsSent))
        {
            await Task.Delay(50);
        }

        await Task.Delay(250);
    }

    private async Task SendAsync(HttpClient client, string name, HttpMethod method, string path, string? body = null, Dictionary<string, string>? headers = null)
    {
        using var request = new HttpRequestMessage(method, new Uri(path, UriKind.Relative));
        if (body is not null)
        {
            request.Content = new StringContent(body, Encoding.UTF8, "application/json");
        }

        foreach (var (key, value) in headers ?? new Dictionary<string, string>())
        {
            request.Headers.TryAddWithoutValidation(key, value);
        }

        using var response = await client.SendAsync(request);
        _ = await response.Content.ReadAsStringAsync();
        Statuses[name] = response.StatusCode;
        RequestsSent++;
    }

    private void RecordMetric(Instrument instrument, double value, ReadOnlySpan<KeyValuePair<string, object?>> tags)
    {
        var text = new StringBuilder(instrument.Meter.Name).Append('|').Append(instrument.Name).Append('|')
            .Append(value.ToString(CultureInfo.InvariantCulture)).Append('|');
        foreach (var tag in tags)
        {
            text.Append(tag.Key).Append('=').Append(Convert.ToString(tag.Value, CultureInfo.InvariantCulture)).Append(';');
        }

        metricTags.Enqueue(text.ToString());
    }

    /// <summary>Everything a span can carry out of the process.</summary>
    public static string Describe(Activity activity)
    {
        var text = new StringBuilder()
            .Append(activity.Source.Name).Append('|')
            .Append(activity.OperationName).Append('|')
            .Append(activity.DisplayName).Append('|')
            .Append(activity.StatusDescription).Append('|')
            .Append(activity.TraceStateString).Append('|');
        foreach (var (key, value) in activity.TagObjects)
        {
            text.Append(key).Append('=').Append(Convert.ToString(value, CultureInfo.InvariantCulture)).Append(';');
        }

        foreach (var (key, value) in activity.Baggage)
        {
            text.Append("baggage:").Append(key).Append('=').Append(value).Append(';');
        }

        foreach (var activityEvent in activity.Events)
        {
            text.Append("event:").Append(activityEvent.Name);
            foreach (var (key, value) in activityEvent.Tags)
            {
                text.Append(';').Append(key).Append('=').Append(Convert.ToString(value, CultureInfo.InvariantCulture));
            }

            text.Append(';');
        }

        foreach (var link in activity.Links)
        {
            text.Append("link:").Append(link.Context.TraceId).Append(';');
        }

        return text.ToString();
    }
}

/// <summary>Production log levels, with the database cases.</summary>
public sealed class ProductionLevelsFixture : ObservabilityHostFixture
{
    protected override bool Verbose => false;

    protected override bool WithDatabase => true;
}

/// <summary>Every category at Verbose: the formatter alone must keep the framework's URL-bearing messages out.</summary>
public sealed class VerboseLevelsFixture : ObservabilityHostFixture
{
    protected override bool Verbose => true;

    protected override bool WithDatabase => false;
}
