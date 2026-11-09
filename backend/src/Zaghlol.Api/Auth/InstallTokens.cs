using System.Buffers.Text;
using System.Diagnostics.CodeAnalysis;
using System.Security.Cryptography;
using System.Text;

namespace Zaghlol.Api.Auth;

/// <summary>
/// The install credential (backend-api §3): 32 bytes from <see cref="RandomNumberGenerator"/>, base64url without padding
/// (43 characters). The server keeps only <c>SHA-256</c> of the token's ASCII text: a 256-bit random secret needs no pepper
/// or slow KDF, and a deterministic hash makes authentication one indexed lookup with no KMS call per request.
/// </summary>
internal static class InstallTokens
{
    public const int Length = 43;
    public const int RandomBytes = 32;

    private const string BearerPrefix = "Bearer ";

    public static string Generate() => Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(RandomBytes));

    public static byte[] Hash(string token)
    {
        ArgumentNullException.ThrowIfNull(token);
        return SHA256.HashData(Encoding.ASCII.GetBytes(token));
    }

    /// <summary>Exactly 43 base64url characters; anything else is rejected before any database access.</summary>
    public static bool IsWellFormed([NotNullWhen(true)] string? token)
    {
        if (token is null || token.Length != Length)
        {
            return false;
        }

        foreach (var c in token)
        {
            if (!(c is (>= 'A' and <= 'Z') or (>= 'a' and <= 'z') or (>= '0' and <= '9') or '-' or '_'))
            {
                return false;
            }
        }

        return true;
    }

    /// <summary><c>Authorization: Bearer &lt;token&gt;</c> with one well-formed token and nothing else.</summary>
    public static bool TryReadBearer(string? header, [NotNullWhen(true)] out string? token)
    {
        token = null;
        if (header is null || !header.StartsWith(BearerPrefix, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var candidate = header[BearerPrefix.Length..];
        if (!IsWellFormed(candidate))
        {
            return false;
        }

        token = candidate;
        return true;
    }
}
