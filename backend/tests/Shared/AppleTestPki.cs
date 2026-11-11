using System.Buffers.Text;
using System.Formats.Asn1;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json.Nodes;

namespace Zaghlol.Testing;

/// <summary>
/// A test PKI shaped like Apple's (T-131 design note §10): a root, an intermediate carrying Apple's WWDR marker
/// <c>1.2.840.113635.100.6.2.1</c> and a leaf carrying the StoreKit marker <c>1.2.840.113635.100.6.11.1</c>, built at test time
/// with <see cref="CertificateRequest"/>, signing JWSs with the leaf key. Every value is synthetic.
/// </summary>
public sealed class AppleTestPki : IDisposable
{
    public const string LeafOid = "1.2.840.113635.100.6.11.1";
    public const string IntermediateOid = "1.2.840.113635.100.6.2.1";

    private AppleTestPki(ECDsa rootKey, ECDsa intermediateKey, ECDsa leafKey, byte[] root, byte[] intermediate, byte[] leaf)
    {
        RootKey = rootKey;
        IntermediateKey = intermediateKey;
        LeafKey = leafKey;
        RootDer = root;
        IntermediateDer = intermediate;
        LeafDer = leaf;
    }

    public ECDsa RootKey { get; }

    public ECDsa IntermediateKey { get; }

    public ECDsa LeafKey { get; }

    public byte[] RootDer { get; }

    public byte[] IntermediateDer { get; }

    public byte[] LeafDer { get; }

    /// <summary><c>Purchases:Apple:TestRootCertificate</c>.</summary>
    public string RootBase64 => Convert.ToBase64String(RootDer);

