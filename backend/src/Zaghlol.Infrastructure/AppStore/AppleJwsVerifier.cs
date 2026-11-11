using System.Buffers.Text;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization.Metadata;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.AppStore;

/// <summary>
/// The in-house Apple JWS verifier (T-131 design note §1-2): <c>System.Security.Cryptography</c> only, pure and synchronous, no
/// network. In order, each failure an <see cref="AppleJwsException"/> with a constant message:
/// <list type="number">
/// <item>shape: at most <see cref="MaxLength"/> characters (before any decode), three strict base64url segments, header and payload
/// JSON without duplicate members (<see cref="AppleJwsFailure.Malformed"/>);</item>
/// <item>header: <c>alg</c> exactly <c>ES256</c>, none of <c>jku</c>, <c>jwk</c>, <c>x5u</c>, <c>kid</c>, <c>crit</c>
/// (<see cref="AppleJwsFailure.Alg"/>); <c>x5c</c> exactly three DER certificates of at most 4 KiB;</item>
/// <item>chain, built offline at the validation time with the pinned root as the only trust anchor: exactly three elements, the
/// intermediate byte-equal to <c>x5c[1]</c>, the root's SHA-256 equal to the pin and <c>x5c[2]</c> byte-equal to it
/// (<see cref="AppleJwsFailure.Chain"/>);</item>
/// <item>Apple's marker extensions on the leaf (<see cref="LeafOid"/>) and intermediate (<see cref="IntermediateOid"/>), and an EC
/// P-256 leaf key (<see cref="AppleJwsFailure.Oid"/>);</item>
/// <item>the ES256 signature with the leaf key, 64-byte IEEE P1363 only (<see cref="AppleJwsFailure.Signature"/>);</item>
/// <item>the payload's read fields (<see cref="AppleJwsFailure.Payload"/>).</item>
/// </list>
/// Validation time: <see cref="JwsSource.Api"/> at now; <see cref="JwsSource.App"/> at the payload's <c>signedDate</c> (read before
/// trust, at most now + 5 min), because StoreKit hands out JWSs signed under intermediates that have since expired. That is safe
/// because a grant never rests on the app's JWS alone: verify re-reads the transaction from Apple.
/// </summary>
public sealed class AppleJwsVerifier : IAppleJwsVerifier
{
    /// <summary>The OpenAPI <c>Jws</c> <c>maxLength</c>.</summary>
    public const int MaxLength = 16384;

    public const int MaxCertificateBytes = 4096;

    /// <summary>Apple's marker on the StoreKit signing leaf certificate.</summary>
    public const string LeafOid = "1.2.840.113635.100.6.11.1";

    /// <summary>Apple's marker on the WWDR intermediate certificate.</summary>
    public const string IntermediateOid = "1.2.840.113635.100.6.2.1";

    /// <summary>How far an app JWS's <c>signedDate</c> may lie ahead of our clock.</summary>
    public static readonly TimeSpan MaxClockSkew = TimeSpan.FromMinutes(5);

    private static readonly string[] ForbiddenHeaders = ["jku", "jwk", "x5u", "kid", "crit"];

    private static readonly JsonDocumentOptions StrictDocument = new() { AllowDuplicateProperties = false, MaxDepth = 16 };

    private readonly byte[] root;
    private readonly byte[] rootSha256;

    /// <param name="pinnedRoot">The trust anchor's DER: Apple Root CA - G3, or a test root in Development and Testing only.</param>
    public AppleJwsVerifier(byte[] pinnedRoot)
    {
        ArgumentNullException.ThrowIfNull(pinnedRoot);
        root = (byte[])pinnedRoot.Clone();
        rootSha256 = SHA256.HashData(root);
    }

    public AppleTransaction VerifyTransaction(Sensitive<string> jws, JwsSource source, DateTimeOffset now)
    {
        var payload = Verify(jws.Reveal(), source, now, AppleJsonContext.Default.TransactionPayloadDto, static p => p.SignedDate);
        if (payload.SignedDate is not { } signed)
        {
            throw Fail(AppleJwsFailure.Payload);
        }

        return new AppleTransaction(
            payload.BundleId,
            Environment(payload.Environment),
            payload.ProductId,
            payload.Type switch
            {
                "Auto-Renewable Subscription" => AppleProductType.AutoRenewable,
                "Non-Consumable" => AppleProductType.NonConsumable,
                _ => AppleProductType.Other,
            },
            Wrap(payload.TransactionId),
            Wrap(payload.OriginalTransactionId),
            Wrap(payload.AppAccountToken),
            payload.InAppOwnershipType switch
            {
                "PURCHASED" => AppleOwnershipType.Purchased,
                "FAMILY_SHARED" => AppleOwnershipType.FamilyShared,
                _ => AppleOwnershipType.Other,
            },
            payload.TransactionReason switch
            {
                "PURCHASE" => AppleTransactionReason.Purchase,
                "RENEWAL" => AppleTransactionReason.Renewal,
                _ => AppleTransactionReason.Other,
            },
            Time(payload.PurchaseDate),
            Time(payload.ExpiresDate),
            Time(payload.RevocationDate),
            payload.RevocationReason,
            Time(signed)!.Value);
    }

