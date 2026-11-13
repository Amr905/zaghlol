using System.Buffers.Binary;
using System.Formats.Asn1;
using System.Formats.Cbor;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Purchases.Attestation;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.AppStore;

namespace Zaghlol.Infrastructure.Attestation;

/// <summary>
/// In-house App Attest validation (T-181 design note §4–§5; Apple, "Validating apps that connect to your server"), with
/// <see cref="CborReader"/>, <see cref="AsnReader"/>, <see cref="X509Chain"/> and <see cref="ECDsa"/>. Fails closed: anything
/// malformed, oversized, unknown or unverifiable is a failure, never a pass. Logs the reason code only.
/// </summary>
internal sealed partial class AppAttestVerifier : IAppAttestVerifier
{
    /// <summary>Apple's nonce extension on the credential certificate.</summary>
    public const string NonceOid = "1.2.840.113635.100.8.2";

    public const int MaxAttestationBytes = 16 * 1024;
    public const int MaxCertificateBytes = 4096;
    public const int MaxAssertionBytes = 2048;
    public const int HashLength = 32;

    // rpIdHash (32) | flags (1) | counter (4) | aaguid (16) | credentialIdLength (2) | credentialId.
    private const int CounterOffset = 33;
    private const int AaguidOffset = 37;
    private const int CredentialLengthOffset = 53;
    private const int CredentialIdOffset = 55;
    private const int AssertionAuthDataMin = 37;

    private static readonly byte[] ProductionAaguid = [.. "appattest"u8, 0, 0, 0, 0, 0, 0, 0];
    private static readonly byte[] DevelopmentAaguid = [.. "appattestdevelop"u8];

    private readonly AppAttestOptions options;
    private readonly TimeProvider clock;
    private readonly ILogger<AppAttestVerifier> logger;
    private readonly byte[] anchor;
    private readonly byte[] anchorSha256;
    private readonly byte[] rpIdHash;

    public AppAttestVerifier(AppAttestOptions options, TimeProvider clock, ILogger<AppAttestVerifier> logger)
    {
        ArgumentNullException.ThrowIfNull(options);
        this.options = options;
        this.clock = clock;
        this.logger = logger;
        anchor = options.TrustAnchor();
        anchorSha256 = SHA256.HashData(anchor);
        rpIdHash = SHA256.HashData(Encoding.UTF8.GetBytes(options.AppId));
    }

    public async Task<AttestationResult> RegisterAttestationAsync(
        IAppAttestKeyStore keys,
        InstallId installId,
        ReadOnlyMemory<byte> keyId,
        ReadOnlyMemory<byte> attestationObject,
        ReadOnlyMemory<byte> clientDataHash,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(keys);

        var checkedKey = CheckAttestation(keyId.Span, attestationObject.Span, clientDataHash.Span, out var publicKey, out var development);
        if (checkedKey is { } failure)
        {
            return Fail(failure);
        }

        var registration = await keys.RegisterAsync(installId, keyId.ToArray(), publicKey!, development, cancellationToken);
        return registration == AppAttestRegistration.Refused ? Fail(AttestationFailure.KeyUnknown) : AttestationResult.Verified(ProofLevel.Device);
    }

    public async Task<AttestationResult> VerifyAssertionAsync(
        IAppAttestKeyStore keys,
        InstallId installId,
        ReadOnlyMemory<byte> keyId,
        ReadOnlyMemory<byte> assertion,
        ReadOnlyMemory<byte> clientDataHash,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(keys);

        if (keyId.Length != HashLength || clientDataHash.Length != HashLength || !ParseAssertion(assertion, out var signature, out var authData))
        {
            return Fail(AttestationFailure.Chain);
        }

        var row = await keys.LockAsync(installId, cancellationToken);
        if (row is null || !CryptographicOperations.FixedTimeEquals(row.KeyId, keyId.Span))
        {
            return Fail(AttestationFailure.KeyUnknown);
        }

        var nonce = Nonce(authData, clientDataHash.Span);
        if (!VerifySignature(row.PublicKey, nonce, signature))
        {
            return Fail(AttestationFailure.HashMismatch);
        }

        if (!CryptographicOperations.FixedTimeEquals(authData.AsSpan(0, HashLength), rpIdHash))
        {
            return Fail(AttestationFailure.AppUnrecognized);
        }

        long counter = BinaryPrimitives.ReadUInt32BigEndian(authData.AsSpan(CounterOffset, 4));
        if (counter <= row.SignCount)
        {
            return Fail(AttestationFailure.Counter);
        }

        return await keys.UpdateCounterAsync(installId, row.KeyId, counter, cancellationToken)
            ? AttestationResult.Verified(ProofLevel.Device)
            : Fail(AttestationFailure.KeyUnknown);
    }

