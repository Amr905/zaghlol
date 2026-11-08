using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using OpenTelemetry;
using OpenTelemetry.Metrics;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.Tests.Observability;

/// <summary>
/// Code review round 2, major #1: the "any occurrence" series must exist at 0 before the first event. Counter.Add is dropped
/// while no listener exists, so this goes through the real DI path (<c>AddZaghlolTelemetry</c>, the hosted services) with an
/// in-memory metric exporter, exactly as production orders things.
/// </summary>
public sealed class SeededSeriesTests
{
    private sealed class TestEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = "Testing";

        public string ApplicationName { get; set; } = "t";

        public string ContentRootPath { get; set; } = "/";

        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = null!;
    }

    [Fact]
    public async Task EverySeriesIsExportedAtZeroBeforeAnyEvent()
    {
        var exported = new List<MetricSnapshot>();
        var services = new ServiceCollection();
        services.AddZaghlolTelemetry(
            new ConfigurationBuilder().Build(),
            new TestEnvironment(),
            "zaghlol-test",
            configureMetrics: metrics => metrics.AddInMemoryExporter(exported));
        await using var provider = services.BuildServiceProvider();

        foreach (var hosted in provider.GetServices<IHostedService>())
        {
            await hosted.StartAsync(CancellationToken.None);
        }

        Assert.True(provider.GetRequiredService<MeterProvider>().ForceFlush(10_000));

        var zeros = new List<(string Name, string Tag)>();

        // The KMS counter is process-wide, so a parallel test may already have moved a series off 0: for it, existence counts.
        var present = new List<(string Name, string Tag)>();
        foreach (var metric in exported.Where(m => m.MetricType == MetricType.LongSum))
        {
            foreach (var point in metric.MetricPoints)
            {
                var tags = new List<string>();
                foreach (var tag in point.Tags)
                {
                    tags.Add($"{tag.Key}={tag.Value}");
                }

                present.Add((metric.Name, string.Join(';', tags)));
                if (point.GetSumLong() == 0)
                {
                    zeros.Add((metric.Name, string.Join(';', tags)));
                }
            }
        }

        foreach (var rule in Enum.GetValues<AuditAlertRule>())
        {
            Assert.Contains(("zaghlol.audit_alert.fired", "rule=" + AlertSignal.RuleName(rule)), zeros);
        }

        foreach (var store in ZaghlolMetrics.NotificationStores)
        {
            Assert.Contains(("zaghlol.notification.dead_letter", "store=" + store), zeros);
        }

        foreach (var operation in new[] { "sign", "sign_verify", "hmac", "data_key", "public_key" })
        {
            Assert.Contains(("zaghlol.kms.unavailable", "operation=" + operation), present);
        }
    }
}
