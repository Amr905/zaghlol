using System.Text.Json.Nodes;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// The shared vectors for the iOS seat-key proof (D-55; backend-api.md section 4.3, ADR-012 Part B (g)) run through the
/// production verifier (T-182): <see cref="SeatKeyProofVerifier.ParseAndVerify"/> and the production message builder. The app
/// (Secure Enclave key, T-183) and the API must agree on these bytes.
/// </summary>
public class SeatProofVectorTests
{
    private const string SignedTransaction = "eyJhbGciOiJFUzI1NiJ9.eyJzeW50aGV0aWMiOnRydWV9.c2ln";

    private static readonly JsonObject Vectors = Load("seat-proof-v1.json");
    private static readonly JsonObject Binding = Load("restore-binding-v1.json");

    [Fact]
    public void ValidVectorsBuildTheDocumentedMessageAndVerifyThroughTheProductionVerifier()
    {
        var valid = Vectors["valid"]!.AsArray();
        Assert.Equal(4, valid.Count);
        Assert.Equal("zaghlol-seat-v1", Vectors["prefix"]!.GetValue<string>());
        Assert.Equal(SeatKeyProofVerifier.MessagePrefix, Vectors["prefix"]!.GetValue<string>());

        foreach (var vector in valid)
        {
            var name = vector!["name"]!.GetValue<string>();
            var challenge = Challenge(vector);
            var message = SeatKeyProofVerifier.Message(challenge.Op, InstallId.Parse(Text(vector, "installId")), challenge.ToArray());
            Assert.Equal(Text(vector, "messageHex"), Convert.ToHexStringLower(message));

            var result = Verifier().ParseAndVerify([Proof(vector)], challenge, InstallId.Parse(Text(vector, "installId")));
            Assert.True(result.IsValid, $"{name}: {result}");
            Assert.Equal(1, result.Keys.Count);
        }
    }

    [Fact]
    public void TheVerifyChallengeIsTheShaOfTheSignedTransactionAndTheRestoreChallengeIsTheBodyHash()
    {
        var verify = Vectors["valid"]!.AsArray().Single(v => Text(v!, "name") == "verify")!;
        Assert.Equal(Text(verify, "challengeHex"), Convert.ToHexStringLower(SeatChallenge.ForVerify(SignedTransaction).ToArray()));

        var restore = Vectors["valid"]!.AsArray().Single(v => Text(v!, "name") == "restore")!;
        var bodyHash = Binding["valid"]!.AsArray().Single(v => Text(v!, "name") == "ios-member-order")!;
        Assert.Equal(Text(bodyHash, "bodyHashHex"), Text(restore, "challengeHex"));
    }

    [Fact]
    public void HighAndLowSFormsOfTheSameSignatureBothVerify()
    {
        var valid = Vectors["valid"]!.AsArray();
        var high = valid.Single(v => Text(v!, "name") == "restore")!;
        var low = valid.Single(v => Text(v!, "name") == "restore-low-s")!;

        Assert.Equal(Text(high, "signature")[..42], Text(low, "signature")[..42]);
        Assert.NotEqual(Text(high, "signature"), Text(low, "signature"));
    }

    [Fact]
    public void InvalidVectorsAreRejectedAsBadSignatures()
    {
        var invalid = Vectors["invalid"]!.AsArray();
        Assert.Equal(["other-install", "other-op", "flipped-signature-bit", "other-challenge"], invalid.Select(v => Text(v!, "name")));

        foreach (var vector in invalid)
        {
            var result = Verifier().ParseAndVerify([Proof(vector!)], Challenge(vector!), InstallId.Parse(Text(vector!, "installId")));
            Assert.False(result.IsValid, $"{Text(vector!, "name")}: verified");
            Assert.Equal(SeatKeyRejection.BadSignature, result.Rejection);
        }
    }

