using System.Globalization;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using OpenTelemetry;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Infrastructure.Observability;

public static class TelemetryServiceCollectionExtensions
{
    public const string OtlpEndpointKey = "OTEL_EXPORTER_OTLP_ENDPOINT";
    public const string SampleRatioKey = "Telemetry:SampleRatio";

    /// <summary>
    /// OpenTelemetry traces and metrics for the API (<c>zaghlol-api</c>) and the workers (<c>zaghlol-worker</c>), plus
    /// <see cref="ZaghlolMetrics"/> and <see cref="IAlertSignal"/>. Spans pass through <see cref="RedactingActivityProcessor"/>
    /// before any exporter; instrumentations never record exceptions. The OTLP exporters are added only when
    /// <c>OTEL_EXPORTER_OTLP_ENDPOINT</c> is set. The app samples everything (<c>Telemetry:SampleRatio</c>, default 1): "10% and
    /// every error" is the collector's tail-sampling policy. Logs do not go through OpenTelemetry: they are JSON on stdout.
    /// </summary>
    /// <param name="configureTracing">Host-specific instrumentation (ASP.NET Core in the API).</param>
    /// <param name="configureMetrics">Host-specific meters (ASP.NET Core in the API).</param>
    /// <param name="addOtlpExporter">Test seam: replaces the OTLP span exporter registration, which stays at the same place,
    /// after the redactor and only when the endpoint is set. Production passes <c>null</c>.</param>
    public static IServiceCollection AddZaghlolTelemetry(
        this IServiceCollection services,
        IConfiguration configuration,
        IHostEnvironment environment,
        string serviceName,
        Action<TracerProviderBuilder>? configureTracing = null,
        Action<MeterProviderBuilder>? configureMetrics = null,
        Action<TracerProviderBuilder>? addOtlpExporter = null)
    {
        ArgumentNullException.ThrowIfNull(services);
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(environment);
        ArgumentException.ThrowIfNullOrWhiteSpace(serviceName);

        services.TryAddSingleton<ZaghlolMetrics>();
        services.TryAddSingleton<IAlertSignal, AlertSignal>();

        // The meter exists only once ZaghlolMetrics is built; build it at startup so its instruments are always exported.
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, MetricsStarter>());

        var exportOtlp = !string.IsNullOrWhiteSpace(configuration[OtlpEndpointKey]);
        var ratio = double.TryParse(configuration[SampleRatioKey], NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed)
            ? Math.Clamp(parsed, 0d, 1d)
            : 1d;
        var version = typeof(TelemetryServiceCollectionExtensions).Assembly.GetName().Version?.ToString() ?? "0";

        services.AddOpenTelemetry()
            .ConfigureResource(resource => resource
                .AddService(serviceName, serviceVersion: version)
                .AddAttributes([new KeyValuePair<string, object>("deployment.environment.name", environment.EnvironmentName)]))
            .WithTracing(tracing =>
            {
                tracing.SetSampler(new ParentBasedSampler(ratio >= 1d ? new AlwaysOnSampler() : new TraceIdRatioBasedSampler(ratio)));
                tracing.AddHttpClientInstrumentation(options =>
                {
                    options.RecordException = false;
                    options.EnrichWithHttpRequestMessage = static (activity, request) =>
                        activity.SetTag("url.template", HttpRequestTelemetry.UrlTemplateOf(request));
                });

                // Npgsql 10 has a built-in ActivitySource, so no extra instrumentation package.
                tracing.AddSource("Npgsql");
                configureTracing?.Invoke(tracing);

                // Registered before any exporter, so nothing is exported unredacted.
                tracing.AddProcessor(new RedactingActivityProcessor());
                if (exportOtlp)
                {
                    (addOtlpExporter ?? (static t => t.AddOtlpExporter()))(tracing);
                }
            })
            .WithMetrics(metrics =>
            {
                metrics.AddMeter(ZaghlolMetrics.MeterName, KmsMetrics.MeterName);
                metrics.AddHttpClientInstrumentation();
                metrics.AddRuntimeInstrumentation();
                configureMetrics?.Invoke(metrics);
                if (exportOtlp)
                {
                    metrics.AddOtlpExporter();
                }
            });

        return services;
    }

    /// <summary>
    /// <see cref="ILogPseudonymizer"/> for <c>installHash</c>. With a KMS registered the monthly log key comes from
    /// <see cref="IKeyedHasher"/> (T-123); only Development and Testing hosts without one use a per-process random key.
    /// </summary>
    public static IServiceCollection AddZaghlolLogPseudonymizer(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<ILogKeySource>(provider =>
        {
            if (provider.GetService<IKeyedHasher>() is { } hasher)
            {
                return new KmsLogKeySource(hasher);
            }

            var environment = provider.GetRequiredService<IHostEnvironment>();
            return environment.IsDevelopment() || environment.IsEnvironment("Testing")
                ? new EphemeralLogKeySource()
                : throw new InvalidOperationException("installHash needs the KMS-derived log key outside Development and Testing.");
        });
        services.TryAddSingleton<ILogPseudonymizer, LogPseudonymizer>();
        return services;
    }
}

/// <summary>Builds <see cref="ZaghlolMetrics"/> when the host starts, so the <c>Zaghlol</c> meter is live from the first export.</summary>
internal sealed class MetricsStarter(ZaghlolMetrics metrics) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        _ = metrics;
        KmsMetrics.Seed();
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
