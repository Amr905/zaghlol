using System.Globalization;
using System.Text;
using System.Text.Json;
using Zaghlol.Domain;

namespace Zaghlol.Application.Audit;

/// <summary>
/// One <c>audit_log</c> row, minus the operator and the time (T-136 design note §5). The hierarchy is closed: every action
/// has its own sealed record whose members are enums, numbers, IDs or keys the code validated, so an e-mail, an order ID or
/// free text can't be expressed. The database CHECKs (no e-mail or order-ID key at any depth, no <c>@</c> anywhere) are the
/// backstop. <see cref="Details"/> is the JSON written to <c>details</c>.
/// </summary>
public abstract record AuditEntry
{
    private protected AuditEntry()
    {
    }

    /// <summary><c>audit_log.action</c>: a fixed word per record type.</summary>
    public abstract string Action { get; }

    /// <summary><c>audit_log.target</c>.</summary>
    public abstract string Target { get; }

    /// <summary><c>audit_log.details</c> (a JSON object).</summary>
    public string Details()
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            WriteDetails(writer);
            writer.WriteEndObject();
        }

        return Encoding.UTF8.GetString(stream.ToArray());
    }

    private protected abstract void WriteDetails(Utf8JsonWriter writer);
}

/// <summary><c>flag_update</c>: the flag's new value, version and rules (T-126).</summary>
/// <param name="RulesJson">The stored rules as the flag store serialises them (platforms, minAppVersion, rolloutPercent).</param>
public sealed record FlagUpdateAudit(string Key, bool Value, int Version, string RulesJson) : AuditEntry
{
    public override string Action => "flag_update";

    public override string Target => "flag:" + Key;

    private protected override void WriteDetails(Utf8JsonWriter writer)
    {
        writer.WriteBoolean("value", Value);
        writer.WriteNumber("version", Version);
        writer.WritePropertyName("rules");
        writer.WriteRawValue(RulesJson);
    }
}

/// <summary>
/// <c>config_update</c>: the key, its new canonical value (validated against the closed key set, so no free text and no <c>@</c>)
/// and the key's new version (T-334).
/// </summary>
public sealed record ConfigUpdateAudit(string Key, string Value, long Version) : AuditEntry
{
    public override string Action => "config_update";

    public override string Target => "config:" + Key;

    private protected override void WriteDetails(Utf8JsonWriter writer)
    {
        writer.WriteString("value", Value);
        writer.WriteNumber("version", Version);
    }
}

/// <summary>The three draft edits of the catalog admin API (T-125).</summary>
public enum CatalogDraftAction
{
    Create,
    Put,
    Delete,
}

/// <summary><c>catalog_draft_create|put|delete</c>: the entity and the entry's path id (never alias text beyond that).</summary>
public sealed record CatalogDraftAudit(CatalogDraftAction Kind, string Entity, string PathId) : AuditEntry
{
    public override string Action => Kind switch
    {
        CatalogDraftAction.Create => "catalog_draft_create",
        CatalogDraftAction.Put => "catalog_draft_put",
        _ => "catalog_draft_delete",
    };

    public override string Target => Entity + "/" + PathId;

    private protected override void WriteDetails(Utf8JsonWriter writer) => writer.WriteString("entity", Entity);
}

/// <summary><c>catalog_publish</c>: the new version and its op count (never the publish note).</summary>
public sealed record CatalogPublishAudit(int Version, int Ops) : AuditEntry
{
    public override string Action => "catalog_publish";

    public override string Target => string.Create(CultureInfo.InvariantCulture, $"catalog/{Version}");

    private protected override void WriteDetails(Utf8JsonWriter writer)
    {
        writer.WriteNumber("version", Version);
        writer.WriteNumber("ops", Ops);
    }
}

/// <summary><c>catalog_seed_import</c>: row counts only.</summary>
public sealed record CatalogSeedImportAudit(int Categories, int Merchants, int Aliases, int Keywords) : AuditEntry
{
    public override string Action => "catalog_seed_import";

    public override string Target => "catalog";

    private protected override void WriteDetails(Utf8JsonWriter writer)
    {
        writer.WriteNumber("categories", Categories);
        writer.WriteNumber("merchants", Merchants);
        writer.WriteNumber("aliases", Aliases);
        writer.WriteNumber("keywords", Keywords);
    }
}

/// <summary>
/// <c>support_lookup</c> (backend-api §5.2): the target is the install ID, or <c>email:</c> plus the 64-hex
/// <see cref="EmailPseudonym"/>; <c>details.account_id</c> is the matched account. Kept exactly 1 year (D-47).
/// </summary>
public sealed record SupportLookupAudit : AuditEntry
{
    private SupportLookupAudit(string target, string key, IReadOnlyList<Guid> accountIds, int purchases)
    {
        Target = target;
        Key = key;
        AccountIds = accountIds;
        Purchases = purchases;
    }

    public override string Action => "support_lookup";

    public override string Target { get; }

    /// <summary><c>install</c> or <c>email</c>.</summary>
    public string Key { get; }

