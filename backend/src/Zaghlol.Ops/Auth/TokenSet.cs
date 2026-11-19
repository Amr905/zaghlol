using System.Buffers.Text;
using System.Text.Json;

namespace Zaghlol.Ops.Auth;

/// <summary>A signed-in token and when it stops being valid. The value is a bearer credential: never print or log it.</summary>
internal sealed record TokenSet(string Token, DateTimeOffset ExpiresAt, string? Subject)
{
    /// <summary>The stored form: <c>v1.{exp}.{token}</c>, using only the characters of a JWT so every store can carry it.</summary>
    public string Serialize() => "v1." + ExpiresAt.ToUnixTimeSeconds().ToString(System.Globalization.CultureInfo.InvariantCulture) + "." + Token;

    public static TokenSet? TryParse(string? stored)
    {
        if (stored is null || !stored.StartsWith("v1.", StringComparison.Ordinal))
        {
            return null;
        }

        var rest = stored[3..];
        var dot = rest.IndexOf('.', StringComparison.Ordinal);
        if (dot <= 0 || !long.TryParse(rest[..dot], System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var exp))
        {
            return null;
        }

        var token = rest[(dot + 1)..];
        return IsTokenShaped(token) ? new TokenSet(token, DateTimeOffset.FromUnixTimeSeconds(exp), ReadClaim(token, "sub")) : null;
    }

    /// <summary>Only a compact JWS (three base64url parts) is accepted; this is also what makes the macOS command line safe.</summary>
    public static bool IsTokenShaped(string token)
    {
        if (token.Length is < 20 or > 16384)
        {
            return false;
        }

        var parts = token.Split('.');
        return parts.Length == 3 && parts.All(p => p.Length > 0 && p.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_'));
    }

    /// <summary>A string or numeric claim of an unverified JWT payload (the API verifies it; the CLI only reads expiry and subject).</summary>
    public static string? ReadClaim(string jwt, string name)
    {
        using var payload = ReadPayload(jwt);
        if (payload is null || !payload.RootElement.TryGetProperty(name, out var claim))
        {
            return null;
        }

        return claim.ValueKind switch
        {
            JsonValueKind.String => claim.GetString(),
            JsonValueKind.Number => claim.GetRawText(),
            _ => null,
        };
    }

    public static JsonDocument? ReadPayload(string jwt)
    {
        var parts = jwt.Split('.');
        if (parts.Length != 3 || !Base64Url.IsValid(parts[1]))
        {
            return null;
        }

        try
        {
            var document = JsonDocument.Parse(Base64Url.DecodeFromChars(parts[1]));
            if (document.RootElement.ValueKind == JsonValueKind.Object)
            {
                return document;
            }

            document.Dispose();
            return null;
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
