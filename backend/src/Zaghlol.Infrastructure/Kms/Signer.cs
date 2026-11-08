using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>
/// ES256 through <see cref="ISigningKeyProvider"/>. Only the active key of a purpose signs; <c>Sync</c> signs raw bytes
/// (response bodies, catalog snapshots) and <c>Entitlement</c> signs JWS tokens, so a kid is never used in both places.
/// Every signature is checked against the published JWK before it is returned, so a wrong key reference fails closed.
/// </summary>
internal sealed class Signer(SigningKeyRing ring, ISigningKeyProvider provider, KmsCallPolicy policy, TimeProvider clock) : ISigner
{
    internal static readonly JsonSerializerOptions PayloadJson = new(JsonSerializerDefaults.Web) { WriteIndented = false };

    public async ValueTask<ResponseSignature> SignAsync(SigningPurpose purpose, ReadOnlyMemory<byte> data, CancellationToken cancellationToken)
    {
        if (purpose != SigningPurpose.Sync)
        {
            throw new ArgumentException("Raw signatures (response headers, catalog .sig files) use the Sync keys.", nameof(purpose));
        }

        var key = ring.Active(purpose);
        var signature = await SignDigestAsync(key, SHA256.HashData(data.Span), cancellationToken);
        return new ResponseSignature(key.Kid, signature);
    }

    public async ValueTask<string> CreateJwsAsync<T>(SigningPurpose purpose, T payload, CancellationToken cancellationToken)
    {
        if (purpose != SigningPurpose.Entitlement)
        {
            throw new ArgumentException("JWS tokens use the Entitlement keys.", nameof(purpose));
        }

        var key = ring.Active(purpose);
        var signingInput = SigningInput(key.Kid, JsonSerializer.SerializeToUtf8Bytes(payload, PayloadJson));
        var signature = await SignDigestAsync(key, SHA256.HashData(Encoding.ASCII.GetBytes(signingInput)), cancellationToken);
        return signingInput + "." + Base64Url.EncodeToString(signature);
    }

    public IReadOnlyList<SigningKey> PublishedKeys(SigningPurpose purpose) => ring.Published(purpose);

    /// <summary><c>b64u(header).b64u(payload)</c> with the fixed header <c>{"alg":"ES256","kid":…,"typ":"JWT"}</c>.</summary>
    internal static string SigningInput(string kid, ReadOnlySpan<byte> payloadUtf8)
    {
        var header = Encoding.UTF8.GetBytes("{\"alg\":\"ES256\",\"kid\":\"" + kid + "\",\"typ\":\"JWT\"}");
        return Base64Url.EncodeToString(header) + "." + Base64Url.EncodeToString(payloadUtf8);
    }

    private async ValueTask<byte[]> SignDigestAsync(SigningKey key, byte[] digest, CancellationToken cancellationToken)
    {
        byte[] signature;
        try
        {
            signature = await KmsCall.RunAsync(policy, clock, "sign", ct => provider.SignDigestAsync(key.KeyRef, digest, ct), cancellationToken);
        }
        catch (CryptographicException)
        {
            KmsMetrics.KmsUnavailable("sign");
            throw new KmsUnavailableException();
        }

        if (!key.PublicJwk.VerifiesDigest(digest, signature))
        {
            KmsMetrics.KmsUnavailable("sign");
            throw new KmsUnavailableException();
        }

        return signature;
    }
}

/// <summary>Raw HMAC-SHA256 through <see cref="IHmacProvider"/>; the key reference comes from <c>Kms:HmacKeys</c>.</summary>
internal sealed class KeyedHasher(KmsSettings settings, IHmacProvider provider, KmsCallPolicy policy, TimeProvider clock) : IKeyedHasher
{
    public async ValueTask<byte[]> HmacSha256Async(KeyedHashKey key, ReadOnlyMemory<byte> data, CancellationToken cancellationToken)
    {
        var keyRef = settings.HmacKeyRefs[key];
        byte[] mac;
        try
        {
            mac = await KmsCall.RunAsync(policy, clock, "hmac", ct => provider.HmacSha256Async(keyRef, data, ct), cancellationToken);
        }
        catch (CryptographicException)
        {
            KmsMetrics.KmsUnavailable("hmac");
            throw new KmsUnavailableException();
        }

        if (mac.Length != 32)
        {
            KmsMetrics.KmsUnavailable("hmac");
            throw new KmsUnavailableException();
        }

        return mac;
    }
}
