using System.Collections.Concurrent;
using System.Diagnostics;
using System.Diagnostics.Metrics;
using System.Globalization;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using OpenTelemetry;
using OpenTelemetry.Trace;
using Serilog;
using Serilog.Events;
using Zaghlol.Application.Purchases;
using Zaghlol.Infrastructure.GooglePlay;
using Zaghlol.Infrastructure.Logging;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Purchases;
using Zaghlol.Testing;

using MelLevel = Microsoft.Extensions.Logging.LogLevel;

namespace Zaghlol.Infrastructure.Tests.GooglePlay;

/// <summary>
/// The real Play client registration (<c>AddZaghlolGooglePlay</c>) in a <c>Testing</c> host against WireMock, with the production
/// logger configuration (every category at Verbose: the worst case), the real telemetry pipeline (spans copied after the
/// redactor) and a meter listener on the Zaghlol meter.
/// </summary>
internal sealed class PlayClientHost : IAsyncDisposable
{
    private readonly ServiceProvider provider;
    private readonly TracerProvider tracer;
    private readonly MeterListener meters = new();
    private readonly LockedWriter log = new();

    private PlayClientHost(PlayWireMock play, IReadOnlyDictionary<string, string?> extra, IPlayAccessTokenSource? tokens)
    {
        Play = play;
        var settings = new Dictionary<string, string?>(play.Settings()) { [TelemetryServiceCollectionExtensions.OtlpEndpointKey] = "http://127.0.0.1:1" };
        foreach (var (key, value) in extra)
        {
            settings[key] = value;
        }

        var configuration = new ConfigurationBuilder().AddInMemoryCollection(settings).Build();
        var logger = new LoggerConfiguration().ConfigureZaghlol("test", log).MinimumLevel.Verbose();
        foreach (var category in LoggingConfigurationExtensions.QuietCategories.Append("Microsoft").Append("System"))
        {
            logger.MinimumLevel.Override(category, LogEventLevel.Verbose);
        }

        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(configuration);
        services.AddSingleton<IHostEnvironment>(new TestEnvironment());
        services.AddLogging(b => b.AddSerilog(logger.CreateLogger(), dispose: true).SetMinimumLevel(MelLevel.Trace));
        services.AddZaghlolTelemetry(configuration, new TestEnvironment(), "zaghlol-test", addOtlpExporter: t => t.AddProcessor(new SpanCopy(Spans)));
        services.AddZaghlolGooglePlay();
        if (tokens is not null)
        {
            services.AddSingleton(tokens);
        }

        provider = services.BuildServiceProvider();
        tracer = provider.GetRequiredService<TracerProvider>();

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

    public PlayWireMock Play { get; }

    public IServiceProvider Services => provider;

    public IPlayDeveloperApi Api => provider.GetRequiredService<IPlayDeveloperApi>();

    public ConcurrentQueue<string> Spans { get; } = new();

    public ConcurrentQueue<(string Instrument, long Value, Dictionary<string, string?> Tags)> Measurements { get; } = new();

    public string LogOutput => log.ToString();

    public static PlayClientHost Start(PlayWireMock play, IReadOnlyDictionary<string, string?>? extra = null, IPlayAccessTokenSource? tokens = null) =>
        new(play, extra ?? new Dictionary<string, string?>(), tokens);

    public IReadOnlyList<Dictionary<string, string?>> StoreCalls() =>
        [.. Measurements.Where(m => m.Instrument == "zaghlol.store.call" && m.Value > 0).Select(m => m.Tags)];

    public async ValueTask DisposeAsync()
    {
        meters.Dispose();
        tracer.ForceFlush();
        await provider.DisposeAsync();
    }

    /// <summary>Copies every span (display name and tags) after the redactor, as the exporter would see it.</summary>
    private sealed class SpanCopy(ConcurrentQueue<string> spans) : BaseProcessor<Activity>
    {
        public override void OnEnd(Activity data) =>
            spans.Enqueue(data.DisplayName + " | " + string.Join(" | ", data.TagObjects.Select(t => t.Key + "=" + Convert.ToString(t.Value, CultureInfo.InvariantCulture)))
                + " | " + data.StatusDescription);
    }

    private sealed class TestEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = "Testing";

        public string ApplicationName { get; set; } = "t";

        public string ContentRootPath { get; set; } = "/";

        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = null!;
    }

    private sealed class LockedWriter : StringWriter
    {
        private readonly object gate = new();

        public LockedWriter()
            : base(CultureInfo.InvariantCulture)
        {
        }

        public override Encoding Encoding => Encoding.UTF8;

        public override void Write(char value)
        {
            lock (gate)
            {
                base.Write(value);
            }
        }

        public override void Write(string? value)
        {
            lock (gate)
            {
                base.Write(value);
            }
        }

        public override string ToString()
        {
            lock (gate)
            {
                return base.ToString();
            }
        }
    }
}
