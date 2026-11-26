using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Zaghlol.Application.Llm.Attestation;

namespace Zaghlol.Application.Llm.Ask;

/// <summary>Why a request body was refused before any gate ran. The endpoint maps it to 400, 413 or nothing.</summary>
public enum AskParseFailure
{
    None,

    /// <summary><c>400 VALIDATION_FAILED</c>.</summary>
    Invalid,

    /// <summary><c>400 UNKNOWN_FIELD</c>: a member the closed body does not declare (no financial data is accepted).</summary>
    UnknownField,
}

/// <summary>
/// The parsed <c>POST /v1/ask/plan</c> body. <see cref="Question"/> is sensitive (<c>***</c> in every print and JSON write). <see cref="Proof"/> is
/// <c>null</c> when the body has no <c>attestation</c> member: the verifier turns that into <c>422 missing</c>, not a <c>400</c> (ask-llm §5).
/// <see cref="BodyHash"/> is the install-bound hash over the same parsed element (null never reaches a gate).
/// </summary>
public sealed record AskPlanRequest(
    string RequestId,
    LlmSensitive<string> Question,
    string Lang,
    string ConsentProvider,
    int ConsentVersion,
    LlmAttestationProof? Proof,
    bool HasAttestationObject);

public sealed record AskParseResult(AskPlanRequest? Request, AskParseFailure Failure, JsonDocument? Document)
{
    public static AskParseResult Fail(AskParseFailure failure) => new(null, failure, null);
}

/// <summary>
/// Closed, strict parse of the body (ask-llm §4.1): exactly the members of the contract, no duplicates, no comments, bounded depth.
/// Nothing from the body is echoed: a failure is a fixed code.
/// </summary>
public static partial class AskPlanRequestParser
{
    public const int MaxQuestionChars = 300;
    public const int MaxBodyBytes = 4 * 1024;
    public const int MaxBodyBytesWithAttestationObject = 16 * 1024;
    public const int PlanVersion = 1;

    private static readonly string[] Members = ["planVersion", "requestId", "q", "lang", "consent", "attestation"];

    private static readonly JsonDocumentOptions DocumentOptions = new()
    {
        AllowTrailingCommas = false,
        CommentHandling = JsonCommentHandling.Disallow,
        MaxDepth = 8,
        AllowDuplicateProperties = false,
    };

    /// <summary>The document is returned so the caller can bind the attestation to the same element; the caller disposes it.</summary>
    public static AskParseResult Parse(ReadOnlyMemory<byte> utf8)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(utf8, DocumentOptions);
        }
        catch (JsonException)
        {
            return AskParseResult.Fail(AskParseFailure.Invalid);
        }

        var result = ParseRoot(document.RootElement);
        if (result.Request is null)
        {
            document.Dispose();
            return result;
        }

        return result with { Document = document };
    }

    private static AskParseResult ParseRoot(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object)
        {
            return AskParseResult.Fail(AskParseFailure.Invalid);
        }

        foreach (var member in root.EnumerateObject())
        {
            if (!Members.Contains(member.Name, StringComparer.Ordinal))
            {
                return AskParseResult.Fail(AskParseFailure.UnknownField);
            }
        }

        if (!root.TryGetProperty("consent", out var consent) || consent.ValueKind != JsonValueKind.Object)
        {
            return AskParseResult.Fail(AskParseFailure.Invalid);
        }

        foreach (var member in consent.EnumerateObject())
        {
            if (member.Name is not ("provider" or "v"))
            {
                return AskParseResult.Fail(AskParseFailure.UnknownField);
            }
        }

        // An unknown member inside the proof is also UNKNOWN_FIELD (the proof parser says which).
        LlmAttestationProof? proof = null;
        var hasObject = false;
        if (root.TryGetProperty("attestation", out var attestation))
        {
            var parsed = LlmAttestationProofParser.Parse(attestation);
            if (!parsed.IsValid)
            {
                return AskParseResult.Fail(parsed.Failure == LlmProofParseFailure.UnknownField ? AskParseFailure.UnknownField : AskParseFailure.Invalid);
            }

            proof = parsed.Proof;
            hasObject = attestation.TryGetProperty("attestationObject", out _);
        }

        if (!TryInt(root, "planVersion", out var version) || version != PlanVersion
            || Str(root, "requestId") is not { } requestId || !Ulid().IsMatch(requestId)
            || Str(root, "q") is not { } q
            || Str(root, "lang") is not { } lang || (lang != "ar" && lang != "en")
            || Str(consent, "provider") is not { } provider || !ProviderPattern().IsMatch(provider)
            || !TryInt(consent, "v", out var consentVersion) || consentVersion < 1)
        {
            return AskParseResult.Fail(AskParseFailure.Invalid);
        }

        var question = NormaliseQuestion(q);
        if (question is null)
        {
            return AskParseResult.Fail(AskParseFailure.Invalid);
        }

        return new AskParseResult(
            new AskPlanRequest(requestId, new LlmSensitive<string>(question), lang, provider, consentVersion, proof, hasObject),
            AskParseFailure.None,
            null);
    }

    private static readonly UTF8Encoding StrictUtf8 = new(false, true);

    /// <summary>
    /// 1 to 300 characters after trim; a lone surrogate or a control character other than tab and line breaks refuses it. NFC is the phone's job:
    /// the backend runs with <c>InvariantGlobalization</c>, where <c>string.Normalize</c> does nothing for non-ASCII text, so it neither
    /// normalises nor refuses (the validator folds text itself and the provider reads any Unicode).
    /// </summary>
    internal static string? NormaliseQuestion(string q)
    {
        var text = q.Trim();
        if (text.Length is 0 or > MaxQuestionChars || text.Any(c => char.IsControl(c) && c is not ('\n' or '\r' or '\t')))
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
            // A lone surrogate escape: not text.
            return null;
        }
    }

    private static bool TryInt(JsonElement element, string name, out int value)
    {
        value = 0;
        return element.TryGetProperty(name, out var number) && number.ValueKind == JsonValueKind.Number && number.TryGetInt32(out value);
    }

    // The OpenAPI patterns, with \z so a trailing newline is not accepted (FU-404).
    [GeneratedRegex(@"^[0-7][0-9A-HJKMNP-TV-Z]{25}\z", RegexOptions.CultureInvariant, 250)]
    private static partial Regex Ulid();

    [GeneratedRegex(@"^[a-z0-9][a-z0-9-]{1,31}\z", RegexOptions.CultureInvariant, 250)]
    private static partial Regex ProviderPattern();
}
