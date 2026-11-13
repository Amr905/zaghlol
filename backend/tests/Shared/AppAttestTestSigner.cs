using System.Buffers.Binary;
using System.Formats.Asn1;
using System.Formats.Cbor;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;

namespace Zaghlol.Testing;

/// <summary>
/// A test-only App Attest "device" under a test root shaped like Apple's (T-181 design note §7): a P-384 root and intermediate,
/// and per key a P-256 credential certificate carrying the nonce extension <c>1.2.840.113635.100.8.2</c>. Produces structurally
/// valid attestation objects and assertions, with switches to break exactly one rule. Every value is synthetic.
/// </summary>
public sealed class AppAttestTestSigner : IDisposable
{
    public const string NonceOid = "1.2.840.113635.100.8.2";
    public const string TeamId = "TESTTEAM00";
    public const string BundleId = "app.zaghlol.test";
    public const string AppId = TeamId + "." + BundleId;

    public static readonly byte[] ProductionAaguid = [.. "appattest"u8, 0, 0, 0, 0, 0, 0, 0];
    public static readonly byte[] DevelopmentAaguid = [.. "appattestdevelop"u8];

    private readonly ECDsa rootKey;
    private readonly X509Certificate2 root;
    private readonly ECDsa intermediateKey;
    private readonly X509Certificate2 intermediate;

