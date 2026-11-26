using System.Text.Json;

namespace Zaghlol.Application.Llm.Plans;

/// <summary>A template that passed the section 2.3 grammar.</summary>
public sealed record PlanTemplate(string Lang, string Text);

/// <summary>
/// Outcome of <see cref="PlanValidator.Validate"/>: <see cref="IsValid"/> with the plan (and the template when it passed step 6),
/// or a fallback with a reason code. A rejected template is <see cref="TemplateRejection"/> and never fails the plan.
/// </summary>
public sealed class PlanValidationResult
{
    private PlanValidationResult(bool isValid, JsonElement plan, PlanTemplate? template, PlanReason? reason, PlanReason? templateRejection)
    {
        IsValid = isValid;
        Plan = plan;
        Template = template;
        Reason = reason;
        TemplateRejection = templateRejection;
    }

    public bool IsValid { get; }

    /// <summary>The validated plan (default when this is a fallback).</summary>
    public JsonElement Plan { get; }

    /// <summary>The template, or null when the plan had none or step 6 dropped it.</summary>
    public PlanTemplate? Template { get; }

    /// <summary>Why the result is a fallback (steps 1 to 5); null when valid.</summary>
    public PlanReason? Reason { get; }

    /// <summary>Why a template was dropped (step 6); null when it passed or there was none.</summary>
    public PlanReason? TemplateRejection { get; }

    public static PlanValidationResult Valid(JsonElement plan, PlanTemplate? template, PlanReason? templateRejection = null) =>
        new(true, plan, template, null, templateRejection);

    public static PlanValidationResult Fallback(PlanReason reason) => new(false, default, null, reason, null);
}
