using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Serilog;
using Serilog.Events;
using Zaghlol.Api.Signing;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Logging;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Signing;

/// <summary>An anchored 200 body for the test endpoints (the shape the six anchoring operations use).</summary>
internal sealed record AnchoredBody(
    [property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? TimeNonce,
    string Status) : IAnchoredResponse;

internal sealed record PlainBody(string Message, int Count);

/// <summary>
/// The real API pipeline (<see cref="ApiPipeline"/>) and KMS wiring over <see cref="FakeKms"/>, with test-only endpoints,
/// verbose logs captured by <see cref="CapturingSink"/> and every span captured by an <see cref="ActivityListener"/>.
/// </summary>
public sealed class SigningHostFixture : IAsyncLifetime, IDisposable
{
    public const string HandlerFailure = "test handler failure";

    public static readonly byte[] PartA = "{\"part\":\"a\","u8.ToArray();
    public static readonly byte[] PartB = "\"next\":\"b\"}"u8.ToArray();

    private readonly ConcurrentQueue<string> spans = new();
    private ActivityListener? listener;
    private WebApplication? app;

    public FakeKms Kms { get; } = FakeKms.CreateDefault();

    public CapturingSink LogSink { get; } = new();

    public IReadOnlyCollection<string> Spans => spans;

    public HttpClient Client { get; private set; } = null!;

    public ISigner Signer => app!.Services.GetRequiredService<ISigner>();

    public async Task InitializeAsync()
    {
        listener = new ActivityListener
        {
            ShouldListenTo = _ => true,
            Sample = (ref ActivityCreationOptions<ActivityContext> _) => ActivitySamplingResult.AllDataAndRecorded,
            ActivityStopped = activity => spans.Enqueue(Describe(activity)),
        };
        ActivitySource.AddActivityListener(listener);

        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = "Testing" });
        builder.WebHost.UseTestServer();
        builder.Configuration.AddInMemoryCollection(Kms.Settings());
        builder.Host.UseSerilog((_, _, logger) => logger
            .ConfigureZaghlol("api")
            .MinimumLevel.Verbose()
            .MinimumLevel.Override("Microsoft", LogEventLevel.Verbose)
            .MinimumLevel.Override("System", LogEventLevel.Verbose)
            .WriteTo.Sink(LogSink));
        builder.Services.AddZaghlolKms();
        Kms.Use(builder.Services);
        builder.Services.AddSingleton(new KmsCallPolicy { Timeout = TimeSpan.FromMilliseconds(200) });
        builder.Services.AddZaghlolHttp();

        app = builder.Build();
        app.UseZaghlolPipeline();
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

    }

    public void Dispose()
    {
        listener?.Dispose();
        Kms.Dispose();
    }

    private static void MapTestEndpoints(WebApplication app)
    {
        app.MapGet("/t/signed", () => TypedResults.Ok(new PlainBody("مرحبا zaghlol", 3))).RequireResponseSignature();
        app.MapGet("/t/signed-empty", () => TypedResults.Ok(new Dictionary<string, string>())).RequireResponseSignature();
        app.MapGet("/t/unsigned", () => TypedResults.Ok(new PlainBody("plain", 1)));
        app.MapGet("/t/signed-404", () => TypedResults.NotFound(new PlainBody("missing", 0))).RequireResponseSignature();
        app.MapGet("/t/signed-404-bodiless", () => TypedResults.NotFound()).RequireResponseSignature();
        app.MapGet("/t/signed-401-bodiless", () => TypedResults.Unauthorized()).RequireResponseSignature();
        app.MapGet("/t/signed-union-not-found", Results<Ok<PlainBody>, NotFound> () => TypedResults.NotFound()).RequireResponseSignature();
        app.MapGet("/t/signed-409", () => TypedResults.Conflict(new PlainBody("conflict", 0))).RequireResponseSignature();

        app.MapGet("/t/signed-body-stream", async (HttpContext context) =>
        {
            context.Response.ContentType = "application/json";
            await context.Response.StartAsync();
            await context.Response.Body.WriteAsync(PartA);
            await context.Response.Body.FlushAsync();
            await context.Response.Body.WriteAsync(PartB);
        }).RequireResponseSignature();

        app.MapGet("/t/signed-body-writer", async (HttpContext context) =>
        {
            context.Response.ContentType = "application/json";
            await context.Response.BodyWriter.WriteAsync(PartA);
            await context.Response.BodyWriter.FlushAsync();

            // Left unflushed on purpose: the middleware must complete the writer before signing.
            PartB.CopyTo(context.Response.BodyWriter.GetSpan(PartB.Length));
            context.Response.BodyWriter.Advance(PartB.Length);
        }).RequireResponseSignature();

        app.MapGet("/t/signed-spoof", (HttpContext context) =>
        {
            context.Response.Headers[ResponseSigningMiddleware.HeaderName] = "kid=s0000t; alg=ES256; sig=forged";
            return TypedResults.Ok(new PlainBody("spoof", 1));
        }).RequireResponseSignature();

        app.MapGet("/t/signed-throws", async (HttpContext context) =>
        {
            await context.Response.Body.WriteAsync("{\"partial\":"u8.ToArray());
            throw new InvalidOperationException(HandlerFailure);
        }).RequireResponseSignature();

        app.MapGet("/t/signed-size/{bytes:int}", async (int bytes, HttpContext context) =>
        {
            var chunk = new byte[64 * 1024];
            Array.Fill(chunk, (byte)'a');
            for (var left = bytes; left > 0; left -= chunk.Length)
            {
                await context.Response.Body.WriteAsync(chunk.AsMemory(0, Math.Min(left, chunk.Length)));
            }
        }).RequireResponseSignature();

        app.MapGet("/t/anchored", (HttpContext context) => TypedResults.Ok(new AnchoredBody(context.TimeNonce(), "ok")))
            .WithTimeNonce()
            .RequireResponseSignature();

        app.MapGet("/t/anchored-union", Results<Ok<AnchoredBody>, NotFound> (HttpContext context) =>
                TypedResults.Ok(new AnchoredBody(context.TimeNonce(), "union")))
            .WithTimeNonce()
            .RequireResponseSignature();

        app.MapGet("/t/anchored-wrong", () => TypedResults.Ok(new AnchoredBody("AAAAAAAAAAAAAAAAAAAAAA", "wrong")))
            .WithTimeNonce()
            .RequireResponseSignature();

        app.MapGet("/t/anchored-json-wrong", () => TypedResults.Json(new AnchoredBody("AAAAAAAAAAAAAAAAAAAAAA", "json")))
            .WithTimeNonce()
            .RequireResponseSignature();

        app.MapGet("/t/anchored-throws", IResult (HttpContext context) =>
            {
                _ = context.TimeNonce();
                throw new InvalidOperationException(HandlerFailure);
            })
            .WithTimeNonce()
            .RequireResponseSignature();
    }

    private static string Describe(Activity activity)
    {
        var text = new StringBuilder()
            .Append(activity.Source.Name).Append('|')
            .Append(activity.OperationName).Append('|')
            .Append(activity.DisplayName).Append('|')
            .Append(activity.StatusDescription).Append('|');
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

        return text.ToString();
    }
}
