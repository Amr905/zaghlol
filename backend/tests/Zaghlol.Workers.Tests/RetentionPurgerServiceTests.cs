using System.Text.RegularExpressions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Serilog;
using Serilog.Core;
using Serilog.Events;
using Serilog.Formatting;
using Zaghlol.Application.Retention;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Workers.Tests;

public sealed partial class RetentionPurgerServiceTests
{
    private sealed class TestSink(ITextFormatter formatter, TextWriter writer) : ILogEventSink
    {
        private readonly object gate = new();

        public void Emit(LogEvent logEvent)
        {
            lock (gate)
            {
                formatter.Format(logEvent, writer);
            }
        }
    }

    private sealed class FakeStore(Func<string, int> purge) : IRetentionStore
    {
        public Task<int> PurgeBatchAsync(string rule, DateTimeOffset now, int batchSize, CancellationToken cancellationToken) =>
            Task.FromResult(purge(rule));
    }

    private sealed class NullMetrics : IRetentionMetrics
    {
        public void Purged(string rule, long count)
        {
        }

        public void Failed(string rule)
        {
        }
    }

    private static IConfiguration Config(string? hours = null, string? batch = null) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["Retention:IntervalHours"] = hours, ["Retention:BatchSize"] = batch })
            .Build();

    [Theory]
    [InlineData(null, 24)]
    [InlineData("abc", 24)]
    [InlineData("6", 6)]
    [InlineData("0", 1)]
    [InlineData("-3", 1)]
    public void TheIntervalDefaultsToADayAndIsAtLeastAnHour(string? configured, int expectedHours)
    {
        Assert.Equal(TimeSpan.FromHours(expectedHours), RetentionPurgerService.IntervalFrom(Config(configured)));
    }

    [Theory]
    [InlineData(null, 5000)]
    [InlineData("10", 100)]
    [InlineData("999999", 50_000)]
    [InlineData("2500", 2500)]
    public void TheBatchSizeIsClamped(string? configured, int expected)
    {
        Assert.Equal(expected, RetentionPurgerService.BatchSizeFrom(Config(batch: configured)));
    }

    private static async Task<string> RunOnceAsync(Func<string, int> purge)
    {
        var output = new StringWriter();
        var logger = new LoggerConfiguration()
            .WriteTo.Sink(new TestSink(new ZaghlolJsonFormatter(), output))
            .CreateLogger();
        using var factory = LoggerFactory.Create(b => b.AddSerilog(logger));
        var job = new RetentionPurgeJob(new FakeStore(purge), new NullMetrics(), TimeProvider.System);
        using var service = new RetentionPurgerService(job, TimeProvider.System, Config(), factory.CreateLogger<RetentionPurgerService>());

        await service.StartAsync(CancellationToken.None);
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (!output.ToString().Contains("finished", StringComparison.Ordinal) && !output.ToString().Contains("failed", StringComparison.Ordinal)
               && DateTime.UtcNow < deadline)
        {
            await Task.Delay(20);
        }

        await service.StopAsync(CancellationToken.None);
        await logger.DisposeAsync();
        return output.ToString();
    }

    [Fact]
    public async Task LogsCarryOnlyTheRuleNameAndACount()
    {
        var log = await RunOnceAsync(rule => rule == RetentionRules.ReplayGuard ? 3 : 0);

        Assert.Contains("\"operation\":\"replay_guard\"", log, StringComparison.Ordinal);
        Assert.Contains("\"count\":3", log, StringComparison.Ordinal);
        Assert.DoesNotContain(RetentionRules.SeatClaimants, log, StringComparison.Ordinal); // zero counts are not logged
    }

    [Fact]
    public async Task AFailureLogsNoAddressAndNoExceptionMessage()
    {
        var log = await RunOnceAsync(rule => rule == RetentionRules.AuditSupport
            ? throw new InvalidOperationException("connection to 203.0.113.77:5432 refused for token abc123secret")
            : 0);

        Assert.Contains("\"operation\":\"audit_support\"", log, StringComparison.Ordinal);
        Assert.DoesNotMatch(Ipv4(), log);
        Assert.DoesNotContain("abc123secret", log, StringComparison.Ordinal);
        Assert.DoesNotContain("refused", log, StringComparison.Ordinal);
    }

    [GeneratedRegex(@"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b")]
    private static partial Regex Ipv4();
}
