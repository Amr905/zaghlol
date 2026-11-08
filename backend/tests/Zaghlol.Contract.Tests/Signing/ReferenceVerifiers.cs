using System.Buffers.Text;
using System.Globalization;
using System.Numerics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Zaghlol.Contract.Tests.Signing;

/// <summary>
/// The verification rules the app applies (T-141), written independently of the signer: a response signature is
/// accepted only with an <c>s</c> kid and the exact header grammar; a JWS only with <c>alg=ES256</c>, <c>typ=JWT</c>,
/// an <c>e</c> kid, unpadded base64url and a 64-byte P1363 signature.
/// </summary>
internal static partial class ReferenceVerifiers
{
    [GeneratedRegex("^kid=(s[0-9]{4}[a-z]); alg=ES256; sig=([A-Za-z0-9_-]{86})\\z", RegexOptions.CultureInvariant)]
    private static partial Regex ResponseHeader();

    [GeneratedRegex("^[A-Za-z0-9_-]+\\z", RegexOptions.CultureInvariant)]
    private static partial Regex Segment();

    [GeneratedRegex("^e[0-9]{4}[a-z]\\z", RegexOptions.CultureInvariant)]
    private static partial Regex EntitlementKid();

    public static bool VerifyResponse(JsonNode jwks, byte[] body, string header)
    {
        var match = ResponseHeader().Match(header);
        if (!match.Success || Find(jwks, match.Groups[1].Value) is not { } key)
        {
            return false;
        }

        return Verify(key, body, Base64Url.DecodeFromChars(match.Groups[2].Value));
    }

    public static bool VerifyJws(JsonNode jwks, string token)
    {
        var parts = token.Split('.');
        if (parts.Length != 3 || !parts.All(p => Segment().IsMatch(p)))
        {
            return false;
        }

        JsonObject header;
        try
        {
            header = JsonNode.Parse(Base64Url.DecodeFromChars(parts[0]))!.AsObject();
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException or FormatException)
        {
            return false;
        }

        if (Text(header, "alg") != "ES256" || Text(header, "typ") != "JWT" || Text(header, "kid") is not { } kid
            || !EntitlementKid().IsMatch(kid) || Find(jwks, kid) is not { } key)
        {
            return false;
        }

        byte[] signature;
        try
        {
            signature = Base64Url.DecodeFromChars(parts[2]);
        }
        catch (FormatException)
        {
            return false;
        }

        return signature.Length == 64 && Verify(key, Encoding.ASCII.GetBytes(parts[0] + "." + parts[1]), signature);
    }

    private static string? Text(JsonObject node, string name) =>
        node[name] is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    private static JsonNode? Find(JsonNode jwks, string kid) =>
        jwks["keys"]!.AsArray().FirstOrDefault(k => k!["kid"]!.GetValue<string>() == kid);

    private static bool Verify(JsonNode jwk, byte[] data, byte[] signature)
    {
        if (jwk["kty"]!.GetValue<string>() != "EC" || jwk["crv"]!.GetValue<string>() != "P-256" || jwk["d"] is not null)
        {
            return false;
        }

        using var key = ECDsa.Create(new ECParameters
        {
            Curve = ECCurve.NamedCurves.nistP256,
            Q = new ECPoint
            {
                X = Base64Url.DecodeFromChars(jwk["x"]!.GetValue<string>()),
                Y = Base64Url.DecodeFromChars(jwk["y"]!.GetValue<string>()),
            },
        });
        return key.VerifyData(data, signature, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
    }
}

/// <summary>P-256 group order arithmetic: the high-S form of a signature.</summary>
internal static class P256
{
    private static readonly BigInteger Order = BigInteger.Parse(
        "0FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551", NumberStyles.HexNumber, CultureInfo.InvariantCulture);

    public static bool IsHighS(byte[] p1363) => S(p1363) > Order / 2;

    /// <summary>The same signature with <c>s</c> replaced by <c>n − s</c> when <c>s</c> is low, so <c>s</c> is always high.</summary>
    public static byte[] ToHighS(byte[] p1363)
    {
        if (IsHighS(p1363))
        {
            return p1363;
        }

        var high = (Order - S(p1363)).ToByteArray(isUnsigned: true, isBigEndian: true);
        var result = p1363.ToArray();
        Array.Clear(result, 32, 32);
        high.CopyTo(result, 64 - high.Length);
        return result;
    }

    private static BigInteger S(byte[] p1363) => new(p1363.AsSpan(32, 32), isUnsigned: true, isBigEndian: true);
}
