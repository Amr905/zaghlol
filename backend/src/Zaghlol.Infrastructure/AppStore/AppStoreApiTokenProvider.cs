using System.Buffers.Text;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.AppStore;

/// <summary>The App Store Server API bearer token, or <c>null</c> when no key is configured (Development and Testing only).</summary>
public interface IAppStoreApiTokenSource
{
    Sensitive<string>? GetToken();
}

/// <summary>The API token could not be minted (alerted as <c>auth_error</c>). Constant message: nothing of the key is in it.</summary>
public sealed class AppStoreApiTokenException : SafeException
{
    public AppStoreApiTokenException()
        : base("No App Store Server API token could be minted.")
    {
    }

    public AppStoreApiTokenException(string message)
        : base(message)
    {
    }

    public AppStoreApiTokenException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>
/// The App Store Server API JWT (T-131 design note §5): header <c>{alg: ES256, kid, typ: JWT}</c>, payload <c>{iss: issuerId, iat,
/// exp: iat + 20 min, aud: "appstoreconnect-v1", bid: bundleId}</c>, signed ES256 (64-byte P1363) with the In-App Purchase key.
/// Apple refuses tokens whose <c>exp</c> is more than 60 minutes after <c>iat</c>. One token is cached and re-minted 5 minutes
/// before <c>exp</c>, so a process mints about one every 15 minutes. The key is imported into <see cref="ECDsa"/> once; the PEM,
/// the key and the token are never logged.
/// </summary>
internal sealed class AppStoreApiTokenProvider : IAppStoreApiTokenSource, IDisposable
{
    public const string Audience = "appstoreconnect-v1";

    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(20);

    public static readonly TimeSpan RenewBefore = TimeSpan.FromMinutes(5);

    private readonly ECDsa? key;
    private readonly string? keyId;
    private readonly string? issuerId;
    private readonly string bundleId;
    private readonly TimeProvider clock;
    private readonly Lock gate = new();
    private (string Token, DateTimeOffset Expires)? cached;

    public AppStoreApiTokenProvider(AppStoreOptions options, TimeProvider clock)
    {
        ArgumentNullException.ThrowIfNull(options);
        this.clock = clock;
        bundleId = options.Catalog.BundleId;
        if (options.PrivateKey is { } pem)
        {
            key = LoadKey(pem.Reveal());
            keyId = options.KeyId;
            issuerId = options.IssuerId;
        }
    }

    /// <summary>Imports a PKCS#8 PEM P-256 key; anything else throws <see cref="AppStoreConfigurationException"/> (no value echoed).</summary>
    public static ECDsa LoadKey(string pem)
    {
        var key = ECDsa.Create();
        try
        {
            key.ImportFromPem(pem);
            if (!AppleKeyText.IsP256(key))
            {
                throw new AppStoreConfigurationException("Purchases:Apple:PrivateKey must be an EC P-256 key.");
            }

            return key;
        }
        catch (Exception error) when (error is ArgumentException or CryptographicException)
        {
            key.Dispose();
            throw new AppStoreConfigurationException("Purchases:Apple:PrivateKey must be the PKCS#8 PEM of the In-App Purchase key.");
        }
        catch
        {
            key.Dispose();
            throw;
        }
    }

    public Sensitive<string>? GetToken()
    {
        if (key is null)
        {
            return null;
        }

        var now = clock.GetUtcNow();
        lock (gate)
        {
            if (cached is { } current && now < current.Expires - RenewBefore)
            {
                return new Sensitive<string>(current.Token);
            }

            try
            {
                var token = Mint(now);
                cached = (token, WholeSecond(now) + Lifetime);
                return new Sensitive<string>(token);
            }
            catch (CryptographicException)
            {
                throw new AppStoreApiTokenException();
            }
        }
    }

    public void Dispose() => key?.Dispose();

    private static DateTimeOffset WholeSecond(DateTimeOffset value) => DateTimeOffset.FromUnixTimeSeconds(value.ToUnixTimeSeconds());

    private string Mint(DateTimeOffset now)
    {
        var iat = now.ToUnixTimeSeconds();
        var header = Json(w =>
        {
            w.WriteString("alg", "ES256");
            w.WriteString("kid", keyId);
            w.WriteString("typ", "JWT");
        });
        var payload = Json(w =>
        {
            w.WriteString("iss", issuerId);
            w.WriteNumber("iat", iat);
            w.WriteNumber("exp", iat + (long)Lifetime.TotalSeconds);
            w.WriteString("aud", Audience);
            w.WriteString("bid", bundleId);
        });
        var input = Base64Url.EncodeToString(header) + "." + Base64Url.EncodeToString(payload);
        var signature = key!.SignData(Encoding.ASCII.GetBytes(input), HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
        return input + "." + Base64Url.EncodeToString(signature);
    }

    private static byte[] Json(Action<Utf8JsonWriter> write)
    {
        using var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer))
        {
            writer.WriteStartObject();
            write(writer);
            writer.WriteEndObject();
        }

        return buffer.ToArray();
    }
}

/// <summary>Adds <c>Authorization: Bearer</c> to each attempt (inside the resilience pipeline, so a retry gets a valid token).</summary>
internal sealed class AppStoreAuthenticationHandler(IAppStoreApiTokenSource tokens) : DelegatingHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (tokens.GetToken() is { } token)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Reveal());
        }

        return base.SendAsync(request, cancellationToken);
    }
}
