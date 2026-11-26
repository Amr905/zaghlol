using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Zaghlol.Application.Catalog;
using Zaghlol.Application.Llm.Ask;
using Zaghlol.Application.Llm.Attestation;

namespace Zaghlol.Application.Llm.Categorise;

/// <summary>
/// The parsed <c>POST /v1/categorise</c> body. The merchants are sensitive (<c>***</c> in every print and JSON write): the phone sends only business
/// names, but a name is still user-derived text, so it never reaches a log, a metric, a problem body or an exception.
/// <see cref="Keys"/> holds the normalised form of each (<see cref="CatalogText.Normalize"/>), the cache key; it is as sensitive as the name.
/// </summary>
public sealed record CategoriseRequest(
    string RequestId,
    string Lang,
    IReadOnlyList<LlmSensitive<string>> Merchants,
    IReadOnlyList<LlmSensitive<string>> Keys,
    string ConsentProvider,
    int ConsentVersion,
    LlmAttestationProof? Proof,
    bool HasAttestationObject);

public sealed record CategoriseParseResult(CategoriseRequest? Request, AskParseFailure Failure, JsonDocument? Document)
{
    public static CategoriseParseResult Fail(AskParseFailure failure) => new(null, failure, null);
}

/// <summary>
/// Closed, strict parse of the body (llm-categorise §3): exactly the members of the contract, no duplicates, no comments, bounded depth. 1 to
/// <c>cat.batch_max</c> merchants of 2 to 64 characters, unique after normalisation; a longer list is <c>400</c>. Nothing from the body is echoed.
/// </summary>
public static partial class CategoriseRequestParser
{
    public const int MaxMerchantChars = 64;
    public const int MinMerchantChars = 2;
    public const int Version = 1;

    private static readonly string[] Members = ["v", "requestId", "lang", "merchants", "consent", "attestation"];

    private static readonly JsonDocumentOptions DocumentOptions = new()
    {
        AllowTrailingCommas = false,
        CommentHandling = JsonCommentHandling.Disallow,
        MaxDepth = 8,
        AllowDuplicateProperties = false,
    };

    private static readonly UTF8Encoding StrictUtf8 = new(false, true);

    /// <summary>The document is returned so the caller can bind the attestation to the same element; the caller disposes it.</summary>
    public static CategoriseParseResult Parse(ReadOnlyMemory<byte> utf8, int batchMax)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(utf8, DocumentOptions);
        }
        catch (JsonException)
        {
            return CategoriseParseResult.Fail(AskParseFailure.Invalid);
        }

        var result = ParseRoot(document.RootElement, batchMax);
        if (result.Request is null)
        {
            document.Dispose();
            return result;
        }

        return result with { Document = document };
    }

    private static CategoriseParseResult ParseRoot(JsonElement root, int batchMax)
    {
        if (root.ValueKind != JsonValueKind.Object)
        {
            return CategoriseParseResult.Fail(AskParseFailure.Invalid);
        }

        foreach (var member in root.EnumerateObject())
        {
            if (!Members.Contains(member.Name, StringComparer.Ordinal))
            {
                return CategoriseParseResult.Fail(AskParseFailure.UnknownField);
            }
        }

        if (!root.TryGetProperty("consent", out var consent) || consent.ValueKind != JsonValueKind.Object)
        {
            return CategoriseParseResult.Fail(AskParseFailure.Invalid);
        }

        foreach (var member in consent.EnumerateObject())
        {
            if (member.Name is not ("provider" or "v"))
            {
                return CategoriseParseResult.Fail(AskParseFailure.UnknownField);
            }
        }

        LlmAttestationProof? proof = null;
        var hasObject = false;
        if (root.TryGetProperty("attestation", out var attestation))
        {
            var parsed = LlmAttestationProofParser.Parse(attestation);
            if (!parsed.IsValid)
            {
                return CategoriseParseResult.Fail(parsed.Failure == LlmProofParseFailure.UnknownField ? AskParseFailure.UnknownField : AskParseFailure.Invalid);
            }

            proof = parsed.Proof;
            hasObject = attestation.TryGetProperty("attestationObject", out _);
        }

        if (!TryInt(root, "v", out var version) || version != Version
            || Str(root, "requestId") is not { } requestId || !Ulid().IsMatch(requestId)
            || Str(root, "lang") is not { } lang || (lang != "ar" && lang != "en")
            || Str(consent, "provider") is not { } provider || !ProviderPattern().IsMatch(provider)
            || !TryInt(consent, "v", out var consentVersion) || consentVersion < 1
            || !root.TryGetProperty("merchants", out var list) || list.ValueKind != JsonValueKind.Array)
        {
            return CategoriseParseResult.Fail(AskParseFailure.Invalid);
        }

        var count = list.GetArrayLength();
        if (count < 1 || count > Math.Clamp(batchMax, 1, 20))
        {
            return CategoriseParseResult.Fail(AskParseFailure.Invalid);
        }

        var merchants = new List<LlmSensitive<string>>(count);
        var keys = new List<LlmSensitive<string>>(count);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in list.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.String || Text(item) is not { } text || !seen.Add(CatalogText.Normalize(text)))
            {
                return CategoriseParseResult.Fail(AskParseFailure.Invalid);
            }

            merchants.Add(new LlmSensitive<string>(text));
            keys.Add(new LlmSensitive<string>(CatalogText.Normalize(text)));
        }

        return new CategoriseParseResult(
            new CategoriseRequest(requestId, lang, merchants, keys, provider, consentVersion, proof, hasObject),
            AskParseFailure.None,
            null);
    }

    /// <summary>2 to 64 UTF-16 units, no control character, no lone surrogate (a failure is a fixed code, never the text).</summary>
    private static string? Text(JsonElement element)
    {
        string? text;
        try
        {
            text = element.GetString();
        }
        catch (InvalidOperationException)
        {
            return null;
        }

        if (text is null || text.Length is < MinMerchantChars or > MaxMerchantChars || text.Any(char.IsControl))
        {
            return null;
        }

        try
        {
            StrictUtf8.GetByteCount(text);
        }
        catch (EncoderFallbackException)
        {
            return null;
        }

        return text;
    }

    private static string? Str(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.String)
        {
            return null;
        }

        try
        {
            return value.GetString();
        }
        catch (InvalidOperationException)
        {
            return null;
        }
    }

    private static bool TryInt(JsonElement element, string name, out int value)
    {
        value = 0;
        return element.TryGetProperty(name, out var number) && number.ValueKind == JsonValueKind.Number && number.TryGetInt32(out value);
    }

    [GeneratedRegex(@"^[0-7][0-9A-HJKMNP-TV-Z]{25}\z", RegexOptions.CultureInvariant, 250)]
    private static partial Regex Ulid();

    [GeneratedRegex(@"^[a-z0-9][a-z0-9-]{1,31}\z", RegexOptions.CultureInvariant, 250)]
    private static partial Regex ProviderPattern();
}
