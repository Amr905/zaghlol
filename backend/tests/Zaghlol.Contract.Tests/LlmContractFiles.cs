using System.Text.Json.Nodes;
using Json.Schema;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// Loads the LLM contract files (T-322): the two JSON Schemas under <c>backend/contracts</c>, the shared vectors and the
/// fake-backend fixtures. The csproj copies them next to the test assembly.
/// </summary>
internal static class LlmContractFiles
{
    private static readonly EvaluationOptions Options = new() { OutputFormat = OutputFormat.List, RequireFormatValidation = true };

    public static JsonObject Contract(string relativePath) => Load(Path.Combine("contracts", relativePath));

    public static JsonObject Vectors(string name) => Load(Path.Combine("vectors", name));

    /// <summary>The whole schema file, without <c>$id</c> so that it can be compiled more than once.</summary>
    public static JsonObject AskPlanSchemaFile() => WithoutId(Contract("ask-plan-v1.schema.json"));

    public static JsonObject CatResultSchemaFile() => WithoutId(Contract("cat-result-v1.schema.json"));

    public static JsonSchema Compile(JsonObject schemaFile) => JsonSchema.FromText(schemaFile.ToJsonString());

    /// <summary>A schema that applies <c>$defs/&lt;def&gt;</c> of <paramref name="schemaFile"/> to the instance.</summary>
    public static JsonSchema CompileDef(JsonObject schemaFile, string def)
    {
        var root = new JsonObject
        {
            ["$schema"] = schemaFile["$schema"]!.GetValue<string>(),
            ["$ref"] = "#/$defs/" + def,
            ["$defs"] = JsonNode.Parse(schemaFile["$defs"]!.ToJsonString()),
        };
        return JsonSchema.FromText(root.ToJsonString());
    }

    public static bool IsValid(JsonSchema schema, JsonNode? instance) => schema.Evaluate(instance, Options).IsValid;

    private static JsonObject WithoutId(JsonObject file)
    {
        var copy = JsonNode.Parse(file.ToJsonString())!.AsObject();
        copy.Remove("$id");
        return copy;
    }

    private static JsonObject Load(string relativePath)
    {
        var path = Path.Combine(AppContext.BaseDirectory, relativePath);
        return JsonNode.Parse(File.ReadAllText(path))!.AsObject();
    }
}
