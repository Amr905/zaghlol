using System.Diagnostics;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using OpenTelemetry;
using OpenTelemetry.Trace;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.Tests.Observability;

/// <summary>
/// Code review round 1 (tests M1): the span exporters run after <see cref="RedactingActivityProcessor"/>. The probe is a
/// processor that copies what it sees in <c>OnEnd</c> (a live <c>Activity</c> reference would look redacted later), and it is
/// registered through the OTLP exporter seam (it replaces the OTLP registration, which sits at one place in the pipeline), with the OTLP endpoint set.
/// </summary>
public sealed class ExporterOrderTests
{
    private const string Sentinel = "ZgHlSentinelQ7x2Vn9w";
    private const string SourceName = "T138.ExporterOrder";

    private sealed class Snapshot
    {
        public List<string> Tags { get; } = [];

        public string? StatusDescription { get; set; }
    }

    private sealed class SnapshotProcessor(Snapshot snapshot) : BaseProcessor<Activity>
    {
        public override void OnEnd(Activity data)
        {
            snapshot.StatusDescription = data.StatusDescription;
            snapshot.Tags.AddRange(data.TagObjects.Select(t => $"{t.Key}={t.Value}"));
        }
    }

    private sealed class TestEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = "Testing";

        public string ApplicationName { get; set; } = "t";

        public string ContentRootPath { get; set; } = "/";

        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = null!;
    }

    [Fact]
    public void TheRealPipelineExportsRedactedSpansWithTheOtlpEndpointSet()
    {
        var snapshot = new Snapshot();
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { [TelemetryServiceCollectionExtensions.OtlpEndpointKey] = "http://127.0.0.1:1" })
            .Build();
        var services = new ServiceCollection();
        services.AddZaghlolTelemetry(
            configuration,
            new TestEnvironment(),
            "zaghlol-test",
            configureTracing: tracing => tracing.AddSource(SourceName),
            addOtlpExporter: tracing => tracing.AddProcessor(new SnapshotProcessor(snapshot)));
        using var provider = services.BuildServiceProvider();
        using var tracerProvider = provider.GetRequiredService<TracerProvider>();

        using var source = new ActivitySource(SourceName);
        using (var activity = source.StartActivity("HttpRequestIn", ActivityKind.Server))
        {
            Assert.NotNull(activity);
            activity.SetTag("http.request.method", "GET");
            activity.SetTag("url.full", "https://h/x/" + Sentinel);
            activity.SetTag("url.query", "q=" + Sentinel);
            activity.SetTag("enduser.id", Sentinel);
            activity.SetStatus(ActivityStatusCode.Error, "failed " + Sentinel);
        }

        Assert.Contains("http.request.method=GET", snapshot.Tags);
        Assert.DoesNotContain(snapshot.Tags, t => t.Contains(Sentinel, StringComparison.Ordinal));
        Assert.Null(snapshot.StatusDescription);
    }

    [Fact]
    public void TheProbeCatchesAnExporterThatRunsBeforeTheRedactor()
    {
        // Negative control: the reversed order, built by hand, leaks to the probe.
        var snapshot = new Snapshot();
        using var tracerProvider = Sdk.CreateTracerProviderBuilder()
            .AddSource(SourceName)
            .AddProcessor(new SnapshotProcessor(snapshot))
            .AddProcessor(new RedactingActivityProcessor())
            .Build();
        using var source = new ActivitySource(SourceName);

        using (var activity = source.StartActivity("HttpRequestIn", ActivityKind.Server))
        {
            Assert.NotNull(activity);
            activity.SetTag("url.query", "q=" + Sentinel);
            activity.SetStatus(ActivityStatusCode.Error, "failed " + Sentinel);
        }

        Assert.Contains(snapshot.Tags, t => t.Contains(Sentinel, StringComparison.Ordinal));
        Assert.NotNull(snapshot.StatusDescription);
    }
}