    /// <summary>Every attestation rule except the registration; <c>null</c> when it passes.</summary>
    internal AttestationFailure? CheckAttestation(
        ReadOnlySpan<byte> keyId,
        ReadOnlySpan<byte> attestationObject,
        ReadOnlySpan<byte> clientDataHash,
        out byte[]? publicKey,
        out bool development)
    {
        publicKey = null;
        development = false;
        if (keyId.Length != HashLength || clientDataHash.Length != HashLength || attestationObject.Length is 0 or > MaxAttestationBytes
            || !ParseAttestation(attestationObject.ToArray(), out var authData, out var leafDer, out var intermediateDer))
        {
            return AttestationFailure.Chain;
        }

        using var leaf = LoadCertificate(leafDer);
        using var intermediate = LoadCertificate(intermediateDer);
        if (leaf is null || intermediate is null || !ChainIsTrusted(leaf, intermediate, intermediateDer))
        {
            return AttestationFailure.Chain;
        }

        if (ReadNonceExtension(leaf) is not { } certNonce)
        {
            return AttestationFailure.Chain;
        }

        if (!CryptographicOperations.FixedTimeEquals(certNonce, Nonce(authData, clientDataHash)))
        {
            return AttestationFailure.HashMismatch;
        }

        var point = ReadP256Point(leaf);
        if (point is null || !CryptographicOperations.FixedTimeEquals(SHA256.HashData(point), keyId))
        {
            return AttestationFailure.Chain;
        }

        if (authData.Length < CredentialIdOffset)
        {
            return AttestationFailure.Chain;
        }

        var credentialLength = BinaryPrimitives.ReadUInt16BigEndian(authData.AsSpan(CredentialLengthOffset, 2));
        if (credentialLength != HashLength || authData.Length < CredentialIdOffset + credentialLength
            || !CryptographicOperations.FixedTimeEquals(authData.AsSpan(CredentialIdOffset, credentialLength), keyId))
        {
            return AttestationFailure.Chain;
        }

        if (!CryptographicOperations.FixedTimeEquals(authData.AsSpan(0, HashLength), rpIdHash))
        {
            return AttestationFailure.AppUnrecognized;
        }

        if (BinaryPrimitives.ReadUInt32BigEndian(authData.AsSpan(CounterOffset, 4)) != 0)
        {
            return AttestationFailure.Counter;
        }

        var aaguid = authData.AsSpan(AaguidOffset, 16);
        if (aaguid.SequenceEqual(ProductionAaguid))
        {
            development = false;
        }
        else if (options.AllowDevelopment && aaguid.SequenceEqual(DevelopmentAaguid))
        {
            development = true;
        }
        else
        {
            return AttestationFailure.AppUnrecognized;
        }

        publicKey = point;
        return null;
    }

    private static byte[] Nonce(ReadOnlySpan<byte> authData, ReadOnlySpan<byte> clientDataHash)
    {
        var buffer = new byte[authData.Length + clientDataHash.Length];
        authData.CopyTo(buffer);
        clientDataHash.CopyTo(buffer.AsSpan(authData.Length));
        return SHA256.HashData(buffer);
    }

