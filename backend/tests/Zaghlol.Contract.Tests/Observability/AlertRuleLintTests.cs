using System.Diagnostics.Metrics;
using System.Text.Json;
using System.Text.RegularExpressions;
using YamlDotNet.RepresentationModel;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Contract.Tests.Observability;

/// <summary>
/// T-138 acceptance: every alert listed in error-handling-and-observability.md section 4 exists as code and no label,
/// annotation or expression carries an install ID, account ID, token or transaction ID (names of such fields are refused too).
/// <c>promtool check rules</c> runs in CI (the <c>alert-rules</c> job).
/// </summary>
public sealed partial class AlertRuleLintTests
{
    // One name per row of the T-138 alert list.
    private static readonly string[] RequiredAlerts =
    [
        // Availability and SLO
        "ZaghlolSyntheticCheckFailing", "ZaghlolSloBurnRateFast", "ZaghlolSloBurnRateSlow",
        "ZaghlolSyncLatencyP95High", "ZaghlolPurchaseVerifyLatencyP95High",
        // Purchases
        "ZaghlolPurchaseUnackedOver48h", "ZaghlolPurchaseVerifyFailureRateHigh", "ZaghlolStoreAuthError",
        "ZaghlolAppleSignedAnswerInvalid", "ZaghlolAppStoreClientErrorRateHigh",
        // Notifications
        "ZaghlolNotificationLagHigh", "ZaghlolNotificationDeadLetter",
        // T-133 RTDN (paged)
        "ZaghlolRtdnBacklogOld", "ZaghlolNotificationProcessorHeartbeat", "ZaghlolRtdnAuthConfig", "ZaghlolRtdnIgnoredPackage",
        // Prices
        "ZaghlolPriceAgeWarn", "ZaghlolPriceAgePage",
        // Catalog and sync size
        "ZaghlolCatalogSnapshotMissing", "ZaghlolSyncResponseSizeHigh",
        // Seats and attestation
        "ZaghlolMoveCooldownSpike", "ZaghlolAttestationFailureSpike", "ZaghlolPlayIntegrityQuotaHigh",
        // audit_alert.fired for each rule
        "ZaghlolAuditSupportMovesPerPurchase90d", "ZaghlolAuditSupportActionsPerOperatorDay",
        "ZaghlolAuditOwnershipFailuresPerOperatorDay", "ZaghlolAuditDisputeFrozenRefusal", "ZaghlolAuditSupportUnfreeze",
        "ZaghlolAuditSeatRebindOverCap", "ZaghlolAuditPurchaseUnacked48h",
        // Signing, security, capacity
        "ZaghlolKmsUnavailable", "ZaghlolSigningVerifyFailed", "ZaghlolAuthFailureSpike", "ZaghlolRateLimitedSpike",
        "ZaghlolCpuHigh", "ZaghlolMemoryHigh", "ZaghlolDbConnectionsHigh", "ZaghlolDbStorageHigh",
    ];

    private static readonly HashSet<string> Forbidden = new(StringComparer.Ordinal)
    {
        "install", "installs", "installid", "installhash", "account", "accounts", "token", "tokens", "transaction", "transactions",
        "order", "orders", "email", "emails", "ip", "ips", "nonce", "nonces", "seatkey", "seatkeys",
    };

    private static readonly HashSet<string> Severities = new(StringComparer.Ordinal) { "page", "warn" };

    private static string ObservabilityDirectory => Path.Combine(AppContext.BaseDirectory, "observability");

    [GeneratedRegex("[A-Za-z]+")]
    private static partial Regex Words();

    [GeneratedRegex("(?<=[a-z])(?=[A-Z])")]
    private static partial Regex CamelBoundary();

    [GeneratedRegex("\\bzaghlol_[a-z0-9_]+")]
    private static partial Regex ZaghlolMetric();

    [GeneratedRegex("_(bucket|sum|count)$")]
    private static partial Regex HistogramSuffix();

    private sealed record Alert(string File, string Name, string Expr, Dictionary<string, string> Labels, Dictionary<string, string> Annotations);

    [Fact]
    public void EveryAlertOfTheDesignExistsOnce()
    {
        var names = LoadAlerts().Select(a => a.Name).ToArray();

        Assert.All(RequiredAlerts, required => Assert.Contains(required, names));
        Assert.Equal(names.Length, names.Distinct(StringComparer.Ordinal).Count());
    }

