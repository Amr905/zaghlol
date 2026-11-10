namespace Zaghlol.Application.Operators;

/// <summary>The operator roles (<c>x-required-roles</c> in the OpenAPI file, backend-api §3 and §5.1).</summary>
public static class OperatorRoles
{
    public const string CatalogEditor = "catalog_editor";
    public const string FlagsAdmin = "flags_admin";
    public const string PricesAdmin = "prices_admin";
    public const string SupportViewer = "support_viewer";
    public const string SupportAgent = "support_agent";
    public const string SupportLead = "support_lead";

    /// <summary>Every role the API knows. A role string in an <c>operators</c> row outside this list is dropped.</summary>
    public static IReadOnlyList<string> All { get; } =
        [CatalogEditor, FlagsAdmin, PricesAdmin, SupportViewer, SupportAgent, SupportLead];

    /// <summary>The roles that also need phishing-resistant MFA (R3-9, R4-6).</summary>
    public static IReadOnlyList<string> PhishingResistant { get; } = [SupportAgent, SupportLead];

    public static bool IsKnown(string role) => All.Contains(role, StringComparer.Ordinal);
}

/// <summary>An <c>operators</c> row: the authority for an operator's roles (token group claims are never trusted).</summary>
public sealed record OperatorRecord(Guid Id, IReadOnlyList<string> Roles, bool Disabled);

/// <summary>Reads <c>operators</c> by OIDC subject. Read-only: no runtime code writes operators.</summary>
public interface IOperatorDirectory
{
    /// <summary>The row whose <c>oidc_subject</c> equals <paramref name="subject"/>, or <c>null</c>.</summary>
    Task<OperatorRecord?> FindBySubjectAsync(string subject, CancellationToken cancellationToken);
}
