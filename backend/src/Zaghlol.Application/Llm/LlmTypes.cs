using System.Text.Json;
using System.Text.Json.Serialization;
using Zaghlol.Domain;

namespace Zaghlol.Application.Llm;

/// <summary>Which feature a provider call is for (the spend ledger and quotas key on it).</summary>
public enum LlmFeature
{
    Ask,
    Categorise,
}

/// <summary>
/// The result class of one provider call (ask-llm.md §3). <see cref="Ok"/> carries valid JSON text; <see cref="Invalid"/> is a
/// reply that is not usable (malformed JSON, cut off); <see cref="Refused"/> is a model refusal; <see cref="Timeout"/> and
/// <see cref="Upstream"/> (5xx, transport error, open circuit) are provider-side failures.
/// </summary>
public enum LlmOutcome
{
    Ok,
    Invalid,
    Timeout,
    Upstream,
    Refused,
}

/// <summary>Token usage of one call: input, of which cached, and output.</summary>
public sealed record LlmUsage(int InputTokens, int CachedTokens, int OutputTokens)
{
    public static LlmUsage None { get; } = new(0, 0, 0);
}

/// <summary>
/// One structured-output request. <paramref name="UserText"/> is the (scrubbed, placeholdered) question and is sensitive: it never
/// reaches a log, a span, an exception or <see cref="object.ToString"/>; serialising the record writes <c>"***"</c> for it.
/// </summary>
public sealed record LlmCall(
    LlmFeature Feature,
    string PromptId,
    LlmSensitive<string> UserText,
    string Lang,
    JsonElement OutputSchema,
    int MaxOutputTokens);

/// <summary>The outcome, the reply JSON (sensitive: it may echo the question) and the usage. Serialising writes <c>"***"</c> for the JSON.</summary>
public sealed record LlmResult(
    LlmOutcome Outcome,
    LlmSensitive<byte[]> Json,
    LlmUsage Usage)
{
    /// <summary>True only when the request provably never reached the provider (open circuit, connection refused). Such a call costs nothing; every other zero-usage result is unknown usage.</summary>
    public bool NeverSent { get; init; }

    public static LlmResult Failed(LlmOutcome outcome, LlmUsage? usage = null) =>
        new(outcome, new LlmSensitive<byte[]>([]), usage ?? LlmUsage.None);

    public static LlmResult NotSent() => Failed(LlmOutcome.Upstream) with { NeverSent = true };
}

/// <summary>One provider adapter (<c>OpenAiResponsesProvider</c>, the fake, later Vertex Gemini).</summary>
public interface ILlmProvider
{
    string Id { get; }

    Task<LlmResult> CompleteAsync(LlmCall request, CancellationToken cancellationToken);
}

/// <summary>
/// The provider API keys, loaded once at start from the active KMS provider's secret store (T-333). A provider without a key is
/// paused: <see cref="HasKey"/> is false and <see cref="GetKeyAsync"/> throws <see cref="LlmServicePausedException"/>. The key is
/// never logged or cached by callers; <see cref="LlmSensitive{T}"/> writes <c>***</c> wherever it is printed or serialised.
/// </summary>
public interface ILlmApiKeyProvider
{
    bool HasKey(string providerId);

    ValueTask<LlmSensitive<string>> GetKeyAsync(string providerId, CancellationToken cancellationToken);
}

/// <summary>
/// The LLM module can't serve this call (no key for the provider, T-333): the endpoints answer <c>LLM_SERVICE_PAUSED</c>. Not a
/// provider failure (never counted by the circuit). The message is constant.
/// </summary>
public sealed class LlmServicePausedException : SafeException
{
    public const string DefaultMessage = "The LLM provider has no API key; the LLM module is paused.";

    public LlmServicePausedException()
        : base(DefaultMessage)
    {
    }

    public LlmServicePausedException(string message)
        : base(message)
    {
    }

    public LlmServicePausedException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>The static system prompt for a <see cref="LlmCall.PromptId"/> (the files are T-339's).</summary>
public interface ILlmPromptCatalog
{
    string GetSystemPrompt(string promptId);
}

/// <summary>The active provider id: remote config <c>llm.provider</c>, read on every call, else <c>Llm:ActiveProvider</c> (T-334).</summary>
public interface IActiveLlmProviderId
{
    ValueTask<string> CurrentAsync(CancellationToken cancellationToken);
}

/// <summary>Resolves the active provider; an unknown id fails closed.</summary>
public interface ILlmProviderRegistry
{
    ValueTask<string> ActiveIdAsync(CancellationToken cancellationToken);

    ValueTask<ILlmProvider> ActiveAsync(CancellationToken cancellationToken);

    ILlmProvider Resolve(string id);
}

/// <summary>Writes a fixed redaction for a sensitive member; never reads.</summary>
public sealed class RedactedJsonConverter<T> : JsonConverter<T>
{
    public const string Redaction = "***";

    public override T Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        throw new NotSupportedException("A redacted member can't be read.");

    public override void Write(Utf8JsonWriter writer, T value, JsonSerializerOptions options)
    {
        ArgumentNullException.ThrowIfNull(writer);
        writer.WriteStringValue(Redaction);
    }
}

/// <summary>A configuration problem of the LLM gateway; the message is constant and never carries a value.</summary>
public sealed class LlmConfigurationException(string message) : Exception(message);

/// <summary>Whether an id names a provider this host has configured (FU-411: <c>PUT llm.provider</c> refuses an id with no adapter).</summary>
public interface IKnownLlmProviderIds
{
    bool IsKnown(string providerId);
}