    public AppAttestTestSigner(string rootSubject = "CN=Zaghlol Test App Attestation Root CA, O=Zaghlol Tests, C=EG")
    {
        var now = DateTimeOffset.UtcNow;
        rootKey = ECDsa.Create(ECCurve.NamedCurves.nistP384);
        var rootRequest = new CertificateRequest(rootSubject, rootKey, HashAlgorithmName.SHA384);
        rootRequest.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, false, 0, true));
        rootRequest.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.KeyCertSign | X509KeyUsageFlags.CrlSign, true));
        rootRequest.CertificateExtensions.Add(new X509SubjectKeyIdentifierExtension(rootRequest.PublicKey, false));
        root = rootRequest.CreateSelfSigned(now.AddYears(-5), now.AddYears(20));

        intermediateKey = ECDsa.Create(ECCurve.NamedCurves.nistP384);
        var intermediateRequest = new CertificateRequest("CN=Zaghlol Test App Attestation CA 1, O=Zaghlol Tests, C=EG", intermediateKey, HashAlgorithmName.SHA384);
        intermediateRequest.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, true, 0, true));
        intermediateRequest.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.KeyCertSign | X509KeyUsageFlags.CrlSign, true));
        intermediateRequest.CertificateExtensions.Add(new X509SubjectKeyIdentifierExtension(intermediateRequest.PublicKey, false));
        intermediateRequest.CertificateExtensions.Add(X509AuthorityKeyIdentifierExtension.CreateFromCertificate(root, true, false));
        using var issued = intermediateRequest.Create(root, now.AddYears(-3), now.AddYears(10), Serial());
        intermediate = issued.CopyWithPrivateKey(intermediateKey);
    }

    /// <summary>The test root (DER) for <c>Attestation:AppAttest:TestRootCertificate</c> / <c>AppAttestOptions.TestRoot</c>.</summary>
    public byte[] RootDer => root.RawData;

    public static byte[] RpIdHash(string appId = AppId) => SHA256.HashData(Encoding.UTF8.GetBytes(appId));

    /// <summary>A fresh device key (the Secure Enclave key App Attest would make).</summary>
    public static AppAttestTestKey NewKey() => new(ECDsa.Create(ECCurve.NamedCurves.nistP256));

    /// <summary>An <c>attestationObject</c> over <paramref name="clientDataHash"/>; each optional argument breaks one rule.</summary>
    public byte[] Attest(
        AppAttestTestKey key,
        ReadOnlySpan<byte> clientDataHash,
        string appId = AppId,
        uint counter = 0,
        byte[]? aaguid = null,
        byte[]? nonceOverride = null,
        byte[]? credentialIdOverride = null)
    {
        var authData = AuthData(RpIdHash(appId), 0x41, counter, aaguid ?? ProductionAaguid, credentialIdOverride ?? key.KeyId, key.CosePublicKey());
        var nonce = nonceOverride ?? SHA256.HashData([.. authData, .. clientDataHash]);
        var leaf = Credential(key, nonce);

        var writer = new CborWriter(CborConformanceMode.Strict);
        writer.WriteStartMap(3);
        writer.WriteTextString("fmt");
        writer.WriteTextString("apple-appattest");
        writer.WriteTextString("attStmt");
        writer.WriteStartMap(2);
        writer.WriteTextString("x5c");
        writer.WriteStartArray(2);
        writer.WriteByteString(leaf);
        writer.WriteByteString(intermediate.RawData);
        writer.WriteEndArray();
        writer.WriteTextString("receipt");
        writer.WriteByteString("synthetic-receipt"u8);
        writer.WriteEndMap();
        writer.WriteTextString("authData");
        writer.WriteByteString(authData);
        writer.WriteEndMap();
        return writer.Encode();
    }

    /// <summary>An assertion (<c>generateAssertion</c>) over <paramref name="clientDataHash"/>.</summary>
    public static byte[] Assert(AppAttestTestKey key, ReadOnlySpan<byte> clientDataHash, uint counter, string appId = AppId)
    {
        var authData = new byte[37];
        RpIdHash(appId).CopyTo(authData, 0);
        authData[32] = 0x01;
        BinaryPrimitives.WriteUInt32BigEndian(authData.AsSpan(33), counter);
        var nonce = SHA256.HashData([.. authData, .. clientDataHash]);
        var signature = key.Key.SignData(nonce, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence);

        var writer = new CborWriter(CborConformanceMode.Strict);
        writer.WriteStartMap(2);
        writer.WriteTextString("signature");
        writer.WriteByteString(signature);
        writer.WriteTextString("authenticatorData");
        writer.WriteByteString(authData);
        writer.WriteEndMap();
        return writer.Encode();
    }

    public void Dispose()
    {
        root.Dispose();
        intermediate.Dispose();
        rootKey.Dispose();
        intermediateKey.Dispose();
    }

    private static byte[] AuthData(byte[] rpIdHash, byte flags, uint counter, byte[] aaguid, byte[] credentialId, byte[] cose)
    {
        var data = new byte[55 + credentialId.Length + cose.Length];
        rpIdHash.CopyTo(data, 0);
        data[32] = flags;
        BinaryPrimitives.WriteUInt32BigEndian(data.AsSpan(33), counter);
        aaguid.CopyTo(data, 37);
        BinaryPrimitives.WriteUInt16BigEndian(data.AsSpan(53), (ushort)credentialId.Length);
        credentialId.CopyTo(data, 55);
        cose.CopyTo(data, 55 + credentialId.Length);
        return data;
    }

    private byte[] Credential(AppAttestTestKey key, byte[] nonce)
    {
        var now = DateTimeOffset.UtcNow;
        var request = new CertificateRequest($"CN={Convert.ToHexStringLower(key.KeyId)}, OU=AAA Certification, O=Zaghlol Tests", key.Key, HashAlgorithmName.SHA256);
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
        request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, true));
        request.CertificateExtensions.Add(X509AuthorityKeyIdentifierExtension.CreateFromCertificate(intermediate, true, false));
        request.CertificateExtensions.Add(new X509Extension(NonceOid, NonceExtension(nonce), false));
        using var leaf = request.Create(intermediate, now.AddDays(-1), now.AddDays(3), Serial());
        return leaf.RawData;
    }

    private static byte[] NonceExtension(byte[] nonce)
    {
        var writer = new AsnWriter(AsnEncodingRules.DER);
        writer.PushSequence();
        var tag = new Asn1Tag(TagClass.ContextSpecific, 1, isConstructed: true);
        writer.PushSequence(tag);
        writer.WriteOctetString(nonce);
        writer.PopSequence(tag);
        writer.PopSequence();
        return writer.Encode();
    }

    private static byte[] Serial() => RandomNumberGenerator.GetBytes(16);
}

/// <summary>A synthetic App Attest key: its P-256 key and <c>keyId</c> = SHA-256 of the uncompressed point.</summary>
public sealed class AppAttestTestKey(ECDsa key) : IDisposable
{
    public ECDsa Key { get; } = key;

    public byte[] Point
    {
        get
        {
            var q = Key.ExportParameters(false).Q;
            return [0x04, .. q.X!, .. q.Y!];
        }
    }

    public byte[] KeyId => SHA256.HashData(Point);

    /// <summary>The COSE_Key (EC2, ES256) that follows the credential ID in <c>authData</c>.</summary>
    public byte[] CosePublicKey()
    {
        var q = Key.ExportParameters(false).Q;
        var writer = new CborWriter(CborConformanceMode.Ctap2Canonical);
        writer.WriteStartMap(5);
        writer.WriteInt32(1);
        writer.WriteInt32(2);
        writer.WriteInt32(3);
        writer.WriteInt32(-7);
        writer.WriteInt32(-1);
        writer.WriteInt32(1);
        writer.WriteInt32(-2);
        writer.WriteByteString(q.X!);
        writer.WriteInt32(-3);
        writer.WriteByteString(q.Y!);
        writer.WriteEndMap();
        return writer.Encode();
    }

    public void Dispose() => Key.Dispose();
}