    [Fact]
    public void EveryAlertHasASeveritySummaryAndDescription()
    {
        foreach (var alert in LoadAlerts())
        {
            Assert.True(alert.Labels.TryGetValue("severity", out var severity) && Severities.Contains(severity), alert.Name + " severity");
            Assert.False(string.IsNullOrWhiteSpace(alert.Annotations.GetValueOrDefault("summary")), alert.Name + " summary");
            Assert.False(string.IsNullOrWhiteSpace(alert.Annotations.GetValueOrDefault("description")), alert.Name + " description");
            Assert.False(string.IsNullOrWhiteSpace(alert.Expr), alert.Name + " expr");
        }
    }

    [Fact]
    public void NoLabelAnnotationOrExpressionMentionsAnIdentifierOrCredential()
    {
        foreach (var alert in LoadAlerts())
        {
            var texts = alert.Labels.SelectMany(l => new[] { l.Key, l.Value })
                .Concat(alert.Annotations.SelectMany(a => new[] { a.Key, a.Value }))
                .Append(alert.Expr)
                .Append(alert.Name);
            foreach (var text in texts)
            {
                Assert.Empty(ForbiddenWordsIn(text).Select(w => alert.Name + ": " + w));
            }
        }
    }

    [Fact]
    public void TheLintCatchesForbiddenWords()
    {
        Assert.Contains("install", ForbiddenWordsIn("sum by (installId) (x)"));
        Assert.Contains("token", ForbiddenWordsIn("purchase_token_total"));
        Assert.Contains("order", ForbiddenWordsIn("by (orderId)"));
        Assert.Contains("ip", ForbiddenWordsIn("client_ip"));
        Assert.Contains("seatkey", ForbiddenWordsIn("seat_key"));
        Assert.Empty(ForbiddenWordsIn("http_route, zaghlol_description, purchase UUID"));
    }

    [Fact]
    public void EveryAuditAlertRuleHasAnAlertOnItsExactName()
    {
        var alerts = LoadAlerts();
        foreach (var rule in Enum.GetValues<AuditAlertRule>())
        {
            var name = AlertSignal.RuleName(rule);
            Assert.Contains(alerts, a => a.Expr.Contains("zaghlol_audit_alert_fired_total", StringComparison.Ordinal)
                                         && a.Expr.Contains($"rule=\"{name}\"", StringComparison.Ordinal));
        }
    }

    [Fact]
    public void EveryZaghlolMetricInRulesAndDashboardsIsDefinedByTheCode()
    {
        var defined = DefinedPrometheusNames();
        var used = LoadAlerts().Select(a => (Source: a.Name, Text: a.Expr))
            .Concat(LoadDashboardExpressions())
            .SelectMany(x => ZaghlolMetric().Matches(x.Text).Select(m => (x.Source, Metric: m.Value)))
            .ToArray();

        Assert.NotEmpty(used);
        foreach (var (source, metric) in used)
        {
            var baseName = HistogramSuffix().Replace(metric, string.Empty);
            Assert.True(defined.Contains(metric) || defined.Contains(baseName), $"{source} uses {metric}, which no instrument produces");
        }
    }

    [Fact]
    public void DashboardsAreValidAndFreeOfIdentifiers()
    {
        var files = Directory.GetFiles(Path.Combine(ObservabilityDirectory, "dashboards"), "*.json");
        Assert.Equal(3, files.Length);
        foreach (var file in files)
        {
            using var document = JsonDocument.Parse(File.ReadAllText(file));
            Assert.True(document.RootElement.GetProperty("panels").GetArrayLength() >= 6, file);
            Assert.Empty(ForbiddenWordsIn(File.ReadAllText(file)).Select(w => Path.GetFileName(file) + ": " + w));
        }
    }

    [Fact]
    public void SyntheticChecksCoverHealthSyncAndTheLatestSnapshot()
    {
        var yaml = File.ReadAllText(Path.Combine(ObservabilityDirectory, "synthetics.yaml"));

        Assert.Contains("name: health", yaml, StringComparison.Ordinal);
        Assert.Contains("name: sync", yaml, StringComparison.Ordinal);
        Assert.Contains("name: catalog-latest-snapshot", yaml, StringComparison.Ordinal);
        Assert.Contains("interval: 60s", yaml, StringComparison.Ordinal);

        // Credentials of the synthetic install come from the secrets manager, never from the file.
        Assert.Contains("${SYNTHETIC_INSTALL_CREDENTIAL}", yaml, StringComparison.Ordinal);
    }

