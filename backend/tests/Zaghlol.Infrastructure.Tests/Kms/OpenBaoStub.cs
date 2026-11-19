using System.Buffers.Text;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>
/// T-201: an in-process stand-in for the OpenBao endpoints the adapter and the key tool use, over TLS with its own test CA.
/// It follows OpenBao's source (2.7 line) where it matters: real ECDSA P-256 (JWS marshaling = r‖s, unpadded base64url),
/// HMAC with the key itself for <c>hmac</c> keys and a random companion key for the others, AES-256-GCM with
/// <c>nonce ‖ ciphertext ‖ tag</c> and <c>associated_data</c>, <c>vault:v&lt;n&gt;:</c> prefixes, BYOK unwrap
/// (RSA-OAEP-SHA256 of the ephemeral key, then AES-KWP), the <c>{"errors":[…]}</c> shapes and status codes (sealed 503,
/// denied/expired token 403, bad request 400, missing key 404 on read). Policies are HCL parsed with OpenBao's priority rules;
/// the tests load them from <c>setup.sh policy …</c>, so the committed policies are what the adapter is tested against.
/// </summary>
internal sealed partial class OpenBaoStub : IAsyncDisposable
{
    public const string Mount = "transit";

    private static readonly Lazy<RSA> SharedWrappingKey = new(() => RSA.Create(4096));

    private readonly ConcurrentDictionary<string, StubKey> keys = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, (string SecretId, string[] Policies)> roles = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, (string[] Policies, DateTimeOffset? Expires)> tokens = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, List<(string Pattern, string[] Capabilities)>> policies = new(StringComparer.Ordinal);
    private readonly X509Certificate2 serverCertificate;
    private WebApplication? app;
    private int port;
    private int logins;

    private OpenBaoStub(TestCa ca)
    {
        Ca = ca;
        serverCertificate = ca.IssueServerCertificate();
    }

    /// <summary>The CA that issued the server certificate (PEM), for the adapter's <c>ca.pem</c>.</summary>
    public TestCa Ca { get; }

    public Uri Address => new($"https://127.0.0.1:{port}");

