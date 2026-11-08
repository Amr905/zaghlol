using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>A P-256 public key as a JWK (<c>kty</c>, <c>crv</c>, <c>x</c>, <c>y</c>; coordinates base64url, 32 bytes each).</summary>
public sealed record EcPublicJwk(string Kty, string Crv, string X, string Y)
{
    public const string EcKeyType = "EC";
    public const string P256 = "P-256";

    /// <summary>From an X9.63 uncompressed point (<c>0x04 ‖ X ‖ Y</c>, 65 bytes).</summary>
    public static EcPublicJwk FromX963(ReadOnlySpan<byte> point)
    {
        if (point.Length != 65 || point[0] != 0x04)
        {
            throw new ArgumentException("Expected a 65-byte uncompressed P-256 point.", nameof(point));
        }

        return new EcPublicJwk(EcKeyType, P256, Base64Url.EncodeToString(point[1..33]), Base64Url.EncodeToString(point[33..65]));
    }

    /// <summary>True when this is a well-formed P-256 key whose point is on the curve.</summary>
    public bool IsValidP256()
    {
        if (!string.Equals(Kty, EcKeyType, StringComparison.Ordinal) || !string.Equals(Crv, P256, StringComparison.Ordinal))
        {
            return false;
        }

        if (!TryCoordinates(out _, out _))
        {
            return false;
        }

        try
        {
            using var key = ECDsa.Create(ToParameters());
            return true;
        }
        catch (CryptographicException)
        {
            return false;
        }
    }

    /// <summary>The X9.63 uncompressed point (<c>0x04 ‖ X ‖ Y</c>).</summary>
    public byte[] ToX963()
    {
        if (!TryCoordinates(out var x, out var y))
        {
            throw new InvalidOperationException("The JWK coordinates are not 32-byte base64url values.");
        }

        return [0x04, .. x, .. y];
    }

    /// <summary>The JWK object for app embedding: <c>{"kty","crv","x","y","kid","use":"sig","alg":"ES256"}</c>.</summary>
    public void WriteTo(Utf8JsonWriter writer, string kid)
    {
        ArgumentNullException.ThrowIfNull(writer);

        writer.WriteStartObject();
        writer.WriteString("kty", Kty);
        writer.WriteString("crv", Crv);
        writer.WriteString("x", X);
        writer.WriteString("y", Y);
        writer.WriteString("kid", kid);
        writer.WriteString("use", "sig");
        writer.WriteString("alg", "ES256");
        writer.WriteEndObject();
    }

    /// <summary>A JWKS document (<c>{"keys":[…]}</c>) of the given keys, for embedding in the app.</summary>
    public static string ToJwks(IEnumerable<SigningKey> keys)
    {
        ArgumentNullException.ThrowIfNull(keys);

        using var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer))
        {
            writer.WriteStartObject();
            writer.WriteStartArray("keys");
            foreach (var key in keys)
            {
                key.PublicJwk.WriteTo(writer, key.Kid);
            }

            writer.WriteEndArray();
            writer.WriteEndObject();
        }

        return Encoding.UTF8.GetString(buffer.ToArray());
    }

    internal ECParameters ToParameters()
    {
        if (!TryCoordinates(out var x, out var y))
        {
            throw new InvalidOperationException("The JWK coordinates are not 32-byte base64url values.");
        }

        return new ECParameters { Curve = ECCurve.NamedCurves.nistP256, Q = new ECPoint { X = x, Y = y } };
    }

    /// <summary>Verifies a P1363 signature over <paramref name="data"/> with this public key.</summary>
    internal bool Verifies(ReadOnlySpan<byte> data, ReadOnlySpan<byte> signature)
    {
        if (signature.Length != 64)
        {
            return false;
        }

        using var key = ECDsa.Create(ToParameters());
        return key.VerifyData(data, signature, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
    }

    /// <summary>Verifies a P1363 signature over a SHA-256 digest with this public key.</summary>
    internal bool VerifiesDigest(ReadOnlySpan<byte> sha256, ReadOnlySpan<byte> signature)
    {
        if (signature.Length != 64)
        {
            return false;
        }

        using var key = ECDsa.Create(ToParameters());
        return key.VerifyHash(sha256, signature, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
    }

    private bool TryCoordinates(out byte[] x, out byte[] y)
    {
        x = [];
        y = [];
        if (X is null || Y is null || X.Length != 43 || Y.Length != 43)
        {
            return false;
        }

        try
        {
            x = Base64Url.DecodeFromChars(X);
            y = Base64Url.DecodeFromChars(Y);
        }
        catch (FormatException)
        {
            return false;
        }

        return x.Length == 32 && y.Length == 32;
    }
}
