using System.Text.Json;

namespace Zaghlol.Infrastructure.Llm;

/// <summary>Shared reading of provider replies (T-338 adapters): a size cap, a duplicate-free parse and tolerant accessors.</summary>
internal static class LlmReplyReader
{
    /// <summary>A reply with a repeated property is not trusted (the validators could read a different value than the model "meant").</summary>
    public static readonly JsonDocumentOptions NoDuplicates = new() { AllowDuplicateProperties = false };

    public static async Task<byte[]?> ReadCappedAsync(HttpResponseMessage response, int maxBytes, CancellationToken ct)
    {
        if (response.Content.Headers.ContentLength is { } length && length > maxBytes)
        {
            return null;
        }

        await using var stream = await response.Content.ReadAsStreamAsync(ct);
        using var buffer = new MemoryStream();
        var chunk = new byte[8192];
        int read;
        while ((read = await stream.ReadAsync(chunk, ct)) > 0)
        {
            if (buffer.Length + read > maxBytes)
            {
                return null;
            }

            buffer.Write(chunk, 0, read);
        }

        return buffer.ToArray();
    }

    /// <summary>True when <paramref name="text"/> is one JSON object without duplicate property names.</summary>
    public static bool IsJsonObject(string text)
    {
        try
        {
            using var reply = JsonDocument.Parse(text, NoDuplicates);
            return reply.RootElement.ValueKind == JsonValueKind.Object;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    public static int Int(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var n) && n >= 0
            ? n
            : 0;

    public static string? Str(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    public static int Clamp(long value) => (int)Math.Min(value, int.MaxValue);
}

/// <summary>Pure transforms of the output schema before it goes to a provider (T-338 AC3).</summary>
public static class LlmSchemaTransforms
{
    private static readonly string[] RootAnnotations = ["$schema", "$id", "$comment"];

    /// <summary>
    /// The copy sent to Vertex and Anthropic: the root's <c>$schema</c>, <c>$id</c> and <c>$comment</c> are removed (ask-plan-v1 comment
    /// (1)); nothing else changes. They are annotations or identifiers and do not affect which instances validate, so the transformed
    /// schema accepts and rejects exactly the same documents. Anthropic gets this schema as a plain (non-strict) tool
    /// <c>input_schema</c>, so the numeric bounds and <c>anyOf</c> stay as guidance and the server validation is the gate.
    /// </summary>
    public static System.Text.Json.Nodes.JsonNode ForProvider(JsonElement schema)
    {
        var node = System.Text.Json.Nodes.JsonNode.Parse(schema.GetRawText())!;
        if (node is System.Text.Json.Nodes.JsonObject root)
        {
            foreach (var name in RootAnnotations)
            {
                root.Remove(name);
            }
        }

        return node;
    }
}
