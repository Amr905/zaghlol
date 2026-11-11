using System.Buffers.Text;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

namespace Zaghlol.Testing;

/// <summary>What <see cref="FakeOidcIssuer.Mint"/> puts in a token. <c>null</c> members are left out.</summary>
public sealed record OperatorTokenSpec
{
    public required string Subject { get; init; }

    public IReadOnlyList<string>? Amr { get; init; } = ["pwd", "mfa"];

    public IReadOnlyList<string>? Acrs { get; init; }

    public string? Audience { get; init; } = FakeOidcIssuer.CliAudience;

    public string? Issuer { get; init; }

    /// <summary><c>RS256</c>, <c>ES256</c>, <c>HS256</c> (keyed with the RSA public key) or <c>none</c>.</summary>
    public string Algorithm { get; init; } = "RS256";

    /// <summary>Overrides the key ID (default: the current key of <see cref="Algorithm"/>); <c>""</c> leaves <c>kid</c> out.</summary>
    public string? Kid { get; init; }

    public DateTimeOffset? IssuedAt { get; init; }

    /// <summary>Seconds after <see cref="IssuedAt"/>; default 3600.</summary>
    public long LifetimeSeconds { get; init; } = 3600;

    public DateTimeOffset? NotBefore { get; init; }

    public bool OmitIssuedAt { get; init; }

    public bool OmitNotBefore { get; init; }

    public bool OmitExpiry { get; init; }

    /// <summary>Extra payload members (for example <c>roles</c> or <c>groups</c>, which the API must ignore).</summary>
    public IReadOnlyDictionary<string, JsonNode?>? Extra { get; init; }

    /// <summary>Extra header members (for example <c>jku</c>, which the API must ignore).</summary>
    public IReadOnlyDictionary<string, JsonNode?>? ExtraHeader { get; init; }

    /// <summary>Signs with this RSA key instead of the issuer's (a forged token).</summary>
    public RSA? ForeignKey { get; init; }
}

/// <summary>
/// An in-process OpenID provider for operator-auth tests (T-136 design note §7): it serves the discovery document and the
/// JWKS through an <see cref="HttpMessageHandler"/> (no network) and mints tokens with RSA and P-256 keys generated per run.
/// It can rotate keys, fail every request, and announce a different issuer (mix-up). No key is ever written anywhere.
/// </summary>
public sealed class FakeOidcIssuer : IDisposable
{
    public const string DefaultIssuer = "https://login.zaghlol.test/tenant-1/v2.0";
    public const string JwksUrl = "https://login.zaghlol.test/tenant-1/discovery/v2.0/keys";
    public const string CliAudience = "zaghlol-ops";
    public const string AdminAudience = "zaghlol-admin";

    private readonly object gate = new();
    private RSA rsa = RSA.Create(2048);
    private ECDsa ec = ECDsa.Create(ECCurve.NamedCurves.nistP256);
    private int discoveryRequests;
    private int jwksRequests;
    private int generation = 1;
    private TaskCompletionSource? release;
    private TaskCompletionSource? arrived;

    private readonly string jwksUrl;

    /// <param name="issuer">The issuer it announces (Google's <c>https://accounts.google.com</c> for the T-133 push tests).</param>
    /// <param name="jwksUrl">Where its JWKS is served.</param>
    public FakeOidcIssuer(string issuer = DefaultIssuer, string jwksUrl = JwksUrl)
    {
        Issuer = issuer;
        this.jwksUrl = jwksUrl;
    }

    public string Issuer { get; }

    public string RsaKid => "rsa-" + generation;

    public string EcKid => "ec-" + generation;

    /// <summary>Every request fails with 503 while set.</summary>
    public bool Failing { get; set; }

    /// <summary>The <c>issuer</c> the discovery document announces (default: <see cref="Issuer"/>).</summary>
    public string? AnnouncedIssuer { get; set; }

    public int DiscoveryRequests => Volatile.Read(ref discoveryRequests);

    /// <summary>Completes when a request reaches the issuer while <see cref="HoldRequests"/> is in effect.</summary>
    public Task RequestArrived
    {
        get
        {
            lock (gate)
            {
                return arrived?.Task ?? Task.CompletedTask;
            }
        }
    }

    public int JwksRequests => Volatile.Read(ref jwksRequests);

    public HttpMessageHandler CreateHandler() => new Handler(this);

    /// <summary>
    /// Requests wait (honouring the client's cancellation token) until <see cref="ReleaseRequests"/>, so a test can act
    /// while a fetch is in flight.
    /// </summary>
    public void HoldRequests()
    {
        lock (gate)
        {
            release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            arrived = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        }
    }

    /// <summary>Lets held and future requests through.</summary>
    public void ReleaseRequests()
    {
        TaskCompletionSource? held;
        lock (gate)
        {
            held = release;
            release = null;
        }

        held?.TrySetResult();
    }

    /// <summary>Replaces both keys with new ones under new key IDs; tokens signed before the rotation stop verifying.</summary>
    public void Rotate()
    {
        lock (gate)
        {
            rsa.Dispose();
            ec.Dispose();
            rsa = RSA.Create(2048);
            ec = ECDsa.Create(ECCurve.NamedCurves.nistP256);
            generation++;
        }
    }

