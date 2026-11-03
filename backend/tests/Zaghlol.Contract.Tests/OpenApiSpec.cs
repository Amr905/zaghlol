using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using Json.Schema;
using YamlDotNet.RepresentationModel;

namespace Zaghlol.Contract.Tests;

/// <summary>One HTTP operation of the OpenAPI document.</summary>
internal sealed record SpecOperation(string Path, string Method, JsonObject Body)
{
    public string Id => Body["operationId"]!.GetValue<string>();

    public string Label => $"{Method.ToUpperInvariant()} {Path}";
}

/// <summary>
/// Loads <c>backend/openapi/zaghlol-v1.yaml</c> as a JSON tree and evaluates instances against its schemas
/// with JSON Schema 2020-12 (OpenAPI 3.1 schemas are JSON Schema).
/// </summary>
internal sealed class OpenApiSpec
{
    private static readonly string[] HttpMethods = ["get", "put", "post", "delete", "patch"];

    private static readonly string[] SchemaChildKeywords = ["items", "additionalProperties"];

    private static readonly string[] SchemaBranchKeywords = ["oneOf", "anyOf", "allOf"];

    private static readonly JsonSerializerOptions DescribeOptions = new() { WriteIndented = false };

    private readonly string definitionsJson;

    private OpenApiSpec(JsonObject root)
    {
        Root = root;
        Schemas = root["components"]!["schemas"]!.AsObject();
        definitionsJson = Schemas.ToJsonString();
    }

    public JsonObject Root { get; }

    public JsonObject Schemas { get; }

    public static OpenApiSpec Load()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "openapi", "zaghlol-v1.yaml");
        using var reader = new StreamReader(path);
        var stream = new YamlStream();
        stream.Load(reader);
        var root = Convert(stream.Documents[0].RootNode)!.AsObject();
        return new OpenApiSpec(root);
    }

    public IReadOnlyList<SpecOperation> Operations()
    {
        var operations = new List<SpecOperation>();
        foreach (var (path, item) in Root["paths"]!.AsObject())
        {
            var pathItem = item!.AsObject();
            foreach (var method in HttpMethods)
            {
                if (pathItem[method] is JsonObject body)
                {
                    operations.Add(new SpecOperation(path, method, body));
                }
            }
        }

        return operations;
    }

    /// <summary>Follows <c>$ref</c> chains such as <c>#/components/responses/NotFound</c>.</summary>
    public JsonNode Resolve(JsonNode node)
    {
        var current = node;
        while (current is JsonObject obj && obj["$ref"] is JsonValue reference)
        {
            current = Pointer(reference.GetValue<string>());
        }

        return current;
    }

    public JsonNode Pointer(string reference)
    {
        JsonNode node = Root;
        foreach (var segment in reference["#/".Length..].Split('/'))
        {
            node = node[segment] ?? throw new InvalidOperationException($"Unresolvable reference {reference}");
        }

        return node;
    }

    public JsonNode? ResponseSchema(SpecOperation operation, string status, string contentType)
    {
        var response = Resolve(operation.Body["responses"]![status]!);
        return response["content"]?[contentType]?["schema"];
    }

    public static JsonNode? RequestSchema(SpecOperation operation)
    {
        return operation.Body["requestBody"]?["content"]?["application/json"]?["schema"];
    }

    /// <summary>Returns null when valid, otherwise a compact description of the failures.</summary>
    public string? Validate(JsonNode schema, JsonNode? instance)
    {
        var schemaJson = schema.ToJsonString();
        var text = "{\"$schema\":\"https://json-schema.org/draft/2020-12/schema\",\"allOf\":[" + schemaJson + "],\"$defs\":" + definitionsJson + "}";
        text = text
            .Replace("#/components/schemas/", "#/$defs/", StringComparison.Ordinal)
            .Replace("\"format\":\"int32\"", "\"x-format\":\"int32\"", StringComparison.Ordinal);

        var options = new EvaluationOptions { OutputFormat = OutputFormat.List, RequireFormatValidation = true };
        var results = JsonSchema.FromText(text).Evaluate(instance, options);
        return results.IsValid ? null : JsonSerializer.Serialize(results, DescribeOptions);
    }

    /// <summary>
    /// Lists every object schema reachable from <paramref name="node"/> that is not closed, that is, an object
    /// with neither <c>additionalProperties: false</c> nor a typed map (<c>additionalProperties</c> schema).
    /// </summary>
    public void CollectOpenObjects(JsonNode? node, string where, List<string> violations, HashSet<string> seenReferences)
    {
        if (node is not JsonObject schema)
        {
            return;
        }

        if (schema["$ref"] is JsonValue reference)
        {
            var name = reference.GetValue<string>();
            if (seenReferences.Add(name))
            {
                CollectOpenObjects(Resolve(schema), name, violations, seenReferences);
            }

            return;
        }

        var isObject = (schema["type"] is JsonValue type && type.TryGetValue<string>(out var typeName) && typeName == "object")
            || schema["properties"] is not null;
        if (isObject)
        {
            var additional = schema["additionalProperties"];
            var closedOrTypedMap = additional is JsonObject
                || (additional is JsonValue flag && flag.TryGetValue<bool>(out var allowed) && !allowed);
            if (!closedOrTypedMap)
            {
                violations.Add(where);
            }
        }

        if (schema["properties"] is JsonObject properties)
        {
            foreach (var (key, child) in properties)
            {
                CollectOpenObjects(child, $"{where}.{key}", violations, seenReferences);
            }
        }

        foreach (var keyword in SchemaChildKeywords)
        {
            CollectOpenObjects(schema[keyword], $"{where}/{keyword}", violations, seenReferences);
        }

        foreach (var keyword in SchemaBranchKeywords)
        {
            if (schema[keyword] is JsonArray branches)
            {
                for (var i = 0; i < branches.Count; i++)
                {
                    CollectOpenObjects(branches[i], $"{where}/{keyword}[{i.ToString(CultureInfo.InvariantCulture)}]", violations, seenReferences);
                }
            }
        }
    }

    private static JsonNode? Convert(YamlNode node)
    {
        switch (node)
        {
            case YamlMappingNode mapping:
                var obj = new JsonObject();
                foreach (var (key, value) in mapping.Children)
                {
                    obj[((YamlScalarNode)key).Value!] = Convert(value);
                }

                return obj;
            case YamlSequenceNode sequence:
                var array = new JsonArray();
                foreach (var child in sequence.Children)
                {
                    array.Add(Convert(child));
                }

                return array;
            case YamlScalarNode scalar:
                return ConvertScalar(scalar);
            default:
                throw new InvalidOperationException("Unsupported YAML node (anchors and aliases are not used in the spec).");
        }
    }

    private static JsonValue? ConvertScalar(YamlScalarNode scalar)
    {
        if (scalar.Style != YamlDotNet.Core.ScalarStyle.Plain)
        {
            return JsonValue.Create(scalar.Value);
        }

        var text = scalar.Value;
        if (string.IsNullOrEmpty(text) || text is "null" or "~")
        {
            return null;
        }

        if (text is "true")
        {
            return JsonValue.Create(true);
        }

        if (text is "false")
        {
            return JsonValue.Create(false);
        }

        if (long.TryParse(text, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var number))
        {
            return JsonValue.Create(number);
        }

        return JsonValue.Create(text);
    }
}
