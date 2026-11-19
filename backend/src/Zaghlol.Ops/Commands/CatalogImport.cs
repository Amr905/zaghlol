using System.Text.Json;
using System.Text.Json.Nodes;

namespace Zaghlol.Ops.Commands;

/// <summary>One call of a catalog import, fully validated before any call is made.</summary>
internal sealed record PlannedCall(HttpMethod Method, string Path, JsonNode? Body, string Label);

/// <summary>
/// The file format of <c>catalog import</c>: <c>{"entries":[ ... ]}</c>, each entry <c>entity</c> plus either a <c>delete: true</c>,
/// or a <c>body</c> (a merchant without a key is created; any other entry is put under its key). The key is <c>key</c>, or
/// <c>merchant</c> + <c>alias</c>, or <c>lang</c> + <c>keyword</c>. Unknown members are refused. Messages name an entry number only.
/// </summary>
internal static class CatalogImport
{
    public const int MaxEntries = 1000;

    private static readonly string[] EntryMembers = ["entity", "key", "merchant", "alias", "lang", "keyword", "body", "delete"];

    public static IReadOnlyList<PlannedCall>? Plan(JsonElement root, out string? error)
    {
        error = null;
        var members = root.EnumerateObject().ToList();
        if (members.Count != 1 || members[0].Name != "entries" || members[0].Value.ValueKind != JsonValueKind.Array)
        {
            error = "The file must be {\"entries\": [ ... ]} and nothing else.";
            return null;
        }

        var entries = members[0].Value.EnumerateArray().ToList();
        if (entries.Count is 0 or > MaxEntries)
        {
            error = "The file must hold 1 to " + MaxEntries.ToString(System.Globalization.CultureInfo.InvariantCulture) + " entries.";
            return null;
        }

        var plan = new List<PlannedCall>();
        for (var i = 0; i < entries.Count; i++)
        {
            var call = PlanEntry(entries[i], out var problem);
            if (call is null)
            {
                error = "Entry " + (i + 1).ToString(System.Globalization.CultureInfo.InvariantCulture) + ": " + problem;
                return null;
            }

            plan.Add(call);
        }

        return plan;
    }

    private static PlannedCall? PlanEntry(JsonElement entry, out string? problem)
    {
        problem = null;
        if (entry.ValueKind != JsonValueKind.Object || entry.EnumerateObject().Any(p => !EntryMembers.Contains(p.Name, StringComparer.Ordinal)))
        {
            problem = "must be an object with only entity, key, merchant, alias, lang, keyword, body, delete.";
            return null;
        }

        string? Text(string name) => entry.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString()
            : entry.TryGetProperty(name, out var n) && n.ValueKind == JsonValueKind.Number ? n.GetRawText() : null;

        var entity = Text("entity");
        var delete = entry.TryGetProperty("delete", out var d) && d.ValueKind == JsonValueKind.True;
        var hasBody = entry.TryGetProperty("body", out var body);
        if (entity is null || delete == hasBody || (hasBody && body.ValueKind != JsonValueKind.Object))
        {
            problem = "needs an entity and exactly one of body (an object) or delete: true.";
            return null;
        }

        var hasKey = entry.TryGetProperty("key", out _) || entry.TryGetProperty("merchant", out _) || entry.TryGetProperty("lang", out _);
        if (entity == "merchants" && hasBody && !hasKey)
        {
            return new PlannedCall(HttpMethod.Post, "/admin/v1/catalog/draft/merchants", JsonNode.Parse(body.GetRawText()), "merchants (create)");
        }

        var key = CatalogCommands.KeyFrom(entity, Text("key"), Text("merchant"), Text("alias"), Text("lang"), Text("keyword"), out var keyError);
        if (key is null)
        {
            problem = keyError;
            return null;
        }

        var path = "/admin/v1/catalog/draft/" + entity + "/" + Uri.EscapeDataString(key);
        return delete
            ? new PlannedCall(HttpMethod.Delete, path, null, entity + " " + key)
            : new PlannedCall(HttpMethod.Put, path, JsonNode.Parse(body.GetRawText()), entity + " " + key);
    }
}