    public AppleRenewalInfo VerifyRenewalInfo(Sensitive<string> jws, DateTimeOffset now)
    {
        var payload = Verify(jws.Reveal(), JwsSource.Api, now, AppleJsonContext.Default.RenewalPayloadDto, static p => p.SignedDate);
        return new AppleRenewalInfo(
            Wrap(payload.OriginalTransactionId),
            Environment(payload.Environment),
            payload.AutoRenewStatus,
            Time(payload.GracePeriodExpiresDate));
    }

    private static AppleEnvironment Environment(string? value) => value switch
    {
        "Production" => AppleEnvironment.Production,
        "Sandbox" => AppleEnvironment.Sandbox,
        _ => AppleEnvironment.Unknown,
    };

    private static Sensitive<string>? Wrap(string? value) => value is null ? null : new Sensitive<string>(value);

    private static DateTimeOffset? Time(long? milliseconds)
    {
        if (milliseconds is not { } ms)
        {
            return null;
        }

        // Out of DateTimeOffset's range is unreadable, not a date.
        return ms is >= -62135596800000L and <= 253402300799999L ? DateTimeOffset.FromUnixTimeMilliseconds(ms) : throw Fail(AppleJwsFailure.Payload);
    }

    private static AppleJwsException Fail(AppleJwsFailure reason) => new(reason);

    private T Verify<T>(string? text, JwsSource source, DateTimeOffset now, JsonTypeInfo<T> type, Func<T, long?> signedDate)
        where T : class
    {
        // 1. Shape, before any decode.
        if (text is null || text.Length is 0 or > MaxLength)
        {
            throw Fail(AppleJwsFailure.Malformed);
        }

        var parts = text.Split('.');
        if (parts.Length != 3)
        {
            throw Fail(AppleJwsFailure.Malformed);
        }

        var headerBytes = Base64UrlStrict(parts[0]);
        var payloadBytes = Base64UrlStrict(parts[1]);
        var signature = Base64UrlStrict(parts[2]);

        using var header = ParseObject(headerBytes);
        using var payloadDocument = ParseObject(payloadBytes);

        // 2. Header.
        var head = header.RootElement;
        if (!head.TryGetProperty("alg", out var alg) || alg.ValueKind != JsonValueKind.String || alg.GetString() != "ES256")
        {
            throw Fail(AppleJwsFailure.Alg);
        }

        foreach (var name in ForbiddenHeaders)
        {
            if (head.TryGetProperty(name, out _))
            {
                throw Fail(AppleJwsFailure.Alg);
            }
        }

        if (!head.TryGetProperty("x5c", out var x5c) || x5c.ValueKind != JsonValueKind.Array || x5c.GetArrayLength() != 3)
        {
            throw Fail(AppleJwsFailure.Chain);
        }

        var der = new byte[3][];
        for (var i = 0; i < 3; i++)
        {
            der[i] = x5c[i].ValueKind == JsonValueKind.String ? Base64Strict(x5c[i].GetString()!) : throw Fail(AppleJwsFailure.Chain);
        }

        // 6 (time first, the chain needs it). Api: now. App: the payload's signedDate, read before trust and bounded.
        T payload;
        try
        {
            payload = payloadDocument.RootElement.Deserialize(type) ?? throw Fail(AppleJwsFailure.Payload);
        }
        catch (JsonException)
        {
            throw Fail(AppleJwsFailure.Payload);
        }

        DateTimeOffset at;
        if (source == JwsSource.Api)
        {
            at = now;
        }
        else if (Time(signedDate(payload)) is { } signed && signed <= now + MaxClockSkew)
        {
            at = signed;
        }
        else
        {
            throw Fail(AppleJwsFailure.Payload);
        }

        // 3-5. Chain, OIDs, signature.
        using var leaf = Load(der[0]);
        using var intermediate = Load(der[1]);
        CheckChain(leaf, intermediate, der, at);
        CheckOids(leaf, intermediate);
        using var key = leaf.GetECDsaPublicKey() ?? throw Fail(AppleJwsFailure.Oid);
        if (!IsP256(key))
        {
            throw Fail(AppleJwsFailure.Oid);
        }

        var signingInput = Encoding.ASCII.GetBytes(parts[0] + "." + parts[1]);
        if (signature.Length != 64
            || !key.VerifyData(signingInput, signature, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation))
        {
            throw Fail(AppleJwsFailure.Signature);
        }

        return payload;
    }

