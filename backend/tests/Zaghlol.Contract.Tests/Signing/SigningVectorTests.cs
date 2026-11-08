using System.Buffers.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Contract.Tests.Signing;

/// <summary>
/// T-123 shared vectors (app ↔ backend): <c>response-signature-v1.json</c>, <c>jws-es256-v1.json</c> and
/// <c>keyed-hash-v1.json</c>, plus the OpenAPI header and nonce patterns.
/// </summary>
public class SigningVectorTests
{
    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private static readonly string[] ExpectedKids = ["e0000t", "s0000t"];

    private static readonly string[] ExpectedJwkMembers = ["alg", "crv", "kid", "kty", "use", "x", "y"];

    [Fact]
    public void CommittedResponseVectorsVerifyExactlyAsLabelled()
    {
        var vectors = Load(SigningVectors.ResponseFile);
        AssertResponseVectors(vectors);
    }

    [Fact]
    public void CommittedJwsVectorsVerifyExactlyAsLabelled()
    {
        var vectors = Load(SigningVectors.JwsFile);
        AssertJwsVectors(vectors);
    }

    [Fact]
    public void CommittedVectorsHoldPublicKeysOnly()
    {
        foreach (var file in new[] { SigningVectors.ResponseFile, SigningVectors.JwsFile })
        {
            var keys = Load(file)["jwks"]!["keys"]!.AsArray();
            Assert.Equal(ExpectedKids, keys.Select(k => k!["kid"]!.GetValue<string>()).Order(StringComparer.Ordinal));
            Assert.All(keys, k => Assert.Equal(ExpectedJwkMembers, k!.AsObject().Select(p => p.Key).Order(StringComparer.Ordinal)));
        }
    }

    [Fact]
    public async Task FreshlyGeneratedVectorsVerifyAndCanBeWrittenOnRequest()
    {
        // The generator self-check: fresh FakeKms signatures round-trip against the published keys every run.
        var (response, jws) = await SigningVectors.GenerateAsync();
        AssertResponseVectors(response);
        AssertJwsVectors(jws);

        if (Environment.GetEnvironmentVariable("ZAGHLOL_GEN_VECTORS") == "1")
        {
            var directory = SourceVectorDirectory();
            await File.WriteAllTextAsync(Path.Combine(directory, SigningVectors.ResponseFile), SigningVectors.Serialize(response));
            await File.WriteAllTextAsync(Path.Combine(directory, SigningVectors.JwsFile), SigningVectors.Serialize(jws));
        }
    }

    [Fact]
    public async Task KeyedHashVectorsMatchThroughIKeyedHasher()
    {
        var cases = Load("keyed-hash-v1.json")["cases"]!.AsArray();
        Assert.Equal(4, cases.Count);

        foreach (var vector in cases)
        {
            using var kms = FakeKms.CreateDefault();
            kms.AddSecret(FakeKms.HmacKeyRef(KeyedHashKey.Audit), Convert.FromHexString(vector!["keyHex"]!.GetValue<string>()));
            await using var services = kms.BuildServices();
            var hasher = services.GetRequiredService<IKeyedHasher>();

            var mac = await hasher.HmacSha256Async(KeyedHashKey.Audit, Convert.FromHexString(vector["dataHex"]!.GetValue<string>()), CancellationToken.None);

            Assert.Equal(vector["hmacSha256Hex"]!.GetValue<string>(), Convert.ToHexStringLower(mac));
        }
    }

    [Fact]
    public void TheOpenApiSignatureHeaderPatternIsTheExactGrammar()
    {
        var pattern = Spec.Root["components"]!["headers"]!["ZaghlolSignature"]!["schema"]!["pattern"]!.GetValue<string>();
        Assert.Equal("^kid=[se][0-9]{4}[a-z]; alg=ES256; sig=[A-Za-z0-9_-]{86}$", pattern);

        var vectors = Load(SigningVectors.ResponseFile);
        foreach (var vector in vectors["valid"]!.AsArray())
        {
            Assert.Matches(pattern, vector!["header"]!.GetValue<string>());
        }

        foreach (var name in new[] { "der-signature", "alg-es384", "padded-signature", "reordered-params", "extra-spaces" })
        {
            var header = vectors["invalid"]!.AsArray().Single(v => v!["name"]!.GetValue<string>() == name)!["header"]!.GetValue<string>();
            Assert.DoesNotMatch(new Regex(pattern + "\\z"), header);
        }
    }

    [Fact]
    public void TheOpenApiTimeNoncePatternMatchesTheFilter()
    {
        Assert.Equal("^[A-Za-z0-9_-]{21}[AQgw]$", Spec.Schemas["TimeNonce"]!["pattern"]!.GetValue<string>());
        Assert.Equal(TimeNonceHeader, Spec.Root["components"]!["parameters"]!["ZaghlolTimeNonce"]!["name"]!.GetValue<string>());
        Assert.Equal(TimeNonceHeader, Zaghlol.Api.Signing.TimeNonceFilter.HeaderName);
    }

    private const string TimeNonceHeader = "Zaghlol-Time-Nonce";

    private static void AssertResponseVectors(JsonObject vectors)
    {
        var jwks = vectors["jwks"]!;
        var valid = vectors["valid"]!.AsArray();
        var invalid = vectors["invalid"]!.AsArray();
        Assert.Equal(4, valid.Count);
        Assert.Equal(9, invalid.Count);

        foreach (var vector in valid)
        {
            Assert.True(ReferenceVerifiers.VerifyResponse(jwks, Body(vector!), vector!["header"]!.GetValue<string>()), Name(vector));
        }

        foreach (var vector in invalid)
        {
            Assert.False(ReferenceVerifiers.VerifyResponse(jwks, Body(vector!), vector!["header"]!.GetValue<string>()), Name(vector));
        }

        var highS = valid.Single(v => Name(v) == "high-s")!["header"]!.GetValue<string>();
        Assert.True(P256.IsHighS(Base64Url.DecodeFromChars(highS[(highS.IndexOf("sig=", StringComparison.Ordinal) + 4)..])));
        Assert.Contains(valid, v => Body(v!).Length == 2);
    }

    private static void AssertJwsVectors(JsonObject vectors)
    {
        var jwks = vectors["jwks"]!;
        var valid = vectors["valid"]!.AsArray();
        var invalid = vectors["invalid"]!.AsArray();
        Assert.Equal(2, valid.Count);
        Assert.Equal(7, invalid.Count);

        foreach (var vector in valid)
        {
            Assert.True(ReferenceVerifiers.VerifyJws(jwks, vector!["token"]!.GetValue<string>()), Name(vector));
        }

        foreach (var vector in invalid)
        {
            Assert.False(ReferenceVerifiers.VerifyJws(jwks, vector!["token"]!.GetValue<string>()), Name(vector));
        }
    }

    private static byte[] Body(JsonNode vector) => Base64Url.DecodeFromChars(vector["bodyB64u"]!.GetValue<string>());

    private static string Name(JsonNode? vector) => vector!["name"]!.GetValue<string>();

    private static JsonObject Load(string file) =>
        JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "vectors", file)))!.AsObject();

    private static string SourceVectorDirectory()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            if (File.Exists(Path.Combine(directory.FullName, "Zaghlol.Contract.Tests.csproj")))
            {
                return Path.Combine(directory.FullName, "vectors");
            }
        }

        throw new InvalidOperationException("The Zaghlol.Contract.Tests project directory was not found.");
    }
}