    private static IEnumerable<string> ForbiddenWordsIn(string text)
    {
        var spaced = CamelBoundary().Replace(text.Replace('_', ' '), " ");
        var words = Words().Matches(spaced).Select(m => m.Value.ToLowerInvariant()).ToArray();
        foreach (var word in words)
        {
            if (Forbidden.Contains(word))
            {
                yield return word;
            }
        }

        // Adjacent words that together name a forbidden field (seat key, install id, install hash).
        for (var i = 0; i + 1 < words.Length; i++)
        {
            var pair = words[i] + words[i + 1];
            if (Forbidden.Contains(pair))
            {
                yield return pair;
            }
        }
    }

    private static List<Alert> LoadAlerts()
    {
        var alerts = new List<Alert>();
        var directory = Path.Combine(ObservabilityDirectory, "alerts");
        var files = Directory.GetFiles(directory, "*.yaml");
        Assert.NotEmpty(files);
        foreach (var file in files)
        {
            var stream = new YamlStream();
            using (var reader = new StreamReader(file))
            {
                stream.Load(reader);
            }

            var root = (YamlMappingNode)stream.Documents[0].RootNode;
            foreach (var group in (YamlSequenceNode)root.Children[new YamlScalarNode("groups")])
            {
                foreach (var rule in (YamlSequenceNode)((YamlMappingNode)group).Children[new YamlScalarNode("rules")])
                {
                    var map = (YamlMappingNode)rule;
                    alerts.Add(new Alert(
                        Path.GetFileName(file),
                        Scalar(map, "alert"),
                        Scalar(map, "expr"),
                        Pairs(map, "labels"),
                        Pairs(map, "annotations")));
                }
            }
        }

        return alerts;
    }

    private static string Scalar(YamlMappingNode map, string key) => ((YamlScalarNode)map.Children[new YamlScalarNode(key)]).Value ?? string.Empty;

    private static Dictionary<string, string> Pairs(YamlMappingNode map, string key) =>
        map.Children.TryGetValue(new YamlScalarNode(key), out var node)
            ? ((YamlMappingNode)node).Children.ToDictionary(c => ((YamlScalarNode)c.Key).Value!, c => ((YamlScalarNode)c.Value).Value ?? string.Empty, StringComparer.Ordinal)
            : [];

    private static IEnumerable<(string Source, string Text)> LoadDashboardExpressions()
    {
        foreach (var file in Directory.GetFiles(Path.Combine(ObservabilityDirectory, "dashboards"), "*.json"))
        {
            using var document = JsonDocument.Parse(File.ReadAllText(file));
            foreach (var panel in document.RootElement.GetProperty("panels").EnumerateArray())
            {
                foreach (var target in panel.GetProperty("targets").EnumerateArray())
                {
                    yield return (Path.GetFileName(file), target.GetProperty("expr").GetString()!);
                }
            }
        }
    }

    /// <summary>The names the OTLP to Prometheus mapping gives the instruments of the <c>Zaghlol</c> and <c>Zaghlol.Kms</c> meters.</summary>
    private static HashSet<string> DefinedPrometheusNames()
    {
        KmsMetrics.TimeNonceEchoMismatch();
        var names = new HashSet<string>(StringComparer.Ordinal);
        using var metrics = new ZaghlolMetrics();
        using var listener = new MeterListener();
        listener.InstrumentPublished = (instrument, _) =>
        {
            if (instrument.Meter.Name is not (ZaghlolMetrics.MeterName or KmsMetrics.MeterName))
            {
                return;
            }

            var name = instrument.Name.Replace('.', '_');
            name += instrument.Unit switch
            {
                "s" => "_seconds",
                "By" => "_bytes",
                _ => string.Empty,
            };
            if (instrument.GetType().Name.StartsWith("Counter", StringComparison.Ordinal))
            {
                name += "_total";
            }

            lock (names)
            {
                names.Add(name);
            }
        };
        listener.Start();
        return names;
    }
}