    /// <summary><c>{ fmt: "apple-appattest", attStmt: { x5c: [leaf, intermediate], receipt }, authData }</c>, nothing else.</summary>
    private static bool ParseAttestation(byte[] data, out byte[] authData, out byte[] leaf, out byte[] intermediate)
    {
        authData = leaf = intermediate = [];
        try
        {
            var reader = new CborReader(data, CborConformanceMode.Strict);
            if (reader.ReadStartMap() != 3)
            {
                return false;
            }

            string? fmt = null;
            byte[]? auth = null;
            byte[][]? x5c = null;
            for (var i = 0; i < 3; i++)
            {
                switch (reader.ReadTextString())
                {
                    case "fmt" when fmt is null:
                        fmt = reader.ReadTextString();
                        break;
                    case "authData" when auth is null:
                        auth = reader.ReadByteString();
                        break;
                    case "attStmt" when x5c is null:
                        x5c = ReadStatement(reader);
                        if (x5c is null)
                        {
                            return false;
                        }

                        break;
                    default:
                        return false;
                }
            }

            reader.ReadEndMap();
            if (reader.BytesRemaining != 0 || fmt != "apple-appattest" || auth is null || x5c is null)
            {
                return false;
            }

            authData = auth;
            leaf = x5c[0];
            intermediate = x5c[1];
            return true;
        }
        catch (Exception e) when (e is CborContentException or InvalidOperationException or ArgumentException or FormatException)
        {
            return false;
        }
    }

    private static byte[][]? ReadStatement(CborReader reader)
    {
        if (reader.ReadStartMap() != 2)
        {
            return null;
        }

        byte[][]? x5c = null;
        var receipt = false;
        for (var i = 0; i < 2; i++)
        {
            switch (reader.ReadTextString())
            {
                case "x5c" when x5c is null:
                    if (reader.ReadStartArray() != 2)
                    {
                        return null;
                    }

                    x5c = [reader.ReadByteString(), reader.ReadByteString()];
                    reader.ReadEndArray();
                    if (x5c[0].Length is 0 or > MaxCertificateBytes || x5c[1].Length is 0 or > MaxCertificateBytes)
                    {
                        return null;
                    }

                    break;
                case "receipt" when !receipt:
                    // Not used (no fraud-metric calls, D-45); read so the structure is complete.
                    reader.ReadByteString();
                    receipt = true;
                    break;
                default:
                    return null;
            }
        }

        reader.ReadEndMap();
        return receipt ? x5c : null;
    }

    /// <summary><c>{ signature, authenticatorData }</c>, nothing else.</summary>
    private static bool ParseAssertion(ReadOnlyMemory<byte> data, out byte[] signature, out byte[] authData)
    {
        signature = authData = [];
        if (data.Length is 0 or > MaxAssertionBytes)
        {
            return false;
        }

        try
        {
            var reader = new CborReader(data, CborConformanceMode.Strict);
            if (reader.ReadStartMap() != 2)
            {
                return false;
            }

            byte[]? sig = null;
            byte[]? auth = null;
            for (var i = 0; i < 2; i++)
            {
                switch (reader.ReadTextString())
                {
                    case "signature" when sig is null:
                        sig = reader.ReadByteString();
                        break;
                    case "authenticatorData" when auth is null:
                        auth = reader.ReadByteString();
                        break;
                    default:
                        return false;
                }
            }

            reader.ReadEndMap();
            if (reader.BytesRemaining != 0 || sig is null || auth is null || auth.Length < AssertionAuthDataMin)
            {
                return false;
            }

            signature = sig;
            authData = auth;
            return true;
        }
        catch (Exception e) when (e is CborContentException or InvalidOperationException or ArgumentException or FormatException)
        {
            return false;
        }
    }

    private static X509Certificate2? LoadCertificate(byte[] der)
    {
        try
        {
            return X509CertificateLoader.LoadCertificate(der);
        }
        catch (CryptographicException)
        {
            return null;
        }
    }