    /// <summary>The accounts an e-mail lookup matched (empty for an install lookup or no match).</summary>
    public IReadOnlyList<Guid> AccountIds { get; }

    /// <summary>How many purchases the response listed.</summary>
    public int Purchases { get; }

    public static SupportLookupAudit ForInstall(InstallId installId, int purchases) =>
        new(installId.ToString(), "install", [], purchases);

    public static SupportLookupAudit ForEmail(EmailPseudonym pseudonym, IReadOnlyList<Guid> accountIds, int purchases)
    {
        ArgumentNullException.ThrowIfNull(pseudonym);
        ArgumentNullException.ThrowIfNull(accountIds);
        return new("email:" + pseudonym.Hex, "email", accountIds, purchases);
    }

    private protected override void WriteDetails(Utf8JsonWriter writer)
    {
        writer.WriteString("key", Key);
        if (AccountIds.Count > 0)
        {
            writer.WriteString("account_id", AccountIds[0]);
        }

        if (AccountIds.Count > 1)
        {
            writer.WriteStartArray("account_ids");
            foreach (var id in AccountIds)
            {
                writer.WriteStringValue(id);
            }

            writer.WriteEndArray();
        }

        writer.WriteNumber("purchases", Purchases);
    }
}

/// <summary>
/// <c>hex(HMAC-SHA256(K_audit, NFC(trim(lower(email)))))</c>: 64 lowercase hex characters. It can only be built from the
/// 32-byte MAC, so the e-mail itself can never become an audit target.
/// </summary>
public sealed record EmailPseudonym
{
    private EmailPseudonym(string hex) => Hex = hex;

    public string Hex { get; }

    public static EmailPseudonym FromMac(ReadOnlySpan<byte> mac)
    {
        if (mac.Length != 32)
        {
            throw new ArgumentException("An HMAC-SHA256 value is 32 bytes.", nameof(mac));
        }

        return new EmailPseudonym(Convert.ToHexStringLower(mac));
    }

    public override string ToString() => Hex;
}

/// <summary>The two operator decisions on a contribution aggregate (T-129).</summary>
public enum ContributionDecisionKind
{
    Promote,
    Reject,
}

/// <summary>
/// <c>contribution_promote|reject</c>: the institution code and the merchant text as <c>b64u</c> (the text is a public-by-threshold
/// string, but like an alias path id it is kept in its encoded form), plus the draft merchant and category a promote used.
/// </summary>
public sealed record ContributionDecisionAudit(
    ContributionDecisionKind Kind,
    string InstitutionCode,
    string MerchantNormB64,
    int? MerchantId,
    string? CategoryCode) : AuditEntry
{
    public override string Action => Kind == ContributionDecisionKind.Promote ? "contribution_promote" : "contribution_reject";

    public override string Target => "contribution/" + InstitutionCode + ":" + MerchantNormB64;

    private protected override void WriteDetails(Utf8JsonWriter writer)
    {
        writer.WriteString("institution", InstitutionCode);
        if (MerchantId is { } id)
        {
            writer.WriteNumber("merchant_id", id);
        }

        if (CategoryCode is not null)
        {
            writer.WriteString("category", CategoryCode);
        }
    }
}

/// <summary>The operator decisions on AI-category review groups (T-354).</summary>
public enum LlmCatReviewKind
{
    CorrectionPromote,
    CorrectionReject,
    CorrectionPromptIssue,
    ConfirmedPromote,
    ConfirmedReject,
}

/// <summary>
/// <c>llmcat_*</c>: the merchant text as <c>b64u</c> (kept encoded, like an alias path id), the category codes, the number of rows
/// the decision moved and, for a promote, the draft merchant. Never an install hash: the rows hold none that the service reads.
/// </summary>
public sealed record LlmCatReviewAudit(
    LlmCatReviewKind Kind,
    string MerchantNormB64,
    string? AiCategory,
    string Category,
    int Rows,
    int? MerchantId) : AuditEntry
{
    public override string Action => Kind switch
    {
        LlmCatReviewKind.CorrectionPromote => "llmcat_correction_promote",
        LlmCatReviewKind.CorrectionReject => "llmcat_correction_reject",
        LlmCatReviewKind.CorrectionPromptIssue => "llmcat_correction_prompt_issue",
        LlmCatReviewKind.ConfirmedPromote => "llmcat_confirmed_promote",
        _ => "llmcat_confirmed_reject",
    };

    public override string Target => (Kind <= LlmCatReviewKind.CorrectionPromptIssue ? "llmcat/corrections:" : "llmcat/confirmed:") + MerchantNormB64;

    private protected override void WriteDetails(Utf8JsonWriter writer)
    {
        if (AiCategory is not null)
        {
            writer.WriteString("ai_category", AiCategory);
        }

        writer.WriteString("category", Category);
        writer.WriteNumber("rows", Rows);
        if (MerchantId is { } id)
        {
            writer.WriteNumber("merchant_id", id);
        }
    }
}

