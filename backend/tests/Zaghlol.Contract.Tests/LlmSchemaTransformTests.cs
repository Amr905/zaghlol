using System.Text.Json;
using System.Text.Json.Nodes;
using Zaghlol.Infrastructure.Llm;

namespace Zaghlol.Contract.Tests;

/// <summary>T-338 AC3: the schema copy sent to Vertex and Anthropic accepts and rejects exactly the same T-322 vectors as the original.</summary>
public class LlmSchemaTransformTests
{
    [Fact]
    public void TheTransformedSchemaGivesTheSameVerdictOnEveryPlanVector()
    {
        var original = LlmContractFiles.AskPlanSchemaFile();
        using var element = JsonDocument.Parse(original.ToJsonString());
        var transformed = (JsonObject)LlmSchemaTransforms.ForProvider(element.RootElement);

        Assert.False(transformed.ContainsKey("$schema") || transformed.ContainsKey("$id") || transformed.ContainsKey("$comment"));

        // Both compiled with the same draft (the file's $schema is removed from the copy, so the default draft applies there).
        var before = LlmContractFiles.Compile(original);
        var after = LlmContractFiles.Compile(transformed);
        var vectors = LlmContractFiles.Vectors("ask-plan-v1.json")["plans"]!.AsArray();
        var accepted = 0;
        var rejected = 0;
        foreach (var vector in vectors)
        {
            var plan = vector!["plan"];
            var a = LlmContractFiles.IsValid(before, plan);
            Assert.Equal(a, LlmContractFiles.IsValid(after, plan));
            if (a)
            {
                accepted++;
            }
            else
            {
                rejected++;
            }
        }

        Assert.True(accepted > 0 && rejected > 0);
    }

    [Fact]
    public void ThePureFunctionDoesNotChangeItsInputOrAnythingBelowTheRoot()
    {
        using var element = JsonDocument.Parse("""{"$schema":"s","$id":"i","$comment":"c","type":"object","properties":{"$comment":{"type":"string"}}}""");
        var raw = element.RootElement.GetRawText();

        var result = (JsonObject)LlmSchemaTransforms.ForProvider(element.RootElement);

        Assert.Equal(raw, element.RootElement.GetRawText());
        Assert.Equal(["type", "properties"], result.Select(p => p.Key).ToArray());
        Assert.True(result["properties"]!.AsObject().ContainsKey("$comment"));
    }
}