    /// <summary>Leaf → intermediate → the pinned root, the only anchor, offline, at now.</summary>
    private bool ChainIsTrusted(X509Certificate2 leaf, X509Certificate2 intermediate, byte[] intermediateDer)
    {
        using var root = X509CertificateLoader.LoadCertificate(anchor);
        using var chain = new X509Chain();
        chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
        chain.ChainPolicy.CustomTrustStore.Add(root);
        chain.ChainPolicy.ExtraStore.Add(intermediate);
        chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
        chain.ChainPolicy.DisableCertificateDownloads = true;
        chain.ChainPolicy.VerificationTimeIgnored = false;
        chain.ChainPolicy.VerificationTime = clock.GetUtcNow().UtcDateTime;
        try
        {
            return chain.Build(leaf)
                && chain.ChainElements.Count == 3
                && chain.ChainElements[1].Certificate.RawDataMemory.Span.SequenceEqual(intermediateDer)
                && CryptographicOperations.FixedTimeEquals(SHA256.HashData(chain.ChainElements[2].Certificate.RawDataMemory.Span), anchorSha256);
        }
        catch (CryptographicException)
        {
            return false;
        }
        finally
        {
            foreach (var element in chain.ChainElements)
            {
                if (!ReferenceEquals(element.Certificate, leaf) && !ReferenceEquals(element.Certificate, intermediate))
                {
                    element.Certificate.Dispose();
                }
            }
        }
    }

    /// <summary>The nonce extension: DER <c>SEQUENCE { [1] EXPLICIT OCTET STRING (32 bytes) }</c>; <c>null</c> on any deviation.</summary>
    internal static byte[]? ReadNonceExtension(X509Certificate2 leaf)
    {
        X509Extension? extension = null;
        foreach (var candidate in leaf.Extensions)
        {
            if (candidate.Oid?.Value == NonceOid)
            {
                if (extension is not null)
                {
                    return null;
                }

                extension = candidate;
            }
        }

        if (extension is null)
        {
            return null;
        }

        try
        {
            var reader = new AsnReader(extension.RawData, AsnEncodingRules.DER);
            var sequence = reader.ReadSequence();
            reader.ThrowIfNotEmpty();
            var tagged = sequence.ReadSequence(new Asn1Tag(TagClass.ContextSpecific, 1, isConstructed: true));
            sequence.ThrowIfNotEmpty();
            var nonce = tagged.ReadOctetString();
            tagged.ThrowIfNotEmpty();
            return nonce.Length == HashLength ? nonce : null;
        }
        catch (AsnContentException)
        {
            return null;
        }
    }

    /// <summary>The leaf's P-256 public key as the 65-byte uncompressed point; <c>null</c> for any other key.</summary>
    private static byte[]? ReadP256Point(X509Certificate2 leaf)
    {
        try
        {
            using var key = leaf.GetECDsaPublicKey();
            if (key is null || !AppleKeyText.IsP256(key))
            {
                return null;
            }

            var q = key.ExportParameters(false).Q;
            if (q.X is not { Length: 32 } x || q.Y is not { Length: 32 } y)
            {
                return null;
            }

            return [0x04, .. x, .. y];
        }
        catch (CryptographicException)
        {
            return null;
        }
    }

    private static bool VerifySignature(byte[] point, byte[] nonce, byte[] signature)
    {
        if (point.Length != 65 || point[0] != 0x04)
        {
            return false;
        }

        try
        {
            using var key = ECDsa.Create(new ECParameters
            {
                Curve = ECCurve.NamedCurves.nistP256,
                Q = new ECPoint { X = point[1..33], Y = point[33..65] },
            });
            return key.VerifyData(nonce, signature, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence);
        }
        catch (CryptographicException)
        {
            return false;
        }
    }

    private AttestationResult Fail(AttestationFailure failure)
    {
        var code = AttestationCodes.Of(failure);
        LogFailed(logger, code);
        return AttestationResult.Failed(failure);
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "attestation_failed provider=app_attest reason={reason}")]
    private static partial void LogFailed(ILogger logger, string reason);
}