    /// <param name="rootSubject">The root's subject (a forged root can reuse Apple's or another root's name).</param>
    /// <param name="intermediateNotAfter">The intermediate's expiry (StoreKit hands out JWSs signed under since-expired ones).</param>
    /// <param name="intermediateOid">Whether the intermediate carries Apple's WWDR marker.</param>
    /// <param name="leafOid">Whether the leaf carries Apple's StoreKit marker.</param>
    /// <param name="leafCurve">The leaf key curve (P-256 unless a test wants another).</param>
    public static AppleTestPki Create(
        string rootSubject = "CN=Zaghlol Test Root CA - G3, OU=Test Certification Authority, O=Zaghlol Tests, C=EG",
        DateTimeOffset? intermediateNotAfter = null,
        bool intermediateOid = true,
        bool leafOid = true,
        ECCurve? leafCurve = null)
    {
        var now = DateTimeOffset.UtcNow;
        var rootKey = ECDsa.Create(ECCurve.NamedCurves.nistP384);
        var intermediateKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var leafKey = ECDsa.Create(leafCurve ?? ECCurve.NamedCurves.nistP256);

        var rootRequest = new CertificateRequest(rootSubject, rootKey, HashAlgorithmName.SHA384);
        rootRequest.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, false, 0, true));
        rootRequest.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.KeyCertSign | X509KeyUsageFlags.CrlSign, true));
        rootRequest.CertificateExtensions.Add(new X509SubjectKeyIdentifierExtension(rootRequest.PublicKey, false));
        using var root = rootRequest.CreateSelfSigned(now.AddYears(-5), now.AddYears(10));

        var intermediateRequest = new CertificateRequest("CN=Zaghlol Test WWDR, OU=G6, O=Zaghlol Tests, C=EG", intermediateKey, HashAlgorithmName.SHA384);
        intermediateRequest.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, true, 0, true));
        intermediateRequest.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.KeyCertSign | X509KeyUsageFlags.CrlSign, true));
        intermediateRequest.CertificateExtensions.Add(new X509SubjectKeyIdentifierExtension(intermediateRequest.PublicKey, false));
        intermediateRequest.CertificateExtensions.Add(X509AuthorityKeyIdentifierExtension.CreateFromCertificate(root, true, false));
        if (intermediateOid)
        {
            intermediateRequest.CertificateExtensions.Add(new X509Extension(IntermediateOid, Null(), false));
        }

        var intermediateEnd = intermediateNotAfter ?? now.AddYears(5);
        using var intermediate = intermediateRequest.Create(root, now.AddYears(-3), intermediateEnd, Serial());
        using var intermediateWithKey = intermediate.CopyWithPrivateKey(intermediateKey);

        var leafRequest = new CertificateRequest("CN=Zaghlol Test StoreKit Signing, O=Zaghlol Tests, C=EG", leafKey, HashAlgorithmName.SHA256);
        leafRequest.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
        leafRequest.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, true));
        leafRequest.CertificateExtensions.Add(X509AuthorityKeyIdentifierExtension.CreateFromCertificate(intermediate, true, false));
        if (leafOid)
        {
            leafRequest.CertificateExtensions.Add(new X509Extension(LeafOid, Null(), false));
        }

        var leafEnd = intermediateEnd < now.AddYears(2) ? intermediateEnd : now.AddYears(2);
        using var leaf = leafRequest.Create(intermediateWithKey, now.AddYears(-2), leafEnd, Serial());

        return new AppleTestPki(rootKey, intermediateKey, leafKey, root.RawData, intermediate.RawData, leaf.RawData);
    }

    /// <summary>A transaction payload (<c>JWSTransactionDecodedPayload</c> fields; synthetic values).</summary>
    public static JsonObject Transaction(
        string bundleId,
        string productId,
        string transactionId,
        string originalTransactionId,
        string? appAccountToken,
        string environment = "Production",
        string type = "Auto-Renewable Subscription",
        string ownership = "PURCHASED",
        string reason = "PURCHASE",
        DateTimeOffset? purchaseDate = null,
        DateTimeOffset? expiresDate = null,
        DateTimeOffset? revocationDate = null,
        int? revocationReason = null,
        DateTimeOffset? signedDate = null)
    {
        var now = DateTimeOffset.UtcNow;
        var payload = new JsonObject
        {
            ["transactionId"] = transactionId,
            ["originalTransactionId"] = originalTransactionId,
            ["webOrderLineItemId"] = "9900000000000001",
            ["bundleId"] = bundleId,
            ["productId"] = productId,
            ["subscriptionGroupIdentifier"] = "21000001",
            ["purchaseDate"] = Ms(purchaseDate ?? now.AddMinutes(-1)),
            ["originalPurchaseDate"] = Ms(purchaseDate ?? now.AddMinutes(-1)),
            ["quantity"] = 1,
            ["type"] = type,
            ["inAppOwnershipType"] = ownership,
            ["signedDate"] = Ms(signedDate ?? now),
            ["environment"] = environment,
            ["transactionReason"] = reason,
            ["storefront"] = "EGY",
            ["storefrontId"] = "143516",
            ["price"] = 49990,
            ["currency"] = "EGP",
        };
        if (appAccountToken is not null)
        {
            payload["appAccountToken"] = appAccountToken;
        }

        if (type == "Auto-Renewable Subscription")
        {
            payload["expiresDate"] = Ms(expiresDate ?? now.AddDays(30));
        }

        if (revocationDate is { } revoked)
        {
            payload["revocationDate"] = Ms(revoked);
        }

        if (revocationReason is { } why)
        {
            payload["revocationReason"] = why;
        }

        return payload;
    }

    /// <summary>A renewal info payload (<c>JWSRenewalInfoDecodedPayload</c> fields).</summary>
    public static JsonObject Renewal(
        string originalTransactionId,
        string productId,
        int autoRenewStatus = 1,
        string environment = "Production",
        DateTimeOffset? gracePeriodExpiresDate = null)
    {
        var payload = new JsonObject
        {
            ["originalTransactionId"] = originalTransactionId,
            ["autoRenewProductId"] = productId,
            ["productId"] = productId,
            ["autoRenewStatus"] = autoRenewStatus,
            ["environment"] = environment,
            ["signedDate"] = Ms(DateTimeOffset.UtcNow),
            ["recentSubscriptionStartDate"] = Ms(DateTimeOffset.UtcNow.AddDays(-1)),
        };
        if (gracePeriodExpiresDate is { } grace)
        {
            payload["gracePeriodExpiresDate"] = Ms(grace);
        }

        return payload;
    }

    public static long Ms(DateTimeOffset value) => value.ToUnixTimeMilliseconds();

    public static string B64Url(byte[] bytes) => Base64Url.EncodeToString(bytes);

    public static string B64Url(string text) => Base64Url.EncodeToString(Encoding.UTF8.GetBytes(text));

    /// <summary>The standard header: <c>{alg: ES256, x5c: [leaf, intermediate, root]}</c>.</summary>
    public JsonObject Header() => new()
    {
        ["alg"] = "ES256",
        ["x5c"] = new JsonArray(Convert.ToBase64String(LeafDer), Convert.ToBase64String(IntermediateDer), Convert.ToBase64String(RootDer)),
    };

    /// <summary>A compact JWS over <paramref name="payload"/> signed with the leaf key (64-byte P1363).</summary>
    public string Sign(JsonNode payload, JsonObject? header = null) => Sign((header ?? Header()).ToJsonString(), payload.ToJsonString());

    /// <summary>A compact JWS over raw header and payload JSON text (for duplicate-member and odd-shape tests).</summary>
    public string Sign(string headerJson, string payloadJson)
    {
        var input = B64Url(headerJson) + "." + B64Url(payloadJson);
        var signature = LeafKey.SignData(Encoding.ASCII.GetBytes(input), HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
        return input + "." + B64Url(signature);
    }

    public void Dispose()
    {
        RootKey.Dispose();
        IntermediateKey.Dispose();
        LeafKey.Dispose();
    }

    private static byte[] Null()
    {
        var writer = new AsnWriter(AsnEncodingRules.DER);
        writer.WriteNull();
        return writer.Encode();
    }

    private static byte[] Serial()
    {
        // A positive, non-zero serial.
        var serial = RandomNumberGenerator.GetBytes(12);
        serial[0] = (byte)((serial[0] & 0x7F) | 0x01);
        return serial;
    }
}