    public string RootToken { get; } = "s." + Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(12));

    /// <summary>Every request as <c>METHOD path body</c>, in order.</summary>
    public ConcurrentQueue<string> Requests { get; } = new();

    public bool Sealed { get; set; }

    public TimeSpan Delay { get; set; }

    /// <summary>The <c>lease_duration</c> of new tokens, seconds.</summary>
    public int TokenTtlSeconds { get; set; } = 3600;

    public int Logins => Volatile.Read(ref logins);

    public static async Task<OpenBaoStub> StartAsync(TestCa? ca = null)
    {
        var stub = new OpenBaoStub(ca ?? new TestCa("zaghlol-test-openbao-ca"));
        await stub.ListenAsync(0);
        return stub;
    }

    /// <summary>Stops and starts the listener on the same port; keys, roles and tokens are kept (raft storage would keep them).</summary>
    public async Task RestartAsync()
    {
        await app!.DisposeAsync();
        await ListenAsync(port);
    }

    public async ValueTask DisposeAsync()
    {
        if (app is not null)
        {
            await app.DisposeAsync();
        }

        serverCertificate.Dispose();
    }

    public void CreateKey(string name, string type, bool exportable = false, bool allowPlaintextBackup = false, bool deletionAllowed = false)
    {
        var key = new StubKey(name, type) { Exportable = exportable, AllowPlaintextBackup = allowPlaintextBackup, DeletionAllowed = deletionAllowed };
        key.AddVersion(type switch
        {
            "ecdsa-p256" => ECDsa.Create(ECCurve.NamedCurves.nistP256),
            _ => null,
        }, RandomNumberGenerator.GetBytes(32));
        if (!keys.TryAdd(name, key))
        {
            throw new InvalidOperationException("exists");
        }
    }

    /// <summary>Puts raw key bytes in directly (tests of the adapter's own guards; the tool goes through import).</summary>
    public void PutRawKey(string name, string type, byte[] material)
    {
        var key = new StubKey(name, type) { Imported = true };
        key.AddVersion(null, material);
        keys[name] = key;
    }

    public void RotateKey(string name)
    {
        var key = keys[name];
        key.AddVersion(key.Type == "ecdsa-p256" ? ECDsa.Create(ECCurve.NamedCurves.nistP256) : null, RandomNumberGenerator.GetBytes(32));
    }

    public void DeleteKey(string name) => keys.TryRemove(name, out _);

    public bool HasKey(string name) => keys.ContainsKey(name);

    public void SetPolicy(string name, string hcl)
    {
        var rules = new List<(string, string[])>();
        foreach (Match match in PolicyStanza().Matches(hcl))
        {
            var capabilities = match.Groups[2].Value.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(c => c.Trim('"')).ToArray();
            rules.Add((match.Groups[1].Value, capabilities));
        }

        policies[name] = rules;
    }

    /// <summary>Loads <c>setup.sh policy &lt;which&gt;</c> (the committed script) as policy <c>zaghlol-&lt;which&gt;</c>.</summary>
    public void LoadSetupPolicy(string which, IDictionary<string, string> environment)
    {
        var script = Path.Combine(AppContext.BaseDirectory, "openbao", "setup.sh");
        var start = new ProcessStartInfo("/bin/sh") { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false };
        start.ArgumentList.Add(script);
        start.ArgumentList.Add("policy");
        start.ArgumentList.Add(which);
        foreach (var (key, value) in environment)
        {
            start.Environment[key] = value;
        }

        using var process = Process.Start(start)!;
        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();
        process.WaitForExit();
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException("setup.sh policy failed: " + error);
        }

        SetPolicy("zaghlol-" + which, output);
    }

    /// <summary>Creates an AppRole bound to <paramref name="policyNames"/>; returns (role_id, secret_id).</summary>
    public (string RoleId, string SecretId) CreateRole(params string[] policyNames)
    {
        var roleId = Guid.NewGuid().ToString();
        var secretId = Guid.NewGuid().ToString();
        roles[roleId] = (secretId, policyNames);
        return (roleId, secretId);
    }

    public string CreateToken(params string[] policyNames)
    {
        var token = "s." + Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(12));
        tokens[token] = (policyNames, null);
        return token;
    }

    public void RevokeAllTokens() => tokens.Clear();

    private async Task ListenAsync(int listenPort)
    {
        var builder = WebApplication.CreateSlimBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.ConfigureKestrel(o => o.Listen(IPAddress.Loopback, listenPort, l => l.UseHttps(serverCertificate)));
        app = builder.Build();
        app.Run(HandleAsync);
        await app.StartAsync();
        var address = app.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single();
        port = new Uri(address).Port;
    }

    private async Task HandleAsync(HttpContext context)
    {
        var path = context.Request.Path.Value ?? string.Empty;
        using var reader = new StreamReader(context.Request.Body);
        var bodyText = await reader.ReadToEndAsync();
        Requests.Enqueue($"{context.Request.Method} {path} {bodyText}");

        if (Delay > TimeSpan.Zero)
        {
            await Task.Delay(Delay, context.RequestAborted);
        }

        if (Sealed)
        {
            await Error(context, 503, "Vault is sealed");
            return;
        }

        if (!path.StartsWith("/v1/", StringComparison.Ordinal))
        {
            await Error(context, 404);
            return;
        }

        path = path["/v1/".Length..];
        var body = bodyText.Length == 0 ? new JsonObject() : JsonNode.Parse(bodyText)!.AsObject();

        if (path == "auth/approle/login" && context.Request.Method == "POST")
        {
            await LoginAsync(context, body);
            return;
        }

        var token = context.Request.Headers["X-Vault-Token"].ToString();
        if (!Authorized(token, context.Request.Method, path))
        {
            await Error(context, 403, "1 error occurred:\n\t* permission denied\n\n");
            return;
        }

        var segments = path.Split('/');
        if (segments.Length < 2 || segments[0] != Mount)
        {
            await Error(context, 404, "1 error occurred:\n\t* unsupported path\n\n");
            return;
        }

        try
        {
            var route = (segments[1], segments.Length, context.Request.Method);
            await (route switch
            {
                ("keys", 3, "GET") => ReadKey(context, segments[2]),
                ("keys", 3, "POST") => CreateKeyRequest(context, segments[2], body),
                ("keys", 4, "POST") when segments[3] == "import" => Import(context, segments[2], body),
                ("wrapping_key", 2, "GET") => Json(context, 200, new JsonObject { ["data"] = new JsonObject { ["public_key"] = SharedWrappingKey.Value.ExportSubjectPublicKeyInfoPem() } }),
                ("sign", 4, "POST") => Sign(context, segments[2], body),
                ("hmac", 4, "POST") => Hmac(context, segments[2], body),
                ("datakey", 4, "POST") when segments[2] == "plaintext" => DataKey(context, segments[3], body),
                ("decrypt", 3, "POST") => Decrypt(context, segments[2], body),
                _ => Error(context, 404, "1 error occurred:\n\t* unsupported path\n\n"),
            });
        }
        catch (StubError error)
        {
            await Error(context, error.Status, error.Message);
        }
    }

    private async Task LoginAsync(HttpContext context, JsonObject body)
    {
        var roleId = (string?)body["role_id"];
        var secretId = (string?)body["secret_id"];
        if (roleId is null || !roles.TryGetValue(roleId, out var role) || role.SecretId != secretId)
        {
            await Error(context, 400, "invalid role or secret ID");
            return;
        }

        Interlocked.Increment(ref logins);
        var token = "s." + Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(12));
        tokens[token] = (role.Policies, DateTimeOffset.UtcNow.AddSeconds(TokenTtlSeconds));
        await Json(context, 200, new JsonObject
        {
            ["auth"] = new JsonObject
            {
                ["client_token"] = token,
                ["accessor"] = "acc",
                ["policies"] = new JsonArray([.. role.Policies.Select(p => (JsonNode)p!)]),
                ["lease_duration"] = TokenTtlSeconds,
                ["renewable"] = true,
            },
        });
    }

    private bool Authorized(string token, string method, string path)
    {
        if (token == RootToken)
        {
            return true;
        }

        if (!tokens.TryGetValue(token, out var held) || (held.Expires is { } expires && expires <= DateTimeOffset.UtcNow))
        {
            return false;
        }

        var segments = path.Split('/');
        var needs = method == "GET" ? "read"
            : segments is [_, "keys", var name, "import"] && !keys.ContainsKey(name) ? "create"
            : "update";

        var rules = held.Policies.SelectMany(p => policies.GetValueOrDefault(p) ?? []).Where(r => Matches(r.Pattern, path)).ToList();
        if (rules.Count == 0)
        {
            return false;
        }

        // OpenBao: only the highest-priority pattern applies (capabilities of that pattern merged across policies); deny wins.
        var best = rules.Select(r => r.Pattern).Distinct().Aggregate((a, b) => Lower(a, b) ? b : a);
        var capabilities = rules.Where(r => r.Pattern == best).SelectMany(r => r.Capabilities).ToHashSet();
        return !capabilities.Contains("deny") && capabilities.Contains(needs);
    }

    private static bool Matches(string pattern, string path)
    {
        var regex = "^" + Regex.Escape(pattern.EndsWith('*') ? pattern[..^1] : pattern).Replace("\\+", "[^/]*", StringComparison.Ordinal)
            + (pattern.EndsWith('*') ? ".*" : string.Empty) + "$";
        return Regex.IsMatch(path, regex, RegexOptions.CultureInvariant);
    }

    /// <summary>OpenBao's policy priority: true when <paramref name="p1"/> is lower priority than <paramref name="p2"/>.</summary>
    private static bool Lower(string p1, string p2)
    {
        static int FirstWildcard(string p) => p.IndexOfAny(['+', '*']) is var i and >= 0 ? i : int.MaxValue;
        if (FirstWildcard(p1) != FirstWildcard(p2))
        {
            return FirstWildcard(p1) < FirstWildcard(p2);
        }

        if (p1.EndsWith('*') != p2.EndsWith('*'))
        {
            return p1.EndsWith('*');
        }

        var plus1 = p1.Count(c => c == '+');
        var plus2 = p2.Count(c => c == '+');
        if (plus1 != plus2)
        {
            return plus1 > plus2;
        }

        return p1.Length != p2.Length ? p1.Length < p2.Length : string.CompareOrdinal(p1, p2) < 0;
    }

    private Task ReadKey(HttpContext context, string name)
    {
        if (!keys.TryGetValue(name, out var key))
        {
            return Json(context, 404, new JsonObject { ["errors"] = new JsonArray() });
        }

        var data = new JsonObject
        {
            ["name"] = key.Name,
            ["type"] = key.Type,
            ["derived"] = false,
            ["deletion_allowed"] = key.DeletionAllowed,
            ["min_available_version"] = 0,
            ["min_decryption_version"] = 1,
            ["min_encryption_version"] = 0,
            ["latest_version"] = key.Latest,
            ["exportable"] = key.Exportable,
            ["allow_plaintext_backup"] = key.AllowPlaintextBackup,
            ["supports_encryption"] = key.Type != "hmac",
            ["supports_decryption"] = key.Type != "hmac",
            ["supports_signing"] = key.Type == "ecdsa-p256",
            ["supports_derivation"] = key.Type == "aes256-gcm96",
            ["auto_rotate_period"] = 0,
            ["imported_key"] = key.Imported,
            ["soft_deleted"] = false,
        };
        if (key.Type == "hmac")
        {
            data["key_size"] = key.Version(1).Material.Length;
        }

        if (key.Imported)
        {
            data["imported_key_allow_rotation"] = false;
        }

        var versions = new JsonObject();
        for (var v = 1; v <= key.Latest; v++)
        {
            versions[v.ToString(CultureInfo.InvariantCulture)] = key.Type == "ecdsa-p256"
                ? new JsonObject
                {
                    ["name"] = "P-256",
                    ["public_key"] = key.Version(v).Ec!.ExportSubjectPublicKeyInfoPem() + "\n",
                    ["creation_time"] = "2026-11-20T00:00:00Z",
                }
                : 1763600000;
        }

        if (key.Type != "hmac")
        {
            data["keys"] = versions;
        }

        return Json(context, 200, new JsonObject { ["data"] = data });
    }

    private Task CreateKeyRequest(HttpContext context, string name, JsonObject body)
    {
        if (!keys.ContainsKey(name))
        {
            CreateKey(name, (string?)body["type"] ?? "aes256-gcm96", (bool?)body["exportable"] ?? false, (bool?)body["allow_plaintext_backup"] ?? false);
        }

        context.Response.StatusCode = 204;
        return Task.CompletedTask;
    }

    private Task Import(HttpContext context, string name, JsonObject body)
    {
        if (keys.ContainsKey(name))
        {
            throw new StubError(500, "the import path cannot be used with an existing key; use import-version to rotate an existing imported key");
        }

        var type = (string?)body["type"] ?? throw new StubError(400, "missing type");
        if ((string?)body["hash_function"] is not "SHA256")
        {
            throw new StubError(400, "this stub only implements SHA256");
        }

        var ciphertext = Convert.FromBase64String((string?)body["ciphertext"] ?? string.Empty);
        if (ciphertext.Length <= 512)
        {
            throw new StubError(500, "provided ciphertext is too short");
        }

        var ephemeral = SharedWrappingKey.Value.Decrypt(ciphertext.AsSpan(0, 512), RSAEncryptionPadding.OaepSHA256);
        if (ephemeral.Length != 32)
        {
            throw new StubError(500, "expected ephemeral AES key to be 256-bit");
        }

        using var aes = Aes.Create();
        aes.Key = ephemeral;
        var material = aes.DecryptKeyWrapPadded(ciphertext.AsSpan(512));
        if ((type == "aes256-gcm96" && material.Length != 32) || (type == "hmac" && material.Length is < 32 or > 512) || type is not ("aes256-gcm96" or "hmac"))
        {
            throw new StubError(500, $"invalid key size {material.Length} bytes for key type {type}");
        }

        var key = new StubKey(name, type)
        {
            Imported = true,
            Exportable = (bool?)body["exportable"] ?? false,
            AllowPlaintextBackup = (bool?)body["allow_plaintext_backup"] ?? false,
        };
        key.AddVersion(null, material);
        keys[name] = key;
        context.Response.StatusCode = 204;
        return Task.CompletedTask;
    }

    private Task Sign(HttpContext context, string name, JsonObject body)
    {
        var key = Key(name, "encryption key not found");
        if (key.Type != "ecdsa-p256")
        {
            throw new StubError(400, $"key type {key.Type} does not support signing");
        }

        var version = KeyVersion(key, body);
        var input = Convert.FromBase64String((string?)body["input"] ?? string.Empty);
        var prehashed = (bool?)body["prehashed"] ?? false;
        var digest = prehashed ? input : SHA256.HashData(input);
        var jws = (string?)body["marshaling_algorithm"] == "jws";
        var ec = key.Version(version).Ec!;
        var signature = jws
            ? Base64Url.EncodeToString(ec.SignHash(digest, DSASignatureFormat.IeeeP1363FixedFieldConcatenation))
            : Convert.ToBase64String(ec.SignHash(digest, DSASignatureFormat.Rfc3279DerSequence));
        return Json(context, 200, new JsonObject { ["data"] = new JsonObject { ["signature"] = $"vault:v{version}:{signature}", ["key_version"] = version } });
    }

    private Task Hmac(HttpContext context, string name, JsonObject body)
    {
        var key = Key(name, "encryption key not found");
        var version = KeyVersion(key, body);
        var entry = key.Version(version);
        var mac = HMACSHA256.HashData(key.Type == "hmac" ? entry.Material : entry.HmacKey, Convert.FromBase64String((string?)body["input"] ?? string.Empty));
        return Json(context, 200, new JsonObject { ["data"] = new JsonObject { ["hmac"] = $"vault:v{version}:{Convert.ToBase64String(mac)}" } });
    }

    private Task DataKey(HttpContext context, string name, JsonObject body)
    {
        var key = Key(name, "encryption key not found");
        if (key.Type != "aes256-gcm96")
        {
            throw new StubError(400, "key type does not support data keys");
        }

        var bits = (int?)body["bits"] ?? 256;
        var plaintext = RandomNumberGenerator.GetBytes(bits / 8);
        var ciphertext = Seal(key.Version(key.Latest).Material, plaintext, []);
        return Json(context, 200, new JsonObject
        {
            ["data"] = new JsonObject
            {
                ["plaintext"] = Convert.ToBase64String(plaintext),
                ["ciphertext"] = $"vault:v{key.Latest}:{Convert.ToBase64String(ciphertext)}",
                ["key_version"] = key.Latest,
            },
        });
    }

    private Task Decrypt(HttpContext context, string name, JsonObject body)
    {
        var key = Key(name, "encryption key not found");
        var value = (string?)body["ciphertext"] ?? string.Empty;
        if (!value.StartsWith("vault:v", StringComparison.Ordinal))
        {
            throw new StubError(400, "invalid ciphertext: no prefix");
        }

        var parts = value["vault:v".Length..].Split(':', 2);
        if (parts.Length != 2)
        {
            throw new StubError(400, "invalid ciphertext: wrong number of fields");
        }

        if (!int.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out var version))
        {
            throw new StubError(400, "invalid ciphertext: version number could not be decoded");
        }

        if (version > key.Latest)
        {
            throw new StubError(400, "invalid ciphertext: version is too new");
        }

        byte[] decoded;
        try
        {
            decoded = Convert.FromBase64String(parts[1]);
        }
        catch (FormatException)
        {
            throw new StubError(400, "invalid ciphertext: could not decode base64");
        }

        var aad = (string?)body["associated_data"] is { Length: > 0 } a ? Convert.FromBase64String(a) : [];
        if (decoded.Length < 12 + 16)
        {
            throw new StubError(400, "invalid ciphertext length");
        }

        var plain = new byte[decoded.Length - 28];
        try
        {
            using var gcm = new AesGcm(key.Version(Math.Max(version, 1)).Material, 16);
            gcm.Decrypt(decoded.AsSpan(0, 12), decoded.AsSpan(12, plain.Length), decoded.AsSpan(12 + plain.Length), plain, aad);
        }
        catch (AuthenticationTagMismatchException)
        {
            throw new StubError(400, "cipher: message authentication failed");
        }

        return Json(context, 200, new JsonObject { ["data"] = new JsonObject { ["plaintext"] = Convert.ToBase64String(plain) } });
    }

    private static byte[] Seal(byte[] key, byte[] plaintext, byte[] aad)
    {
        var output = new byte[12 + plaintext.Length + 16];
        RandomNumberGenerator.Fill(output.AsSpan(0, 12));
        using var gcm = new AesGcm(key, 16);
        gcm.Encrypt(output.AsSpan(0, 12), plaintext, output.AsSpan(12, plaintext.Length), output.AsSpan(12 + plaintext.Length), aad);
        return output;
    }

    private StubKey Key(string name, string missing) =>
        keys.TryGetValue(name, out var key) ? key : throw new StubError(400, missing);

    private static int KeyVersion(StubKey key, JsonObject body)
    {
        var version = (int?)body["key_version"] ?? 0;
        if (version == 0)
        {
            return key.Latest;
        }

        return version <= key.Latest ? version : throw new StubError(400, $"key version does not exist; latest key version is {key.Latest}");
    }

    private static Task Error(HttpContext context, int status, params string[] errors) =>
        Json(context, status, new JsonObject { ["errors"] = new JsonArray([.. errors.Select(e => (JsonNode)e!)]) });

    private static async Task Json(HttpContext context, int status, JsonObject body)
    {
        context.Response.StatusCode = status;
        context.Response.ContentType = "application/json";
        await context.Response.WriteAsync(body.ToJsonString());
    }

    [GeneratedRegex("path\\s+\"([^\"]+)\"\\s*\\{\\s*capabilities\\s*=\\s*\\[([^\\]]*)\\]\\s*\\}", RegexOptions.CultureInvariant)]
    private static partial Regex PolicyStanza();

    private sealed class StubError(int status, string message) : Exception(message)
    {
        public int Status { get; } = status;
    }

    private sealed class StubKey(string name, string type)
    {
        private readonly List<(ECDsa? Ec, byte[] Material, byte[] HmacKey)> versions = [];

        public string Name { get; } = name;

        public string Type { get; } = type;

        public bool Exportable { get; init; }

        public bool AllowPlaintextBackup { get; init; }

        public bool DeletionAllowed { get; init; }

        public bool Imported { get; init; }

        public int Latest => versions.Count;

        public (ECDsa? Ec, byte[] Material, byte[] HmacKey) Version(int version) => versions[version - 1];

        public void AddVersion(ECDsa? ec, byte[] material) =>
            versions.Add((ec, material, Type == "hmac" ? material : RandomNumberGenerator.GetBytes(32)));
    }
}

