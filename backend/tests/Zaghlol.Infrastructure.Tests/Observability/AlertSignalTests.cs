using System.Collections.Concurrent;
using System.Diagnostics.Metrics;
using System.Globalization;
using Microsoft.Extensions.Logging;
using Serilog;
using Serilog.Extensions.Logging;
using Zaghlol.Infrastructure.Logging;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.Tests.Observability;

/// <summary>T-138: <see cref="IAlertSignal"/> counts the rule and writes one <c>audit_alert</c> line with a purchase or operator UUID.</summary>
public sealed class AlertSignalTests
{
    [Theory]
    [InlineData(AuditAlertRule.SupportMovesPerPurchase90d, "support_moves_per_purchase_90d", true)]
    [InlineData(AuditAlertRule.DisputeFrozenRefusal, "dispute_frozen_refusal", true)]
    [InlineData(AuditAlertRule.SupportUnfreeze, "support_unfreeze", true)]
    [InlineData(AuditAlertRule.SeatRebindOverCap, "seat_rebind_over_cap", true)]
    [InlineData(AuditAlertRule.PurchaseUnacked48h, "purchase_unacked_48h", true)]
    [InlineData(AuditAlertRule.SupportActionsPerOperatorDay, "support_actions_per_operator_day", false)]
    [InlineData(AuditAlertRule.OwnershipFailuresPerOperatorDay, "ownership_failures_per_operator_day", false)]
    public void RaiseWritesOneWarnLineAndCountsTheRule(AuditAlertRule rule, string name, bool purchaseRule)
    {
        var id = Guid.NewGuid();
        var counted = new ConcurrentQueue<string>();
        using var listener = new MeterListener();
        listener.InstrumentPublished = (instrument, l) =>
        {
            if (instrument.Meter.Name == ZaghlolMetrics.MeterName && instrument.Name == "zaghlol.audit_alert.fired")
            {
                l.EnableMeasurementEvents(instrument);
            }
        };
        listener.SetMeasurementEventCallback<long>((_, value, tags, _) =>
        {
            if (value == 0)
            {
                return;
            }

            foreach (var tag in tags)
            {
                counted.Enqueue(string.Create(CultureInfo.InvariantCulture, $"{tag.Key}={tag.Value}"));
            }
        });
        listener.Start();

        using var writer = new StringWriter(CultureInfo.InvariantCulture);
        using var logger = new LoggerConfiguration().ConfigureZaghlol("test", writer).CreateLogger();
        using var factory = new SerilogLoggerFactory(logger);
        using var metrics = new ZaghlolMetrics();
        var signal = new AlertSignal(metrics, factory.CreateLogger<AlertSignal>());

        signal.Raise(rule, purchaseRule ? id : null, purchaseRule ? null : id);

        var line = LogCapture.Single(writer.ToString());
        Assert.Equal("audit_alert", line.GetProperty("msg").GetString());
        Assert.Equal("warn", line.GetProperty("level").GetString());
        Assert.Equal(name, line.GetProperty("rule").GetString());
        Assert.Equal(id.ToString("D"), line.GetProperty(purchaseRule ? "purchaseId" : "operatorId").GetString());
        Assert.False(line.TryGetProperty(purchaseRule ? "operatorId" : "purchaseId", out _));
        Assert.Contains("rule=" + name, counted);
    }

    [Fact]
    public void ARuleWithoutItsIdentifierIsRefused()
    {
        using var writer = new StringWriter(CultureInfo.InvariantCulture);
        using var logger = new LoggerConfiguration().ConfigureZaghlol("test", writer).CreateLogger();
        using var factory = new SerilogLoggerFactory(logger);
        using var metrics = new ZaghlolMetrics();
        var signal = new AlertSignal(metrics, factory.CreateLogger<AlertSignal>());

        Assert.Throws<ArgumentException>(() => signal.Raise(AuditAlertRule.SupportUnfreeze));
        Assert.Throws<ArgumentException>(() => signal.Raise(AuditAlertRule.SupportActionsPerOperatorDay, purchaseId: Guid.NewGuid()));
        Assert.Empty(writer.ToString());
    }

    [Fact]
    public void EveryRuleHasADistinctNameThatMatchesTheAlertRules()
    {
        var names = Enum.GetValues<AuditAlertRule>().Select(AlertSignal.RuleName).ToArray();

        Assert.Equal(7, names.Distinct(StringComparer.Ordinal).Count());
    }
}
