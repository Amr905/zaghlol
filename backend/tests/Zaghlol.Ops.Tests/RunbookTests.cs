namespace Zaghlol.Ops.Tests;

public class RunbookTests
{
    private static string RepoFile(string relative)
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "CLAUDE.md")))
        {
            dir = dir.Parent;
        }

        Assert.NotNull(dir);
        return Path.Combine(dir.FullName, relative);
    }

    [Fact]
    public void EveryAlertRuleHasARunbookAction()
    {
        var rules = File.ReadAllLines(RepoFile("backend/deploy/observability/alerts/seats.yaml"))
            .Select(l => l.Trim())
            .Where(l => l.StartsWith("- alert:", StringComparison.Ordinal))
            .Select(l => l["- alert:".Length..].Trim())
            .ToList();
        var runbook = File.ReadAllText(RepoFile("docs/ops/support-runbook.md"));

        Assert.NotEmpty(rules);
        foreach (var rule in rules)
        {
            Assert.True(runbook.Contains(rule, StringComparison.Ordinal), $"runbook has no action for alert {rule}");
        }
    }

    [Theory]
    [InlineData("support_moves_per_purchase_90d")]
    [InlineData("support_actions_per_operator_day")]
    [InlineData("ownership_failures_per_operator_day")]
    [InlineData("dispute_frozen_refusal")]
    [InlineData("support_unfreeze")]
    [InlineData("seat_rebind")]
    [InlineData("R6-1")]
    [InlineData("R5-5(a)")]
    [InlineData("R4-7(3)")]
    [InlineData("R4-6")]
    [InlineData("PO to confirm")]
    public void RunbookCoversRequiredTopic(string topic)
    {
        var runbook = File.ReadAllText(RepoFile("docs/ops/support-runbook.md"));

        Assert.Contains(topic, runbook, StringComparison.Ordinal);
    }
}
