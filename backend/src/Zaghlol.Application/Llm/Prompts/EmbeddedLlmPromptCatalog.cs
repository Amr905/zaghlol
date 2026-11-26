using System.Collections.Concurrent;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Zaghlol.Application.Llm.Prompts;

/// <summary>Names of the shipped prompts.</summary>
public static class LlmPromptIds
{
    public const string AskPlanV1 = "ask-plan-v1";
}

/// <summary>
/// The static system prompts, embedded in this assembly (<c>Llm/Prompts/*.txt</c>, ask-llm §2.5). They hold no user data and no per-request
/// text, so the provider's prefix caching applies. An unknown id fails closed with a constant message.
/// </summary>
public sealed class EmbeddedLlmPromptCatalog : ILlmPromptCatalog
{
    private const string ResourcePrefix = "Zaghlol.Llm.Prompts.";

    private static readonly ConcurrentDictionary<string, string> Cache = new(StringComparer.Ordinal);

    public string GetSystemPrompt(string promptId)
    {
        ArgumentNullException.ThrowIfNull(promptId);
        return Cache.GetOrAdd(promptId, Load);
    }

    /// <summary>The first 12 hex characters of SHA-256 of the prompt text: the value recorded in metrics so a prompt change is visible (never the text).</summary>
    public static string HashPrefix(string promptText)
    {
        ArgumentNullException.ThrowIfNull(promptText);
        return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(promptText)))[..12];
    }

    private static string Load(string promptId)
    {
        var name = ResourcePrefix + promptId + ".txt";
        using var stream = typeof(EmbeddedLlmPromptCatalog).Assembly.GetManifestResourceStream(name)
            ?? throw new LlmConfigurationException("The LLM prompt is not embedded.");
        using var reader = new StreamReader(stream, Encoding.UTF8);
        return reader.ReadToEnd().Replace("\r\n", "\n", StringComparison.Ordinal).TrimEnd('\n');
    }
}

/// <summary>The <c>ask-plan/1</c> JSON Schema file as the provider's structured-output schema (the same file the validator embeds).</summary>
public static class AskPlanContract
{
    private const string SchemaResource = "Zaghlol.Llm.ask-plan-v1.schema.json";

    private static readonly Lazy<JsonElement> SchemaElement = new(Load);

    public static JsonElement Schema => SchemaElement.Value;

    private static JsonElement Load()
    {
        using var stream = typeof(AskPlanContract).Assembly.GetManifestResourceStream(SchemaResource)
            ?? throw new LlmConfigurationException("The ask-plan schema is not embedded.");
        using var document = JsonDocument.Parse(stream);
        return document.RootElement.Clone();
    }
}