/// <summary>A throwaway CA (ECDSA P-256) and the server certificates it issues for 127.0.0.1.</summary>
internal sealed class TestCa : IDisposable
{
    private readonly ECDsa key = ECDsa.Create(ECCurve.NamedCurves.nistP256);

    public TestCa(string name)
    {
        var request = new CertificateRequest("CN=" + name, key, HashAlgorithmName.SHA256);
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(true, false, 0, true));
        request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.KeyCertSign | X509KeyUsageFlags.CrlSign, true));
        request.CertificateExtensions.Add(new X509SubjectKeyIdentifierExtension(request.PublicKey, false));
        Certificate = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-5), DateTimeOffset.UtcNow.AddDays(1));
    }

    public X509Certificate2 Certificate { get; }

    public string Pem => Certificate.ExportCertificatePem() + "\n";

    public X509Certificate2 IssueServerCertificate()
    {
        using var leafKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var request = new CertificateRequest("CN=openbao", leafKey, HashAlgorithmName.SHA256);
        var names = new SubjectAlternativeNameBuilder();
        names.AddIpAddress(IPAddress.Loopback);
        names.AddDnsName("localhost");
        request.CertificateExtensions.Add(names.Build());
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
        request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension([new Oid("1.3.6.1.5.5.7.3.1")], false));
        request.CertificateExtensions.Add(X509AuthorityKeyIdentifierExtension.CreateFromCertificate(Certificate, true, false));
        var serial = RandomNumberGenerator.GetBytes(16);
        serial[0] &= 0x7F;
        using var issued = request.Create(Certificate, DateTimeOffset.UtcNow.AddMinutes(-5), DateTimeOffset.UtcNow.AddDays(1), serial);
        using var withKey = issued.CopyWithPrivateKey(leafKey);
        return X509CertificateLoader.LoadPkcs12(withKey.Export(X509ContentType.Pfx), null);
    }

    public void Dispose()
    {
        Certificate.Dispose();
        key.Dispose();
    }
}
