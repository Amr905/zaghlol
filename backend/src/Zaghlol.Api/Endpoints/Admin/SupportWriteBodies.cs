using System.Text.Json;
using System.Text.RegularExpressions;
using Zaghlol.Application.Audit;
using Zaghlol.Application.Support;
using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints.Admin;

/// <summary>
/// The strict bodies of the three support writes (backend-api 5.3, T-186). Hand-parsed so the order ID is only ever read into a
/// <see cref="Sensitive{T}"/>, no member name or value is echoed, and no unknown, duplicate, missing or mistyped member is accepted:
/// an unknown member is <c>UNKNOWN_FIELD</c>, anything else wrong is <c>VALIDATION_FAILED</c>.
/// </summary>
internal static partial class SupportWriteBodies
{
    private const int MaxDepth = 4;

    /// <summary>OpenAPI <c>OwnershipCheck.pattern</c>.</summary>
    [GeneratedRegex(@"^[A-Za-z0-9.-]{6,64}\z")]
    private static partial Regex OrderIdPattern();

    public static (SupportSeatMoveCommand? Command, string? Error) ParseMove(ReadOnlyMemory<byte> utf8, Guid operatorId)
    {
        var read = Read(
            utf8,
            ["purchaseId", "toInstallId", "reasonCode", "ticketRef", "ownershipCheck", "attachToAccount", "correctsAuditId"],
            ["purchaseId", "toInstallId", "reasonCode", "ticketRef", "ownershipCheck"]);
        if (read.Members is not { } m)
        {
            return (null, read.Error);
        }

        if (!Uuid(m, "purchaseId", out var purchase)
            || !m["toInstallId"].TryGetString(out var to) || !InstallId.TryParse(to, out var install)
            || !m["reasonCode"].TryGetString(out var reasonText) || !SupportReasons.TryParse(reasonText, out var reason)
            || !Ticket(m, out var ticket)
            || !Order(m, out var order))
        {
            return (null, ErrorCodes.ValidationFailed);
        }

        var attach = false;
        if (m.TryGetValue("attachToAccount", out var attachElement))
        {
            if (attachElement.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            {
                return (null, ErrorCodes.ValidationFailed);
            }

            attach = attachElement.GetBoolean();
        }

        long? corrects = null;
        if (m.TryGetValue("correctsAuditId", out var correctsElement))
        {
            if (!AuditId(correctsElement, out var id))
            {
                return (null, ErrorCodes.ValidationFailed);
            }

            corrects = id;
        }

        // `correction` <=> correctsAuditId; and a correction reverses a move, it never links an account.
        var correction = reason == SupportReason.Correction;
        if (correction != corrects.HasValue || (correction && attach))
        {
            return (null, ErrorCodes.ValidationFailed);
        }

        return (new SupportSeatMoveCommand(operatorId, purchase, install, reason, ticket, order, attach, corrects), null);
    }

    public static (SupportDetachCommand? Command, string? Error) ParseDetach(ReadOnlyMemory<byte> utf8, Guid operatorId)
    {
        var read = Read(
            utf8,
            ["purchaseId", "reasonCode", "ticketRef", "ownershipCheck", "correctsAuditId"],
            ["purchaseId", "reasonCode", "ticketRef", "ownershipCheck", "correctsAuditId"]);
        if (read.Members is not { } m)
        {
            return (null, read.Error);
        }

        if (!Uuid(m, "purchaseId", out var purchase)
            || !m["reasonCode"].TryGetString(out var reason) || !string.Equals(reason, "correction", StringComparison.Ordinal)
            || !Ticket(m, out var ticket)
            || !Order(m, out var order)
            || !AuditId(m["correctsAuditId"], out var corrects))
        {
            return (null, ErrorCodes.ValidationFailed);
        }

        return (new SupportDetachCommand(operatorId, purchase, ticket, order, corrects), null);
    }

    public static (SupportUnfreezeCommand? Command, string? Error) ParseUnfreeze(ReadOnlyMemory<byte> utf8, Guid operatorId)
    {
        var read = Read(utf8, ["purchaseId", "ticketRef", "ownershipCheck"], ["purchaseId", "ticketRef", "ownershipCheck"]);
        if (read.Members is not { } m)
        {
            return (null, read.Error);
        }

        if (!Uuid(m, "purchaseId", out var purchase) || !Ticket(m, out var ticket) || !Order(m, out var order))
        {
            return (null, ErrorCodes.ValidationFailed);
        }

        return (new SupportUnfreezeCommand(operatorId, purchase, ticket, order), null);
    }

    private static (Dictionary<string, JsonElement>? Members, string? Error) Read(ReadOnlyMemory<byte> utf8, string[] allowed, string[] required)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(utf8, new JsonDocumentOptions { MaxDepth = MaxDepth });
        }
        catch (JsonException)
        {
            return (null, ErrorCodes.ValidationFailed);
        }

        using (document)
        {
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                return (null, ErrorCodes.ValidationFailed);
            }

            var members = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
            var duplicate = false;
            foreach (var member in document.RootElement.EnumerateObject())
            {
                if (!allowed.Contains(member.Name, StringComparer.Ordinal))
                {
                    return (null, ErrorCodes.UnknownField);
                }

                duplicate |= !members.TryAdd(member.Name, member.Value.Clone());
            }

            return duplicate || required.Any(name => !members.ContainsKey(name)) ? (null, ErrorCodes.ValidationFailed) : (members, null);
        }
    }

    private static bool Uuid(Dictionary<string, JsonElement> members, string name, out Guid value)
    {
        value = default;
        return members[name].TryGetString(out var text) && Guid.TryParseExact(text, "D", out value) && value != Guid.Empty;
    }

    private static bool Ticket(Dictionary<string, JsonElement> members, out string ticket)
    {
        ticket = string.Empty;
        if (!members["ticketRef"].TryGetString(out var text) || !SupportTicketRef.IsValid(text))
        {
            return false;
        }

        ticket = text;
        return true;
    }

    private static bool Order(Dictionary<string, JsonElement> members, out Sensitive<string> order)
    {
        order = default;
        if (!members["ownershipCheck"].TryGetString(out var text) || !OrderIdPattern().IsMatch(text))
        {
            return false;
        }

        order = new Sensitive<string>(text);
        return true;
    }

    private static bool AuditId(JsonElement element, out long id)
    {
        id = 0;
        return element.ValueKind == JsonValueKind.Number && element.TryGetInt64(out id) && id >= 1;
    }

    private static bool TryGetString(this JsonElement element, out string text)
    {
        text = element.ValueKind == JsonValueKind.String ? element.GetString() ?? string.Empty : string.Empty;
        return element.ValueKind == JsonValueKind.String;
    }
}
