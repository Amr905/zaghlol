using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// Checks the shared vectors for the iOS seat-key proof (D-55; backend-api.md section 4.3, ADR-012 Part B (g)):
/// <c>message = "zaghlol-seat-v1" || 0x00 || op || 0x00 || installId || 0x00 || challenge</c>, signed with ECDSA P-256 /
/// SHA-256 in IEEE P1363 form. The app (Secure Enclave key) and the API verifier must agree on these bytes.
/// </summary>
public class SeatProofVectorTests
{
    private static readonly JsonObject Vectors = LoadVectors();

    [Fact]
    public void ValidVectorsBuildTheDocumentedMessageAndVerify()
    {
        var valid = Vectors["valid"]!.AsArray();
        Assert.Equal(3, valid.Count);

        foreach (var vector in valid)
        {
            var name = vector!["name"]!.GetValue<string>();
            var message = Message(vector);
            Assert.Equal(vector["messageHex"]!.GetValue<string>(), Convert.ToHexStringLower(message));
            Assert.True(Verifies(vector, message), $"{name}: signature does not verify");
        }
    }

    [Fact]
    public void InvalidVectorsDoNotVerify()
    {
        var invalid = Vectors["invalid"]!.AsArray();
        Assert.NotEmpty(invalid);

        foreach (var vector in invalid)
        {
            Assert.False(Verifies(vector!, Message(vector!)), $"{vector!["name"]!.GetValue<string>()}: verified");
        }
    }

    [Fact]
    public void PublicKeysAreUncompressedP256Points()
    {
        foreach (var vector in Vectors["valid"]!.AsArray())
        {
            var key = Base64Url.DecodeFromChars(vector!["publicKey"]!.GetValue<string>());
            Assert.Equal(65, key.Length);
            Assert.Equal(0x04, key[0]);
            Assert.Equal(64, Base64Url.DecodeFromChars(vector["signature"]!.GetValue<string>()).Length);
        }
    }

    private static byte[] Message(JsonNode vector)
    {
        var prefix = Vectors["prefix"]!.GetValue<string>();
        var op = vector["op"]!.GetValue<string>();
        var installId = vector["installId"]!.GetValue<string>();
        var challenge = Convert.FromHexString(vector["challengeHex"]!.GetValue<string>());
        Assert.Equal(32, challenge.Length);
        return [.. Encoding.ASCII.GetBytes(prefix), 0, .. Encoding.ASCII.GetBytes(op), 0, .. Encoding.ASCII.GetBytes(installId), 0, .. challenge];
    }

    private static bool Verifies(JsonNode vector, byte[] message)
    {
        var point = Base64Url.DecodeFromChars(vector["publicKey"]!.GetValue<string>());
        var signature = Base64Url.DecodeFromChars(vector["signature"]!.GetValue<string>());
        using var key = ECDsa.Create(new ECParameters
        {
            Curve = ECCurve.NamedCurves.nistP256,
            Q = new ECPoint { X = point[1..33], Y = point[33..65] },
        });
        return key.VerifyData(message, signature, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
    }

    private static JsonObject LoadVectors()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "vectors", "seat-proof-v1.json");
        return JsonNode.Parse(File.ReadAllText(path))!.AsObject();
    }
}
