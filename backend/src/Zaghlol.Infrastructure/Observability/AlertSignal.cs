using Microsoft.Extensions.Logging;

namespace Zaghlol.Infrastructure.Observability;

/// <summary>The audit alerts the acting services raise (backend-api.md section 4.3 and 5.3, error-handling-and-observability.md section 4).</summary>
public enum AuditAlertRule
{
    /// <summary>More than 2 support moves for one purchase in 90 days. Carries the purchase UUID.</summary>
    SupportMovesPerPurchase90d,

    /// <summary>More than 20 support actions by one operator in a day. Carries the operator UUID.</summary>
    SupportActionsPerOperatorDay,

    /// <summary>More than 5 failed ownership checks by one operator in a day. Carries the operator UUID.</summary>
    OwnershipFailuresPerOperatorDay,

    /// <summary>Any <c>dispute_frozen</c> refusal. Carries the purchase UUID.</summary>
    DisputeFrozenRefusal,

    /// <summary>Any <c>support_unfreeze</c> call. Carries the purchase UUID.</summary>
    SupportUnfreeze,

    /// <summary>An over-cap same-iPhone rebind (<c>seat_rebind</c>). Carries the purchase UUID.</summary>
    SeatRebindOverCap,
}

/// <summary>
/// Per-purchase and per-operator rules can't be metric labels (cardinality, and 90-day windows), so the acting task evaluates
/// the threshold in its own transaction and raises the signal here: one <c>audit_alert.fired{rule}</c> count and one
/// <c>warn</c> <c>audit_alert</c> log line with the rule and the purchase UUID (or the operator UUID for operator rules).
/// </summary>
public interface IAlertSignal
{
    /// <param name="rule">The rule that fired.</param>
    /// <param name="purchaseId">Required for purchase rules.</param>
    /// <param name="operatorId">Required for operator rules (a staff identifier, not user data).</param>
    void Raise(AuditAlertRule rule, Guid? purchaseId = null, Guid? operatorId = null);
}

public sealed partial class AlertSignal(ZaghlolMetrics metrics, ILogger<AlertSignal> logger) : IAlertSignal
{
    public static string RuleName(AuditAlertRule rule) => rule switch
    {
        AuditAlertRule.SupportMovesPerPurchase90d => "support_moves_per_purchase_90d",
        AuditAlertRule.SupportActionsPerOperatorDay => "support_actions_per_operator_day",
        AuditAlertRule.OwnershipFailuresPerOperatorDay => "ownership_failures_per_operator_day",
        AuditAlertRule.DisputeFrozenRefusal => "dispute_frozen_refusal",
        AuditAlertRule.SupportUnfreeze => "support_unfreeze",
        AuditAlertRule.SeatRebindOverCap => "seat_rebind_over_cap",
        _ => throw new ArgumentOutOfRangeException(nameof(rule)),
    };

    public void Raise(AuditAlertRule rule, Guid? purchaseId = null, Guid? operatorId = null)
    {
        var name = RuleName(rule);
        var perOperator = rule is AuditAlertRule.SupportActionsPerOperatorDay or AuditAlertRule.OwnershipFailuresPerOperatorDay;
        if (perOperator && operatorId is null)
        {
            throw new ArgumentException("An operator rule needs the operator UUID.", nameof(operatorId));
        }

        if (!perOperator && purchaseId is null)
        {
            throw new ArgumentException("A purchase rule needs the purchase UUID.", nameof(purchaseId));
        }

        metrics.AuditAlertFired(name);

        // The fields travel as scope properties, so the message stays the constant "audit_alert" (query: msg = "audit_alert").
        var fields = new Dictionary<string, object> { ["Rule"] = name };
        if (perOperator)
        {
            fields["OperatorId"] = operatorId!.Value;
        }
        else
        {
            fields["PurchaseId"] = purchaseId!.Value;
        }

        using (logger.BeginScope(fields))
        {
            Fired(logger);
        }
    }

    [LoggerMessage(EventId = 9001, Level = LogLevel.Warning, Message = LogFieldPolicy.AuditAlertMessage)]
    private static partial void Fired(ILogger logger);
}
