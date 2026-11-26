namespace Zaghlol.Application.Llm.Plans;

/// <summary>Closed set of validator reason codes (ask-llm.md section 2.4a). Only these codes are ever logged, never plan or question text.</summary>
public enum PlanReason
{
    SchemaInvalid,
    RefNotInText,
    PlainName,
    MentionNotInText,
    AmountNotInText,
    AmountFractionTooLong,
    PlanMismatch,
    FilterMultipleKeys,
    PeriodFieldMismatch,
    ModeFieldMismatch,
    SourceFieldMismatch,
    InstrumentsDuplicate,
    TargetCurrencySet,
    IncomeSlugSet,
    TemplateLength,
    TemplateNotNfc,
    TemplateLang,
    TemplatePlanNotAllowed,
    TemplatePlaceholder,
    TemplateDigit,
    TemplateBadBlank,
    TemplateDuplicateBlank,
    TemplateAt,
    TemplateLink,
    TemplateMarkup,
    TemplateControl,
    TemplateEmoji,
    TemplateScript,
    TemplatePlainName,
}

public static class PlanReasons
{
    /// <summary>The fixed wire string of a reason (the strings of the shared vectors).</summary>
    public static string Code(this PlanReason reason) => reason switch
    {
        PlanReason.SchemaInvalid => "SCHEMA_INVALID",
        PlanReason.RefNotInText => "REF_NOT_IN_TEXT",
        PlanReason.PlainName => "PLAIN_NAME",
        PlanReason.MentionNotInText => "MENTION_NOT_IN_TEXT",
        PlanReason.AmountNotInText => "AMOUNT_NOT_IN_TEXT",
        PlanReason.AmountFractionTooLong => "AMOUNT_FRACTION_TOO_LONG",
        PlanReason.PlanMismatch => "PLAN_MISMATCH",
        PlanReason.FilterMultipleKeys => "FILTER_MULTIPLE_KEYS",
        PlanReason.PeriodFieldMismatch => "PERIOD_FIELD_MISMATCH",
        PlanReason.ModeFieldMismatch => "MODE_FIELD_MISMATCH",
        PlanReason.SourceFieldMismatch => "SOURCE_FIELD_MISMATCH",
        PlanReason.InstrumentsDuplicate => "INSTRUMENTS_DUPLICATE",
        PlanReason.TargetCurrencySet => "TARGET_CURRENCY_SET",
        PlanReason.IncomeSlugSet => "INCOME_SLUG_SET",
        PlanReason.TemplateLength => "TEMPLATE_LENGTH",
        PlanReason.TemplateNotNfc => "TEMPLATE_NOT_NFC",
        PlanReason.TemplateLang => "TEMPLATE_LANG",
        PlanReason.TemplatePlanNotAllowed => "TEMPLATE_PLAN_NOT_ALLOWED",
        PlanReason.TemplatePlaceholder => "TEMPLATE_PLACEHOLDER",
        PlanReason.TemplateDigit => "TEMPLATE_DIGIT",
        PlanReason.TemplateBadBlank => "TEMPLATE_BAD_BLANK",
        PlanReason.TemplateDuplicateBlank => "TEMPLATE_DUPLICATE_BLANK",
        PlanReason.TemplateAt => "TEMPLATE_AT",
        PlanReason.TemplateLink => "TEMPLATE_LINK",
        PlanReason.TemplateMarkup => "TEMPLATE_MARKUP",
        PlanReason.TemplateControl => "TEMPLATE_CONTROL",
        PlanReason.TemplateEmoji => "TEMPLATE_EMOJI",
        PlanReason.TemplateScript => "TEMPLATE_SCRIPT",
        PlanReason.TemplatePlainName => "TEMPLATE_PLAIN_NAME",
        _ => throw new ArgumentOutOfRangeException(nameof(reason)),
    };
}
