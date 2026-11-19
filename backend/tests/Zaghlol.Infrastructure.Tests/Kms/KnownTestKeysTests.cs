using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>
/// T-200 design note §4: the File KMS denylist covers every key committed to the repository. A new committed key (a JWK
/// private scalar anywhere in the source tree, a public JWK in the shared vectors, a 32-byte <c>keyHex</c>) fails this test
/// until its fingerprint is added to <c>KnownTestKeys</c>.
/// </summary>
public partial class KnownTestKeysTests
{
    private static readonly string Committed = Path.Combine(AppContext.BaseDirectory, "committed-keys");

    private static readonly string[] ScannedExtensions = [".json", ".dart", ".cs", ".py", ".sh", ".txt", ".yaml", ".yml", ".env", ".pem", ".key", ".jwk"];

    private static readonly string[] SkippedDirectories = [".git", "bin", "obj", "build", ".dart_tool", "node_modules", "Pods", ".gradle", ".dev-keys"];

    /// <summary>The committed catalog dev seed key (kid s0000a), rebuilt from its private scalar.</summary>
    public static ECDsa CatalogDevKey()
    {
        using var json = JsonDocument.Parse(File.ReadAllText(Path.Combine(Committed, "catalog_build", "dev_signing_key.json")));
        return FromScalar(json.RootElement.GetProperty("d").GetString()!);
    }

    [Fact]
    public void EveryLinkedCommittedSigningKeyIsDenied()
    {
        var fingerprints = Scalars(Directory.EnumerateFiles(Committed, "*", SearchOption.AllDirectories)).ToList();

        Assert.NotEmpty(fingerprints);
        Assert.All(fingerprints, f => Assert.Contains(f.Fingerprint, KnownTestKeys.SigningKeys));
    }

    [Fact]
    public void EveryPrivateScalarInTheSourceTreeIsDenied()
    {
        var root = RepositoryRoot();
        var files = Walk(root).ToList();
        Assert.True(files.Count > 100, "the repository walk found too few files");

        var found = Scalars(files).ToList();

        Assert.Contains(found, f => f.File.EndsWith("dev_signing_key.json", StringComparison.Ordinal));
        var missing = found.Where(f => !KnownTestKeys.SigningKeys.Contains(f.Fingerprint)).Select(f => Path.GetRelativePath(root, f.File)).ToList();
        Assert.True(missing.Count == 0, "committed EC private keys missing from KnownTestKeys: " + string.Join(", ", missing));
    }

    [Fact]
    public void EveryPublicJwkInTheSharedVectorsIsDenied()
    {
        var count = 0;
        foreach (var file in Directory.EnumerateFiles(Path.Combine(Committed, "vectors"), "*.json"))
        {
            foreach (Match match in JwkPattern().Matches(File.ReadAllText(file)))
            {
                var point = (byte[])[0x04, .. Base64Url.DecodeFromChars(match.Groups["x"].Value), .. Base64Url.DecodeFromChars(match.Groups["y"].Value)];
                using var key = ECDsa.Create(new ECParameters
                {
                    Curve = ECCurve.NamedCurves.nistP256,
                    Q = new ECPoint { X = point[1..33], Y = point[33..] },
                });
                Assert.Contains(KeyFingerprints.OfSigningKey(key), KnownTestKeys.SigningKeys);
                count++;
            }
        }

        Assert.True(count >= 4, "expected the catalog, JWS and response vector keys");
    }

    [Fact]
    public void EveryCommitted32ByteKeyIsDenied()
    {
        var keys = new List<byte[]> { FakeKms.FixedSeatKey };
        foreach (var file in Directory.EnumerateFiles(Path.Combine(Committed, "vectors"), "*.json"))
        {
            foreach (Match match in KeyHexPattern().Matches(File.ReadAllText(file)))
            {
                keys.Add(Convert.FromHexString(match.Groups["hex"].Value));
            }
        }

        Assert.True(keys.Count >= 2);
        Assert.All(keys, k => Assert.Contains(KeyFingerprints.OfSecret(k), KnownTestKeys.Secrets));
    }

    [Theory]
    [InlineData(0, true)]
    [InlineData(1, true)]
    [InlineData(15, true)]
    [InlineData(16, false)]
    [InlineData(32, false)]
    public void DegenerateMeansFewerThan16DistinctBytes(int distinct, bool degenerate)
    {
        var secret = Enumerable.Range(0, 32).Select(i => (byte)(distinct == 0 ? 0 : i % distinct)).ToArray();

        Assert.Equal(degenerate, KnownTestKeys.IsDegenerate(secret));
    }

    [Fact]
    public void RandomKeysAreNotDegenerate()
    {
        for (var i = 0; i < 10_000; i++)
        {
            Assert.False(KnownTestKeys.IsDegenerate(RandomNumberGenerator.GetBytes(32)));
        }
    }

    private static IEnumerable<(string File, string Fingerprint)> Scalars(IEnumerable<string> files)
    {
        foreach (var file in files)
        {
            string text;
            try
            {
                text = File.ReadAllText(file);
            }
            catch (IOException)
            {
                continue;
            }

            foreach (Match match in ScalarPattern().Matches(text))
            {
                using var key = FromScalar(match.Groups["d"].Value);
                yield return (file, KeyFingerprints.OfSigningKey(key));
            }
        }
    }

    private static ECDsa FromScalar(string d)
    {
        var key = ECDsa.Create();
        key.ImportParameters(new ECParameters { Curve = ECCurve.NamedCurves.nistP256, D = Base64Url.DecodeFromChars(d) });
        return key;
    }

    private static string RepositoryRoot()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            if (File.Exists(Path.Combine(dir.FullName, "CLAUDE.md")) && Directory.Exists(Path.Combine(dir.FullName, "backend")))
            {
                return dir.FullName;
            }
        }

        throw new InvalidOperationException("the repository root (CLAUDE.md next to backend/) was not found above the test binaries");
    }

    private static IEnumerable<string> Walk(string root)
    {
        var pending = new Stack<string>([root]);
        while (pending.TryPop(out var dir))
        {
            foreach (var sub in Directory.EnumerateDirectories(dir))
            {
                if (!SkippedDirectories.Contains(Path.GetFileName(sub), StringComparer.Ordinal) && !new DirectoryInfo(sub).Attributes.HasFlag(FileAttributes.ReparsePoint))
                {
                    pending.Push(sub);
                }
            }

            foreach (var file in Directory.EnumerateFiles(dir))
            {
                if (ScannedExtensions.Contains(Path.GetExtension(file), StringComparer.OrdinalIgnoreCase) && new FileInfo(file).Length < 4_000_000)
                {
                    yield return file;
                }
            }
        }
    }

    [GeneratedRegex("\"d\"\\s*:\\s*\"(?<d>[A-Za-z0-9_-]{43})\"", RegexOptions.CultureInvariant)]
    private static partial Regex ScalarPattern();

    [GeneratedRegex("\"x\"\\s*:\\s*\"(?<x>[A-Za-z0-9_-]{43})\"\\s*,\\s*\"y\"\\s*:\\s*\"(?<y>[A-Za-z0-9_-]{43})\"", RegexOptions.CultureInvariant)]
    private static partial Regex JwkPattern();

    [GeneratedRegex("\"keyHex\"\\s*:\\s*\"(?<hex>[0-9a-f]{64})\"", RegexOptions.CultureInvariant)]
    private static partial Regex KeyHexPattern();
}
