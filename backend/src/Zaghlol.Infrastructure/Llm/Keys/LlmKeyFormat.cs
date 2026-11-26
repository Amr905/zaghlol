using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Zaghlol.Infrastructure.Llm.Keys;

/// <summary>What a provider's secret looks like (T-333).</summary>
internal enum LlmKeyFormat
{
    /// <summary>An API key sent as <c>Authorization: Bearer</c>: 1..1024 visible ASCII characters (no space, CR or LF).</summary>
    BearerToken,

    /// <summary>A Google service-account JSON (Vertex, T-338): a JSON object with <c>type = service_account</c>, <c>client_email</c>, <c>private_key</c>.</summary>
    ServiceAccountJson,
}

/// <summary>Checks a loaded secret. Every refusal is a constant reason: it never quotes, measures or hashes the value.</summary>
internal static partial class LlmKeyFormats
{
    public const int MaxBearerChars = 1024;
    public const int MaxSecretBytes = 8 * 1024;

    public const string EmptyReason = "the value is empty";
    public const string TooLargeReason = "the value is larger than 8 KiB";
    public const string NotUtf8Reason = "the value is not UTF-8 text";
    public const string BearerReason = "an API key must be 1 to 1024 visible ASCII characters (no space, tab, CR or LF)";
    public const string ServiceAccountReason = "a service-account key must be a JSON object with \"type\":\"service_account\" and non-empty \"client_email\" and \"private_key\" strings";

    /// <summary>The provider kind decides the format. A kind without a known format is refused (fail closed).</summary>
    public static LlmKeyFormat For(LlmProviderKind kind) => kind switch
    {
        LlmProviderKind.OpenAiResponses or LlmProviderKind.AnthropicMessages => LlmKeyFormat.BearerToken,
        LlmProviderKind.VertexGemini => LlmKeyFormat.ServiceAccountJson,
        _ => throw new LlmKeyConfigurationException("An LLM provider kind has no known key format."),
    };

    /// <summary>
    /// Provider ids form a file name and a KV path, so they are restricted to 2 to 32 characters: the OpenAPI <c>LlmConsent.provider</c> pattern the app
    /// consents with (FU-417: a longer or one-character id would load a key that no phone can ever consent to).
    /// </summary>
    [GeneratedRegex("^[a-z0-9][a-z0-9-]{1,31}\\z", RegexOptions.CultureInvariant)]
    public static partial Regex ProviderId();

    /// <summary>
    /// The secret text of <paramref name="utf8"/> (one trailing newline removed), or the constant reason it is refused. The caller
    /// zeroes <paramref name="utf8"/>.
    /// </summary>
    public static string? Decode(ReadOnlySpan<byte> utf8, out string? reason)
    {
        if (utf8.Length > MaxSecretBytes)
        {
            reason = TooLargeReason;
            return null;
        }

        try
        {
            reason = null;
            return new UTF8Encoding(false, throwOnInvalidBytes: true).GetString(utf8);
        }
        catch (DecoderFallbackException)
        {
            reason = NotUtf8Reason;
            return null;
        }
    }

    /// <summary>Normalises and checks <paramref name="value"/>; returns the secret, or null with a constant <paramref name="reason"/>.</summary>
    public static string? Check(string value, LlmKeyFormat format, out string? reason)
    {
        ArgumentNullException.ThrowIfNull(value);
        var text = value.EndsWith("\r\n", StringComparison.Ordinal) ? value[..^2]
            : value.EndsWith('\n') ? value[..^1]
            : value;

        if (text.Length == 0)
        {
            reason = EmptyReason;
            return null;
        }

        if (Encoding.UTF8.GetByteCount(text) > MaxSecretBytes)
        {
            reason = TooLargeReason;
            return null;
        }

        reason = format switch
        {
            LlmKeyFormat.BearerToken => IsBearer(text) ? null : BearerReason,
            LlmKeyFormat.ServiceAccountJson => IsServiceAccount(text) ? null : ServiceAccountReason,
            _ => BearerReason,
        };
        return reason is null ? text : null;
    }

    private static bool IsBearer(string text) =>
        text.Length <= MaxBearerChars && !text.AsSpan().ContainsAnyExceptInRange('\x21', '\x7E');

    private static bool IsServiceAccount(string text)
    {
        try
        {
            using var doc = JsonDocument.Parse(text, new JsonDocumentOptions { MaxDepth = 4, AllowDuplicateProperties = false });
            var root = doc.RootElement;
            return root.ValueKind == JsonValueKind.Object
                && root.TryGetProperty("type", out var type) && type.ValueKind == JsonValueKind.String && type.ValueEquals("service_account")
                && NonEmptyString(root, "client_email")
                && NonEmptyString(root, "private_key");
        }
        catch (JsonException)
        {
            // The parser's message can quote the input; it is dropped.
            return false;
        }
    }

    private static bool NonEmptyString(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String && value.GetString() is { Length: > 0 };
}
