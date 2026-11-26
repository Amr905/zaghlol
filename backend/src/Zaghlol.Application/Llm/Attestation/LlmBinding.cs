using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Zaghlol.Domain;

namespace Zaghlol.Application.Llm.Attestation;

/// <summary>
/// The body binding of the LLM endpoints (ask-llm.md §5; vectors <c>ask-binding-v1.json</c>, <c>cat-binding-v1.json</c>):
/// <c>bodyHash = SHA-256(prefix ‖ 0x00 ‖ installId ‖ 0x00 ‖ JCS(body without the top-level "attestation"))</c>, the Play
/// <c>requestHash = base64url(bodyHash)</c> and the App Attest <c>clientDataHash = SHA-256(clientDataPrefix ‖ 0x00 ‖ bodyHash)</c>.
/// The JCS is written from the same <see cref="JsonElement"/> the endpoint binds (parsed once, duplicate members refused by the
/// caller), so the hashed and the processed body can't differ. Nothing here logs or keeps the body.
/// </summary>
public static class LlmBinding
{
    public const string AskPrefix = "zaghlol-ask-v1";
    public const string AskClientDataPrefix = "zaghlol-ask-attest-v1";
    public const string CategorisePrefix = "zaghlol-cat-v1";
    public const string CategoriseClientDataPrefix = "zaghlol-cat-attest-v1";
    public const int HashLength = 32;

    /// <summary>2^53: the largest integer every JSON implementation (and RFC 8785's ES6 number form) writes exactly.</summary>
    private const decimal MaxSafeInteger = 9_007_199_254_740_992m;

    public static string Prefix(LlmFeature feature) => feature switch
    {
        LlmFeature.Ask => AskPrefix,
        LlmFeature.Categorise => CategorisePrefix,
        _ => throw new ArgumentOutOfRangeException(nameof(feature)),
    };

    public static string ClientDataPrefix(LlmFeature feature) => feature switch
    {
        LlmFeature.Ask => AskClientDataPrefix,
        LlmFeature.Categorise => CategoriseClientDataPrefix,
        _ => throw new ArgumentOutOfRangeException(nameof(feature)),
    };

    /// <summary>
    /// The install-bound body hash, or <c>null</c> when <paramref name="root"/> is not an object, holds a number that is not an
    /// integer within ±2^53, or a string with a lone surrogate (the caller answers <c>VALIDATION_FAILED</c>).
    /// </summary>
    public static byte[]? BodyHash(LlmFeature feature, InstallId installId, JsonElement root)
    {
        if (Canonical(root) is not { } jcs)
        {
            return null;
        }

        return BodyHash(feature, installId, jcs);
    }

    /// <summary>The body hash over an already canonical UTF-8 JCS text.</summary>
    public static byte[] BodyHash(LlmFeature feature, InstallId installId, ReadOnlySpan<byte> jcsUtf8)
    {
        using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        sha.AppendData(Encoding.ASCII.GetBytes(Prefix(feature)));
        sha.AppendData([0]);
        sha.AppendData(Encoding.ASCII.GetBytes(installId.Value.ToString("D", CultureInfo.InvariantCulture)));
        sha.AppendData([0]);
        sha.AppendData(jcsUtf8);
        return sha.GetHashAndReset();
    }

    /// <summary>The App Attest <c>clientDataHash</c> for <paramref name="bodyHash"/>.</summary>
    public static byte[] ClientDataHash(LlmFeature feature, ReadOnlySpan<byte> bodyHash)
    {
        if (bodyHash.Length != HashLength)
        {
            throw new ArgumentException("bodyHash must be 32 bytes.", nameof(bodyHash));
        }

        using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        sha.AppendData(Encoding.ASCII.GetBytes(ClientDataPrefix(feature)));
        sha.AppendData([0]);
        sha.AppendData(bodyHash);
        return sha.GetHashAndReset();
    }

    /// <summary>RFC 8785 UTF-8 bytes of <paramref name="root"/> without its top-level <c>attestation</c>; <c>null</c> as in <see cref="BodyHash(LlmFeature, InstallId, JsonElement)"/>.</summary>
    public static byte[]? Canonical(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var output = new StringBuilder();
        try
        {
            return Write(root, output, skipAttestation: true) && !HasLoneSurrogate(output) ? Encoding.UTF8.GetBytes(output.ToString()) : null;
        }
        catch (InvalidOperationException)
        {
            // A string escape the reader can't turn into UTF-16: no hash, never echoed.
            return null;
        }
    }

    private static bool Write(JsonElement element, StringBuilder output, bool skipAttestation)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Object:
                output.Append('{');
                var first = true;
                foreach (var member in element.EnumerateObject()
                             .Where(m => !(skipAttestation && m.Name == "attestation"))
                             .OrderBy(m => m.Name, StringComparer.Ordinal))
                {
                    if (!first)
                    {
                        output.Append(',');
                    }

                    first = false;
                    WriteString(member.Name, output);
                    output.Append(':');
                    if (!Write(member.Value, output, skipAttestation: false))
                    {
                        return false;
                    }
                }

                output.Append('}');
                return true;

            case JsonValueKind.Array:
                output.Append('[');
                var index = 0;
                foreach (var item in element.EnumerateArray())
                {
                    if (index++ > 0)
                    {
                        output.Append(',');
                    }

                    if (!Write(item, output, skipAttestation: false))
                    {
                        return false;
                    }
                }

                output.Append(']');
                return true;

            case JsonValueKind.String:
                WriteString(element.GetString()!, output);
                return true;

            case JsonValueKind.Number:
                if (!element.TryGetDecimal(out var number) || number != decimal.Truncate(number) || Math.Abs(number) > MaxSafeInteger)
                {
                    return false;
                }

                // ES6 Number.prototype.toString for an integer: plain digits, no exponent, "-0" is "0".
                output.Append(((long)number).ToString(CultureInfo.InvariantCulture));
                return true;

            case JsonValueKind.True:
                output.Append("true");
                return true;

            case JsonValueKind.False:
                output.Append("false");
                return true;

            case JsonValueKind.Null:
                output.Append("null");
                return true;

            default:
                return false;
        }
    }

    private static void WriteString(string text, StringBuilder output)
    {
        output.Append('"');
        foreach (var c in text)
        {
            switch (c)
            {
                case '"':
                    output.Append("\\\"");
                    break;
                case '\\':
                    output.Append("\\\\");
                    break;
                case '\b':
                    output.Append("\\b");
                    break;
                case '\f':
                    output.Append("\\f");
                    break;
                case '\n':
                    output.Append("\\n");
                    break;
                case '\r':
                    output.Append("\\r");
                    break;
                case '\t':
                    output.Append("\\t");
                    break;
                case < ' ':
                    output.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                    break;
                default:
                    output.Append(c);
                    break;
            }
        }

        output.Append('"');
    }

    private static bool HasLoneSurrogate(StringBuilder text)
    {
        for (var i = 0; i < text.Length; i++)
        {
            if (char.IsHighSurrogate(text[i]) && i + 1 < text.Length && char.IsLowSurrogate(text[i + 1]))
            {
                i++;
            }
            else if (char.IsSurrogate(text[i]))
            {
                return true;
            }
        }

        return false;
    }
}
