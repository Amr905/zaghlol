using System.Text.Json;
using System.Text.RegularExpressions;
using Zaghlol.Domain;

namespace Zaghlol.Application.Llm.Attestation;

/// <summary>
/// The <c>attestation</c> member of an LLM request (OpenAPI <c>LlmAttestation</c>). Proof material is held as
/// <see cref="Sensitive{T}"/> or bytes and <see cref="ToString"/> names the type only, so no record print shows a token.
/// </summary>
public abstract record LlmAttestationProof
{
    private protected LlmAttestationProof()
    {
    }

    /// <summary>The wire <c>type</c> (<c>play_integrity</c>, <c>app_attest</c>, <c>dev</c>).</summary>
    public abstract string Type { get; }

    public sealed override string ToString() => $"LlmAttestationProof({Type})";
}

/// <summary>A Play Integrity standard-request token.</summary>
public sealed record LlmPlayIntegrityProof(Sensitive<string> Token) : LlmAttestationProof
{
    public override string Type => "play_integrity";
}

/// <summary>An App Attest assertion, with the <c>attestationObject</c> on a key's first use.</summary>
public sealed record LlmAppAttestProof(byte[] KeyId, byte[] Assertion, byte[]? AttestationObject) : LlmAttestationProof
{
    public override string Type => "app_attest";
}

/// <summary>Development and Testing only: base64url of <c>HMAC-SHA256(devKey, bodyHash)</c>.</summary>
public sealed record LlmDevProof(Sensitive<string> Proof) : LlmAttestationProof
{
    public override string Type => "dev";
}

/// <summary>Why the <c>attestation</c> member could not be read.</summary>
public enum LlmProofParseFailure
{
    None,

    /// <summary><c>400 VALIDATION_FAILED</c>: wrong type, shape or encoding.</summary>
    ValidationFailed,

    /// <summary><c>400 UNKNOWN_FIELD</c>: a member the proof type does not declare.</summary>
    UnknownField,
}

/// <summary>Result of <see cref="LlmAttestationProofParser.Parse"/>.</summary>
public sealed record LlmProofParseResult(LlmAttestationProof? Proof, LlmProofParseFailure Failure)
{
    public bool IsValid => Failure == LlmProofParseFailure.None;
}

/// <summary>Closed parse of the <c>attestation</c> member, patterns as in the OpenAPI schemas. Never echoes the input.</summary>
public static partial class LlmAttestationProofParser
{
    public static LlmProofParseResult Parse(JsonElement attestation)
    {
        try
        {
            if (attestation.ValueKind != JsonValueKind.Object)
            {
                return Fail(LlmProofParseFailure.ValidationFailed);
            }

            var type = String(attestation, "type");
            string[] known = type switch
            {
                "play_integrity" => ["type", "token"],
                "app_attest" => ["type", "keyId", "assertion", "attestationObject"],
                "dev" => ["type", "proof"],
                _ => [],
            };
            if (known.Length == 0)
            {
                return Fail(LlmProofParseFailure.ValidationFailed);
            }

            if (attestation.EnumerateObject().Any(m => !known.Contains(m.Name, StringComparer.Ordinal)))
            {
                return Fail(LlmProofParseFailure.UnknownField);
            }

            switch (type)
            {
                case "play_integrity":
                    return String(attestation, "token") is { } token && IntegrityToken().IsMatch(token)
                        ? new LlmProofParseResult(new LlmPlayIntegrityProof(new Sensitive<string>(token)), LlmProofParseFailure.None)
                        : Fail(LlmProofParseFailure.ValidationFailed);

                case "dev":
                    return String(attestation, "proof") is { } proof && DevProof().IsMatch(proof)
                        ? new LlmProofParseResult(new LlmDevProof(new Sensitive<string>(proof)), LlmProofParseFailure.None)
                        : Fail(LlmProofParseFailure.ValidationFailed);

                default:
                    if (String(attestation, "keyId") is not { } keyText || !KeyId().IsMatch(keyText) || Decode(keyText) is not { Length: 32 } keyId
                        || String(attestation, "assertion") is not { } assertionText || !Assertion().IsMatch(assertionText)
                        || Decode(assertionText) is not { } assertion)
                    {
                        return Fail(LlmProofParseFailure.ValidationFailed);
                    }

                    byte[]? attestationObject = null;
                    if (attestation.TryGetProperty("attestationObject", out var element))
                    {
                        if (element.ValueKind != JsonValueKind.String || element.GetString() is not { } objectText
                            || !AttestationObject().IsMatch(objectText) || Decode(objectText) is not { } decoded)
                        {
                            return Fail(LlmProofParseFailure.ValidationFailed);
                        }

                        attestationObject = decoded;
                    }

                    return new LlmProofParseResult(new LlmAppAttestProof(keyId, assertion, attestationObject), LlmProofParseFailure.None);
            }
        }
        catch (InvalidOperationException)
        {
            return Fail(LlmProofParseFailure.ValidationFailed);
        }
    }

    private static string? String(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static byte[]? Decode(string base64)
    {
        var buffer = new byte[(base64.Length / 4 * 3) + 3];
        return Convert.TryFromBase64String(base64, buffer, out var written) ? buffer[..written] : null;
    }

    private static LlmProofParseResult Fail(LlmProofParseFailure failure) => new(null, failure);

    [GeneratedRegex(@"^[A-Za-z0-9_.-]{16,16384}\z", RegexOptions.CultureInvariant)]
    private static partial Regex IntegrityToken();

    [GeneratedRegex(@"^[A-Za-z0-9_.-]{8,256}\z", RegexOptions.CultureInvariant)]
    private static partial Regex DevProof();

    [GeneratedRegex(@"^[A-Za-z0-9+/]{43}=\z", RegexOptions.CultureInvariant)]
    private static partial Regex KeyId();

    [GeneratedRegex(@"^[A-Za-z0-9+/]{16,8192}={0,2}\z", RegexOptions.CultureInvariant)]
    private static partial Regex Assertion();

    [GeneratedRegex(@"^[A-Za-z0-9+/]{16,16384}={0,2}\z", RegexOptions.CultureInvariant)]
    private static partial Regex AttestationObject();
}