    private void CheckChain(X509Certificate2 leaf, X509Certificate2 intermediate, byte[][] der, DateTimeOffset at)
    {
        if (!CryptographicOperations.FixedTimeEquals(der[2], root))
        {
            throw Fail(AppleJwsFailure.Chain);
        }

        using var anchor = Load(root);
        using var chain = new X509Chain();
        chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
        chain.ChainPolicy.CustomTrustStore.Add(anchor);
        chain.ChainPolicy.ExtraStore.Add(intermediate);
        chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
        chain.ChainPolicy.DisableCertificateDownloads = true;
        chain.ChainPolicy.VerificationTimeIgnored = false;
        chain.ChainPolicy.VerificationTime = at.UtcDateTime;
        try
        {
            if (!chain.Build(leaf) || chain.ChainElements.Count != 3
                || !chain.ChainElements[1].Certificate.RawDataMemory.Span.SequenceEqual(der[1])
                || !CryptographicOperations.FixedTimeEquals(SHA256.HashData(chain.ChainElements[2].Certificate.RawDataMemory.Span), rootSha256))
            {
                throw Fail(AppleJwsFailure.Chain);
            }
        }
        catch (CryptographicException)
        {
            throw Fail(AppleJwsFailure.Chain);
        }
        finally
        {
            foreach (var element in chain.ChainElements)
            {
                element.Certificate.Dispose();
            }
        }
    }

    private static void CheckOids(X509Certificate2 leaf, X509Certificate2 intermediate)
    {
        if (leaf.Extensions[LeafOid] is null || intermediate.Extensions[IntermediateOid] is null)
        {
            throw Fail(AppleJwsFailure.Oid);
        }
    }

    private static bool IsP256(ECDsa key)
    {
        try
        {
            return AppleKeyText.IsP256(key);
        }
        catch (CryptographicException)
        {
            return false;
        }
    }

    private static X509Certificate2 Load(byte[] der)
    {
        try
        {
            return X509CertificateLoader.LoadCertificate(der);
        }
        catch (CryptographicException)
        {
            throw Fail(AppleJwsFailure.Chain);
        }
    }

    private static JsonDocument ParseObject(byte[] json)
    {
        try
        {
            var document = JsonDocument.Parse(json, StrictDocument);
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                document.Dispose();
                throw Fail(AppleJwsFailure.Malformed);
            }

            return document;
        }
        catch (JsonException)
        {
            throw Fail(AppleJwsFailure.Malformed);
        }
    }

    /// <summary>Unpadded base64url, canonical only (no padding, whitespace or stray bits).</summary>
    private static byte[] Base64UrlStrict(string segment)
    {
        if (segment.Length == 0 || segment.Length % 4 == 1 || !segment.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_'))
        {
            throw Fail(AppleJwsFailure.Malformed);
        }

        byte[] bytes;
        try
        {
            bytes = Base64Url.DecodeFromChars(segment);
        }
        catch (FormatException)
        {
            throw Fail(AppleJwsFailure.Malformed);
        }

        return string.Equals(Base64Url.EncodeToString(bytes), segment, StringComparison.Ordinal) ? bytes : throw Fail(AppleJwsFailure.Malformed);
    }

    /// <summary>Standard padded base64 of one DER certificate, canonical only, at most <see cref="MaxCertificateBytes"/>.</summary>
    private static byte[] Base64Strict(string text)
    {
        if (text.Length == 0 || text.Length % 4 != 0 || text.Length > (MaxCertificateBytes + 2) / 3 * 4
            || !text.All(c => char.IsAsciiLetterOrDigit(c) || c is '+' or '/' or '='))
        {
            throw Fail(AppleJwsFailure.Malformed);
        }

        byte[] bytes;
        try
        {
            bytes = Convert.FromBase64String(text);
        }
        catch (FormatException)
        {
            throw Fail(AppleJwsFailure.Malformed);
        }

        return bytes.Length <= MaxCertificateBytes && string.Equals(Convert.ToBase64String(bytes), text, StringComparison.Ordinal)
            ? bytes
            : throw Fail(AppleJwsFailure.Malformed);
    }
}