/// <summary>The ownership-check outcomes an audit row can name (backend-api 5.3 <c>ownership_outcome</c>).</summary>
public static class SupportOwnershipOutcomes
{
    public const string Pass = "pass";
    public const string Fail = "fail";
    public const string Unavailable = "unavailable";
    public const string NotRun = "not_run";
}

/// <summary>The <c>outcome</c> values of the three support audit rows (backend-api 5.3).</summary>
public static class SupportOutcomes
{
    public const string Moved = "moved";
    public const string Attached = "attached";
    public const string MovedAndAttached = "moved_and_attached";
    public const string Detached = "detached";
    public const string Unfrozen = "unfrozen";
    public const string Noop = "noop";
    public const string Refused = "refused";
    public const string DisputeFrozen = "dispute_frozen";
    public const string OwnershipFailed = "ownership_failed";
    public const string UpstreamUnavailable = "upstream_unavailable";
}

/// <summary>The support ticket number: never free text, so no personal data can enter an audit row.</summary>
public static partial class SupportTicketRef
{
    public static bool IsValid(string? value) => value is not null && Pattern().IsMatch(value);

    internal static string Require(string value) =>
        IsValid(value) ? value : throw new ArgumentException("The ticket reference is not a ticket number.", nameof(value));

    [System.Text.RegularExpressions.GeneratedRegex(@"^[A-Za-z0-9_-]{1,32}\z")]
    private static partial System.Text.RegularExpressions.Regex Pattern();
}

/// <summary>
/// <c>support_seat_move</c> (backend-api 5.3): one row per call, successful or refused. Install IDs and the account ID are pseudonymous;
/// the order ID has no member here, only the ownership-check outcome.
/// </summary>
public sealed record SupportSeatMoveAudit(
    Guid PurchaseId,
    Guid? FromInstall,
    Guid ToInstall,
    string ReasonCode,
    string TicketRef,
    Guid? AttachedAccountId,
    long? CorrectsAuditId,
    string OwnershipOutcome,
    string Outcome) : AuditEntry
{
    public override string Action => "support_seat_move";

    public override string Target => PurchaseId.ToString("D");

    private protected override void WriteDetails(Utf8JsonWriter writer)
    {
        if (FromInstall is { } from)
        {
            writer.WriteString("from_install", from);
        }

        writer.WriteString("to_install", ToInstall);
        writer.WriteString("reason_code", ReasonCode);
        writer.WriteString("ticket_ref", SupportTicketRef.Require(TicketRef));
        if (AttachedAccountId is { } account)
        {
            writer.WriteString("attached_account_id", account);
        }

        if (CorrectsAuditId is { } corrects)
        {
            writer.WriteNumber("corrects_audit_id", corrects);
        }

        writer.WriteString("ownership_check", "order_id");
        writer.WriteString("ownership_outcome", OwnershipOutcome);
        writer.WriteString("outcome", Outcome);
    }
}

/// <summary><c>support_detach</c> (backend-api 5.3): the correction that removes a support link.</summary>
public sealed record SupportDetachAudit(
    Guid PurchaseId,
    Guid? DetachedAccountId,
    string TicketRef,
    long CorrectsAuditId,
    string OwnershipOutcome,
    string Outcome) : AuditEntry
{
    public override string Action => "support_detach";

    public override string Target => PurchaseId.ToString("D");

    private protected override void WriteDetails(Utf8JsonWriter writer)
    {
        writer.WriteString("reason_code", "correction");
        writer.WriteString("ticket_ref", SupportTicketRef.Require(TicketRef));
        if (DetachedAccountId is { } account)
        {
            writer.WriteString("detached_account_id", account);
        }

        writer.WriteNumber("corrects_audit_id", CorrectsAuditId);
        writer.WriteString("ownership_check", "order_id");
        writer.WriteString("ownership_outcome", OwnershipOutcome);
        writer.WriteString("outcome", Outcome);
    }
}

/// <summary><c>support_unfreeze</c> (backend-api 5.3, R5-5(b)): the correction row that started the freeze and the value that was cleared.</summary>
public sealed record SupportUnfreezeAudit(
    Guid PurchaseId,
    string TicketRef,
    long? FreezeAuditId,
    DateTimeOffset? FrozenUntil,
    string OwnershipOutcome,
    string Outcome) : AuditEntry
{
    public override string Action => "support_unfreeze";

    public override string Target => PurchaseId.ToString("D");

    private protected override void WriteDetails(Utf8JsonWriter writer)
    {
        writer.WriteString("ticket_ref", SupportTicketRef.Require(TicketRef));
        if (FreezeAuditId is { } id)
        {
            writer.WriteNumber("freeze_audit_id", id);
        }
        else
        {
            writer.WriteNull("freeze_audit_id");
        }

        if (FrozenUntil is { } until)
        {
            writer.WriteString("frozen_until", until.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'", CultureInfo.InvariantCulture));
        }
        else
        {
            writer.WriteNull("frozen_until");
        }

        writer.WriteString("ownership_check", "order_id");
        writer.WriteString("ownership_outcome", OwnershipOutcome);
        writer.WriteString("outcome", Outcome);
    }
}
