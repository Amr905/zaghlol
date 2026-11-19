using System.Text.Json;
using System.Text.RegularExpressions;

namespace Zaghlol.Ops;

/// <summary>Which token the API receives: the ID token works with every IdP (Google has no other JWT), an Entra access token needs v2.</summary>
internal enum TokenUse
{
    IdToken,
    AccessToken,
}

/// <summary>Where a signed-in token may be kept between runs. Never a file.</summary>
internal enum TokenCacheMode
{
    /// <summary>The OS credential store when there is one, else memory for this process only.</summary>
    Os,

    /// <summary>Memory for this process only.</summary>
    Memory,
}

/// <summary>A bad setting. Messages name settings only, never values.</summary>
internal sealed class OpsConfigException(string message) : Exception(message)
{
}

/// <summary>
/// Operator CLI settings (T-137 design note section 1): the API, the IdP and the public client. All values are public except the
/// optional client secret that Google's desktop client type asks for (Google itself treats it as non-confidential); it can be set
/// only through the environment, never through the file or a flag.
/// </summary>
internal sealed record OpsConfig(
    Uri ApiUrl,
    Uri Issuer,
    string ClientId,
    string? ClientSecret,
    string Scopes,
    TokenUse TokenUse,
    string RedirectHost,
    TokenCacheMode TokenCache)
{
    public const string EnvPrefix = "ZAGHLOL_OPS_";

    /// <summary>The only environment variables the CLI reads. A test asserts nothing else is read (no order-ID variable can exist).</summary>
    public static readonly IReadOnlyList<string> EnvironmentVariables =
    [
        EnvPrefix + "CONFIG",
        EnvPrefix + "API_URL",
        EnvPrefix + "ISSUER",
        EnvPrefix + "CLIENT_ID",
        EnvPrefix + "CLIENT_SECRET",
        EnvPrefix + "SCOPES",
        EnvPrefix + "TOKEN_USE",
        EnvPrefix + "REDIRECT_HOST",
        EnvPrefix + "TOKEN_CACHE",
    ];

    private static readonly Regex ScopePattern = new("^[A-Za-z0-9:/._ -]{1,200}$", RegexOptions.CultureInvariant, TimeSpan.FromSeconds(1));
    private static readonly Regex ClientIdPattern = new("^[A-Za-z0-9._@:/-]{1,200}$", RegexOptions.CultureInvariant, TimeSpan.FromSeconds(1));

    /// <summary>Settings from the optional JSON file, then the environment on top (the environment wins).</summary>
    public static OpsConfig Load(Func<string, string?> environment, string? configPathOption, Func<string, string?> readFile, string? defaultConfigPath)
    {
        ArgumentNullException.ThrowIfNull(environment);
        ArgumentNullException.ThrowIfNull(readFile);

        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        var explicitPath = configPathOption ?? environment(EnvPrefix + "CONFIG");
        var path = explicitPath ?? defaultConfigPath;
        if (path is not null)
        {
            var text = readFile(path);
            if (text is null && explicitPath is not null)
            {
                throw new OpsConfigException("The settings file could not be read.");
            }

            if (text is not null)
            {
                ReadFile(text, values);
            }
        }

        string? Pick(string name, string key) => environment(EnvPrefix + name) is { Length: > 0 } fromEnv ? fromEnv : values.GetValueOrDefault(key);

        var api = RequireUri(Pick("API_URL", "apiUrl"), "apiUrl", allowLoopbackHttp: true);
        var issuer = RequireUri(Pick("ISSUER", "issuer"), "issuer", allowLoopbackHttp: false);
        var clientId = Pick("CLIENT_ID", "clientId");
        if (clientId is null || !ClientIdPattern.IsMatch(clientId))
        {
            throw new OpsConfigException("clientId is missing or has characters that a client ID does not use.");
        }

        var secret = environment(EnvPrefix + "CLIENT_SECRET");
        if (secret is { Length: 0 })
        {
            secret = null;
        }

        var scopes = Pick("SCOPES", "scopes") ?? "openid email";
        if (!ScopePattern.IsMatch(scopes) || !scopes.Split(' ', StringSplitOptions.RemoveEmptyEntries).Contains("openid", StringComparer.Ordinal))
        {
            throw new OpsConfigException("scopes must be space-separated scope names that include openid.");
        }

        var use = (Pick("TOKEN_USE", "tokenUse") ?? "id_token") switch
        {
            "id_token" => TokenUse.IdToken,
            "access_token" => TokenUse.AccessToken,
            _ => throw new OpsConfigException("tokenUse must be id_token or access_token."),
        };
        var host = Pick("REDIRECT_HOST", "redirectHost") ?? "localhost";
        if (host is not ("localhost" or "127.0.0.1"))
        {
            throw new OpsConfigException("redirectHost must be localhost or 127.0.0.1.");
        }

        var cache = (Pick("TOKEN_CACHE", "tokenCache") ?? "os") switch
        {
            "os" => TokenCacheMode.Os,
            "memory" => TokenCacheMode.Memory,
            _ => throw new OpsConfigException("tokenCache must be os or memory."),
        };

        return new OpsConfig(api, issuer, clientId, secret, string.Join(' ', scopes.Split(' ', StringSplitOptions.RemoveEmptyEntries)), use, host, cache);
    }

    /// <summary>A stable key for this IdP and client; names the credential-store entry. Public values only.</summary>
    public string CacheKey()
    {
        var bytes = System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(Issuer.AbsoluteUri + "|" + ClientId + "|" + ApiUrl.AbsoluteUri));
        return Convert.ToHexStringLower(bytes.AsSpan(0, 12));
    }

    private static void ReadFile(string text, Dictionary<string, string> values)
    {
        if (text.Length > 16 * 1024)
        {
            throw new OpsConfigException("The settings file is too large.");
        }

        try
        {
            using var document = JsonDocument.Parse(text);
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                throw new OpsConfigException("The settings file must be a JSON object.");
            }

            foreach (var property in document.RootElement.EnumerateObject())
            {
                // clientSecret is deliberately not accepted from a file.
                if (property.Name is "apiUrl" or "issuer" or "clientId" or "scopes" or "tokenUse" or "redirectHost" or "tokenCache"
                    && property.Value.ValueKind == JsonValueKind.String)
                {
                    values[property.Name] = property.Value.GetString()!;
                }
                else
                {
                    throw new OpsConfigException("The settings file has a member that is not a known string setting.");
                }
            }
        }
        catch (JsonException)
        {
            throw new OpsConfigException("The settings file is not valid JSON.");
        }
    }

    private static Uri RequireUri(string? value, string name, bool allowLoopbackHttp)
    {
        if (value is null || !Uri.TryCreate(value, UriKind.Absolute, out var uri) || !string.IsNullOrEmpty(uri.UserInfo)
            || !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment))
        {
            throw new OpsConfigException($"{name} must be an absolute URL without credentials, query or fragment.");
        }

        var loopbackHttp = allowLoopbackHttp && uri.Scheme == Uri.UriSchemeHttp && uri.IsLoopback;
        if (uri.Scheme != Uri.UriSchemeHttps && !loopbackHttp)
        {
            throw new OpsConfigException($"{name} must use https (http only for a loopback API during development).");
        }

        return uri;
    }
}
