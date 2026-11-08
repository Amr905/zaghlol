using System.Buffers.Text;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Contract.Tests.Signing;

/// <summary>
/// Builds the shared signing vectors (T-123 design note) with fresh <see cref="FakeKms"/> keys. ECDSA is randomized,
/// so the committed files were generated once (<c>ZAGHLOL_GEN_VECTORS=1</c>) and the private keys discarded; only the
/// public JWKs are in the files. Every run still regenerates them in memory and checks them (the generator self-check).
/// </summary>
internal static class SigningVectors
{
    public const string ResponseFile = "response-signature-v1.json";
    public const string JwsFile = "jws-es256-v1.json";

    private static readonly JsonSerializerOptions Indented = new() { WriteIndented = true };

    private static readonly string[] Bodies =
    [
        "{\"serverTime\":\"2026-11-08T12:00:00Z\",\"nextSyncNotBefore\":\"2026-11-09T12:00:00Z\",\"timeNonce\":\"kq3V9w0bQ2FwdGFpblphZw\"}",
        "{}",
        "{\"message\":\"زغلول بيقولك أهلاً\",\"timeNonce\":null}",
    ];

    public static string Serialize(JsonObject document) => document.ToJsonString(Indented) + "\n";

    public static async Task<(JsonObject Response, JsonObject Jws)> GenerateAsync()
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices();
        var signer = services.GetRequiredService<ISigner>();
        var jwks = EcPublicJwk.ToJwks(kms.Keys);
        return (await ResponseAsync(kms, signer, jwks), await JwsAsync(kms, signer, jwks));
    }

    private static async Task<JsonObject> ResponseAsync(FakeKms kms, ISigner signer, string jwks)
    {
        var valid = new JsonArray();
        string[] names = ["anchored-json", "empty-object", "utf8-arabic"];
        for (var i = 0; i < Bodies.Length; i++)
        {
            var body = Encoding.UTF8.GetBytes(Bodies[i]);
            var signature = await signer.SignAsync(SigningPurpose.Sync, body, CancellationToken.None);
            valid.Add(Case(names[i], body, signature.HeaderValue));
        }

        var main = Encoding.UTF8.GetBytes(Bodies[0]);
        var good = (await signer.SignAsync(SigningPurpose.Sync, main, CancellationToken.None)).Signature.ToArray();
        valid.Add(Case("high-s", main, Header("s0000t", P256.ToHighS(good))));

        var flipped = main.ToArray();
        flipped[5] ^= 0x01;
        var gzip = Gzip(main);
        var overGzip = (await signer.SignAsync(SigningPurpose.Sync, gzip, CancellationToken.None)).Signature.ToArray();

        var invalid = new JsonArray
        {
            Case("flipped-body-byte", flipped, Header("s0000t", good)),
            Case("unknown-kid", main, Header("s0000u", good)),
            Case("entitlement-kid-on-header", main, Header("e0000t", kms.SignRaw("e0000t", main, DSASignatureFormat.IeeeP1363FixedFieldConcatenation))),
            Case("der-signature", main, "kid=s0000t; alg=ES256; sig=" + Base64Url.EncodeToString(kms.SignRaw("s0000t", main, DSASignatureFormat.Rfc3279DerSequence))),
            Case("alg-es384", main, "kid=s0000t; alg=ES384; sig=" + Base64Url.EncodeToString(good)),
            Case("padded-signature", main, Header("s0000t", good) + "=="),
            Case("reordered-params", main, "alg=ES256; kid=s0000t; sig=" + Base64Url.EncodeToString(good)),
            Case("extra-spaces", main, "kid=s0000t;  alg=ES256; sig=" + Base64Url.EncodeToString(good)),
            Case("signature-over-gzip-bytes", main, Header("s0000t", overGzip)),
        };

        return new JsonObject
        {
            ["version"] = 1,
            ["description"] = "Zaghlol-Signature vectors (T-123, backend-api.md section 1). The header is exactly "
                + "'kid=<kid>; alg=ES256; sig=<86 base64url chars>'; the signature is ECDSA P-256 / SHA-256 in IEEE P1363 form "
                + "(r||s) over the exact body bytes (bodyB64u, uncompressed). Only 's' kids sign headers; high-S must be "
                + "accepted. Synthetic test keys; only their public JWKs are here.",
            ["jwks"] = JsonNode.Parse(jwks),
            ["valid"] = valid,
            ["invalid"] = invalid,
        };
    }

    private static async Task<JsonObject> JwsAsync(FakeKms kms, ISigner signer, string jwks)
    {
        var entitlementPayload = new
        {
            InstallId = "01JZ0000000000000000TEST01",
            Status = "active",
            Product = "gold_yearly",
            ExpiresAt = "2027-11-08T12:00:00Z",
            ServerTime = "2026-11-08T12:00:00Z",
        };
        var accountPayload = new { AccountId = "0193a3c0-0000-7000-8000-000000000001", Provider = "google", ServerTime = "2026-11-08T12:00:00Z" };

        var entitlement = await signer.CreateJwsAsync(SigningPurpose.Entitlement, entitlementPayload, CancellationToken.None);
        var account = await signer.CreateJwsAsync(SigningPurpose.Entitlement, accountPayload, CancellationToken.None);
        var parts = entitlement.Split('.');
        var payload = parts[1];
        var otherPayload = Base64Url.EncodeToString(Encoding.UTF8.GetBytes(Encoding.UTF8.GetString(Base64Url.DecodeFromChars(payload)).Replace("active", "refunded", StringComparison.Ordinal)));

        string Signed(string header, string kid, DSASignatureFormat format = DSASignatureFormat.IeeeP1363FixedFieldConcatenation)
        {
            var input = Base64Url.EncodeToString(Encoding.UTF8.GetBytes(header)) + "." + payload;
            return input + "." + Base64Url.EncodeToString(kms.SignRaw(kid, Encoding.ASCII.GetBytes(input), format));
        }

        var noneInput = Base64Url.EncodeToString("{\"alg\":\"none\",\"kid\":\"e0000t\",\"typ\":\"JWT\"}"u8) + "." + payload;
        var hsInput = Base64Url.EncodeToString("{\"alg\":\"HS256\",\"kid\":\"e0000t\",\"typ\":\"JWT\"}"u8) + "." + payload;
        var publicPoint = kms.Keys.Single(k => k.Kid == "e0000t").PublicJwk.ToX963();
        var hs = hsInput + "." + Base64Url.EncodeToString(HMACSHA256.HashData(publicPoint, Encoding.ASCII.GetBytes(hsInput)));

        return new JsonObject
        {
            ["version"] = 1,
            ["description"] = "Compact JWS vectors for entitlement and account tokens (T-123). Header exactly "
                + "{\"alg\":\"ES256\",\"kid\":<e kid>,\"typ\":\"JWT\"}; payload UTF-8 JSON; signature ECDSA P-256 / SHA-256, "
                + "IEEE P1363, over ASCII(b64u(header) '.' b64u(payload)); base64url without padding. Only 'e' kids sign "
                + "tokens. Synthetic test keys; only their public JWKs are here.",
            ["jwks"] = JsonNode.Parse(jwks),
            ["valid"] = new JsonArray
            {
                new JsonObject { ["name"] = "entitlement", ["token"] = entitlement },
                new JsonObject { ["name"] = "account", ["token"] = account },
            },
            ["invalid"] = new JsonArray
            {
                new JsonObject { ["name"] = "alg-none", ["token"] = noneInput + "." },
                new JsonObject { ["name"] = "hs256-with-public-key-as-secret", ["token"] = hs },
                new JsonObject { ["name"] = "unknown-kid", ["token"] = Signed("{\"alg\":\"ES256\",\"kid\":\"e0000u\",\"typ\":\"JWT\"}", "e0000t") },
                new JsonObject { ["name"] = "sync-kid", ["token"] = Signed("{\"alg\":\"ES256\",\"kid\":\"s0000t\",\"typ\":\"JWT\"}", "s0000t") },
                new JsonObject { ["name"] = "der-signature", ["token"] = Signed("{\"alg\":\"ES256\",\"kid\":\"e0000t\",\"typ\":\"JWT\"}", "e0000t", DSASignatureFormat.Rfc3279DerSequence) },
                new JsonObject { ["name"] = "padded-signature", ["token"] = entitlement + "==" },
                new JsonObject { ["name"] = "modified-payload", ["token"] = parts[0] + "." + otherPayload + "." + parts[2] },
            },
        };
    }

    private static string Header(string kid, byte[] signature) => $"kid={kid}; alg=ES256; sig={Base64Url.EncodeToString(signature)}";

    private static JsonObject Case(string name, byte[] body, string header) =>
        new() { ["name"] = name, ["bodyB64u"] = Base64Url.EncodeToString(body), ["header"] = header };

    private static byte[] Gzip(byte[] data)
    {
        using var output = new MemoryStream();
        using (var gzip = new GZipStream(output, CompressionLevel.Optimal, leaveOpen: true))
        {
            gzip.Write(data);
        }

        return output.ToArray();
    }
}