    [Fact]
    public void MalformedSetsAreRejectedWithTheirReason()
    {
        var malformed = Vectors["malformed"]!.AsArray();
        Assert.True(malformed.Count >= 20, "expected the design note's malformed set");
        string[] required =
        [
            "empty", "verify-two-keys", "restore-six-keys", "duplicate-key", "padded-public-key", "whitespace-in-public-key",
            "non-canonical-last-character", "compressed-33-byte-key", "truncated-64-byte-key", "hybrid-prefix-0x06",
            "y-plus-one-off-curve", "all-zero-point", "der-signature", "r-zero", "s-zero", "r-equals-n",
            "generator-with-restore-signature",
        ];
        Assert.Empty(required.Except(malformed.Select(v => Text(v!, "name")), StringComparer.Ordinal));

        foreach (var vector in malformed)
        {
            var name = Text(vector!, "name");
            var inputs = vector!["seatKeys"]!.AsArray()
                .Select(k => (SeatKeyProofInput?)new SeatKeyProofInput(Text(k!, "publicKey"), Text(k!, "signature")))
                .ToList();
            var result = Verifier().ParseAndVerify(inputs, Challenge(vector), InstallId.Parse(Text(vector, "installId")));

            Assert.False(result.IsValid, $"{name}: verified");
            Assert.True(Text(vector, "expect") == SeatKeyTags.Result(result.Rejection), $"{name}: {result} instead of {Text(vector, "expect")}");
        }
    }

    /// <summary>T-185's <c>seatKeysDigest</c>: the production digest reproduces every iOS restore-binding vector.</summary>
    [Fact]
    public void DigestOfPublicKeysReproducesTheRestoreBindingVectors()
    {
        var ios = Binding["valid"]!.AsArray().Where(v => v!["body"]!["platform"]!.GetValue<string>() == "ios").ToList();
        Assert.Equal(3, ios.Count);

        foreach (var vector in ios)
        {
            var keys = vector!["body"]!["attestation"]!["seatKeys"]?.AsArray();
            byte[] digest;
            if (keys is null)
            {
                digest = SeatKeysDigest.Empty;
            }
            else
            {
                var parsed = Verifier().Parse(SeatOp.Restore, [.. keys.Select(k => (SeatKeyProofInput?)new SeatKeyProofInput(Text(k!, "publicKey"), Text(k!, "signature")))]);
                Assert.True(parsed.IsValid, $"{Text(vector, "name")}: {parsed}");
                digest = parsed.Keys.Digest();
            }

            Assert.Equal(Text(vector, "seatKeysDigestHex"), Convert.ToHexStringLower(digest));
        }
    }

    /// <summary>The two-key restore vector: both elements verify over the same install-bound bodyHash (positions 0 and 1).</summary>
    [Fact]
    public void TheTwoKeyRestoreBindingVectorVerifiesAsAWholeSet()
    {
        var vector = Binding["valid"]!.AsArray().Single(v => Text(v!, "name") == "ios-two-seat-keys")!;
        var keys = vector["body"]!["attestation"]!["seatKeys"]!.AsArray()
            .Select(k => (SeatKeyProofInput?)new SeatKeyProofInput(Text(k!, "publicKey"), Text(k!, "signature")))
            .ToList();
        var challenge = SeatChallenge.ForRestore(Convert.FromHexString(Text(vector, "bodyHashHex")));

        var result = Verifier().ParseAndVerify(keys, challenge, InstallId.Parse(Text(vector, "installId")));

        Assert.True(result.IsValid, result.ToString());
        Assert.Equal(2, result.Keys.Count);
        Assert.Equal(1, Assert.Single(result.Keys.Others).Position);
        Assert.Equal(Text(vector, "seatKeysDigestHex"), Convert.ToHexStringLower(result.Keys.Digest()));
    }

    internal static SeatKeyProofVerifier Verifier() => new(new NoMetrics());

    private static SeatChallenge Challenge(JsonNode vector)
    {
        var op = Text(vector, "op") switch
        {
            "verify" => SeatOp.Verify,
            "restore" => SeatOp.Restore,
            "signin" => SeatOp.SignIn,
            var other => throw new InvalidOperationException("unknown op " + other),
        };
        var bytes = Convert.FromHexString(Text(vector, "challengeHex"));
        return op == SeatOp.Restore ? SeatChallenge.ForRestore(bytes) : SeatChallenge.FromRaw(op, bytes);
    }

    private static SeatKeyProofInput Proof(JsonNode vector) => new(Text(vector, "publicKey"), Text(vector, "signature"));

    private static string Text(JsonNode node, string name) => node[name]!.GetValue<string>();

    private static JsonObject Load(string file) =>
        JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "vectors", file)))!.AsObject();

    private sealed class NoMetrics : ISeatKeyMetrics
    {
        public void Proof(SeatOp op, SeatKeyRejection? rejection)
        {
        }

        public void ElementZero(SeatOp op, ElementZeroStatus status)
        {
        }
    }
}
