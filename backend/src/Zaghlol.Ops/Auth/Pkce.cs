using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;

namespace Zaghlol.Ops.Auth;

/// <summary>PKCE (RFC 7636) with S256 only, and the random values of one authorization request.</summary>
internal sealed record Pkce(string Verifier, string Challenge, string State, string Nonce)
{
    public static Pkce Create()
    {
        var verifier = Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(32));
        return new Pkce(verifier, ChallengeFor(verifier), Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(16)), Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(16)));
    }

    public static string ChallengeFor(string verifier) => Base64Url.EncodeToString(SHA256.HashData(Encoding.ASCII.GetBytes(verifier)));
}