    public string Mint(OperatorTokenSpec spec, DateTimeOffset now)
    {
        ArgumentNullException.ThrowIfNull(spec);

        var header = new JsonObject { ["alg"] = spec.Algorithm, ["typ"] = "JWT" };
        var kid = spec.Kid ?? (spec.Algorithm == "ES256" ? EcKid : RsaKid);
        if (kid.Length > 0)
        {
            header["kid"] = kid;
        }

        foreach (var (name, value) in spec.ExtraHeader ?? new Dictionary<string, JsonNode?>())
        {
            header[name] = value?.DeepClone();
        }

        var iat = (spec.IssuedAt ?? now).ToUnixTimeSeconds();
        var payload = new JsonObject
        {
            ["iss"] = spec.Issuer ?? Issuer,
            ["sub"] = spec.Subject,
        };
        if (spec.Audience is not null)
        {
            payload["aud"] = spec.Audience;
        }

        if (!spec.OmitIssuedAt)
        {
            payload["iat"] = iat;
        }

        if (!spec.OmitNotBefore)
        {
            payload["nbf"] = (spec.NotBefore ?? spec.IssuedAt ?? now).ToUnixTimeSeconds();
        }

        if (!spec.OmitExpiry)
        {
            payload["exp"] = iat + spec.LifetimeSeconds;
        }

        if (spec.Amr is not null)
        {
            payload["amr"] = new JsonArray([.. spec.Amr.Select(a => (JsonNode?)JsonValue.Create(a))]);
        }

        if (spec.Acrs is not null)
        {
            payload["acrs"] = new JsonArray([.. spec.Acrs.Select(a => (JsonNode?)JsonValue.Create(a))]);
        }

        foreach (var (name, value) in spec.Extra ?? new Dictionary<string, JsonNode?>())
        {
            payload[name] = value?.DeepClone();
        }

        var signingInput = Encode(header) + "." + Encode(payload);
        var data = Encoding.ASCII.GetBytes(signingInput);
        byte[] signature;
        lock (gate)
        {
            signature = spec.Algorithm switch
            {
                "RS256" => (spec.ForeignKey ?? rsa).SignData(data, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1),
                "ES256" => ec.SignData(data, HashAlgorithmName.SHA256),
                "HS256" => HMACSHA256.HashData(Encoding.UTF8.GetBytes(Jwks()), data),
                "none" => Array.Empty<byte>(),
                _ => throw new ArgumentException("Unsupported test algorithm.", nameof(spec)),
            };
        }

        return signingInput + "." + Base64Url.EncodeToString(signature);
    }

    /// <summary>The JWKS document: the current RSA and P-256 public keys.</summary>
    public string Jwks()
    {
        lock (gate)
        {
            var rsaKey = rsa.ExportParameters(false);
            var ecKey = ec.ExportParameters(false);
            var keys = new JsonArray
            {
                new JsonObject
                {
                    ["kty"] = "RSA",
                    ["use"] = "sig",
                    ["alg"] = "RS256",
                    ["kid"] = RsaKid,
                    ["n"] = Base64Url.EncodeToString(rsaKey.Modulus!),
                    ["e"] = Base64Url.EncodeToString(rsaKey.Exponent!),
                },
                new JsonObject
                {
                    ["kty"] = "EC",
                    ["use"] = "sig",
                    ["alg"] = "ES256",
                    ["crv"] = "P-256",
                    ["kid"] = EcKid,
                    ["x"] = Base64Url.EncodeToString(ecKey.Q.X!),
                    ["y"] = Base64Url.EncodeToString(ecKey.Q.Y!),
                },
            };
            return new JsonObject { ["keys"] = keys }.ToJsonString();
        }
    }

    public void Dispose()
    {
        lock (gate)
        {
            rsa.Dispose();
            ec.Dispose();
        }
    }

    private static string Encode(JsonObject value) => Base64Url.EncodeToString(Encoding.UTF8.GetBytes(value.ToJsonString()));

    private HttpResponseMessage Respond(HttpRequestMessage request)
    {
        var url = request.RequestUri?.AbsoluteUri ?? string.Empty;
        if (Failing)
        {
            return new HttpResponseMessage(HttpStatusCode.ServiceUnavailable);
        }

        string body;
        if (string.Equals(url, Issuer + "/.well-known/openid-configuration", StringComparison.Ordinal))
        {
            Interlocked.Increment(ref discoveryRequests);
            body = new JsonObject
            {
                ["issuer"] = AnnouncedIssuer ?? Issuer,
                ["jwks_uri"] = jwksUrl,
                ["authorization_endpoint"] = Issuer + "/authorize",
                ["token_endpoint"] = Issuer + "/token",
            }.ToJsonString();
        }
        else if (string.Equals(url, jwksUrl, StringComparison.Ordinal))
        {
            Interlocked.Increment(ref jwksRequests);
            body = Jwks();
        }
        else
        {
            return new HttpResponseMessage(HttpStatusCode.NotFound);
        }

        return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
    }

    private sealed class Handler(FakeOidcIssuer issuer) : HttpMessageHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            TaskCompletionSource? held;
            lock (issuer.gate)
            {
                held = issuer.release;
                if (held is not null)
                {
                    issuer.arrived?.TrySetResult();
                }
            }

            if (held is not null)
            {
                await held.Task.WaitAsync(cancellationToken);
            }

            return issuer.Respond(request);
        }
    }
}
