using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Zaghlol.Application.Purchases.Restore;
using Zaghlol.Domain;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// T-185: the production restore parser reproduces the shared vectors (<c>restore-binding-v1.json</c>) and rejects the invalid ones
/// (R3-8). The vectors' attestation values are placeholders ("ignored"); the hash excludes <c>attestation</c>, so the tests swap in
/// well-formed values, which must not change the hash.
/// </summary>
public class RestoreParserVectorTests
{
    private static readonly JsonObject Vectors = JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "vectors", "restore-binding-v1.json")))!.AsObject();

    private static readonly string KeyId = Convert.ToBase64String(SHA256.HashData("k"u8));

    private static readonly string Assertion = Convert.ToBase64String(new byte[48]);

    [Fact]
    public void ValidVectorsGiveTheVectorBodyHashAndClientDataHash()
    {
        foreach (var vector in Vectors["valid"]!.AsArray())
        {
            var name = vector!["name"]!.GetValue<string>();
            var body = JsonNode.Parse(vector["body"]!.ToJsonString())!.AsObject();
            var attestation = body["attestation"]!.AsObject();
            if (body["platform"]!.GetValue<string>() == "ios")
            {
                attestation["keyId"] = KeyId;
                attestation["assertion"] = Assertion;
            }

            var installId = InstallId.Parse(vector["installId"]!.GetValue<string>());
            var parsed = RestoreRequestParser.Parse(Encoding.UTF8.GetBytes(body.ToJsonString()), installId);

            Assert.True(parsed.Request is not null, $"{name}: {parsed}");
            Assert.Equal(vector["bodyHashHex"]!.GetValue<string>(), Convert.ToHexStringLower(parsed.Request.BodyHash));
            if (parsed.Request is IosRestoreRequest ios)
            {
                var digest = Convert.FromHexString(vector["seatKeysDigestHex"]!.GetValue<string>());
                Assert.Equal(
                    vector["clientDataHashHex"]!.GetValue<string>(),
                    Convert.ToHexStringLower(RestoreRequestParser.ClientDataHash(ios.BodyHash, digest)));
            }
        }
    }

    [Fact]
    public void TheSameBodyOnAnotherInstallHasAnotherHash()
    {
        var vector = Vectors["valid"]!.AsArray()[0]!;
        var bytes = Encoding.UTF8.GetBytes(vector["body"]!.ToJsonString());

        var a = RestoreRequestParser.Parse(bytes, InstallId.Parse(vector["installId"]!.GetValue<string>()));
        var b = RestoreRequestParser.Parse(bytes, InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e78"));

        Assert.NotEqual(a.Request!.BodyHash, b.Request!.BodyHash);
    }

    [Fact]
    public void EveryInvalidVectorIsAValidationFailureAndNeverBinds()
    {
        var installId = InstallId.Parse(Vectors["valid"]!.AsArray()[0]!["installId"]!.GetValue<string>());
        foreach (var vector in Vectors["invalid"]!.AsArray())
        {
            var parsed = RestoreRequestParser.Parse(Encoding.UTF8.GetBytes(vector!["raw"]!.GetValue<string>()), installId);

            Assert.Null(parsed.Request);
            Assert.True(parsed.Failure == RestoreParseFailure.ValidationFailed, $"{vector["name"]}: {parsed.Failure}");
        }
    }

    [Theory]
    [InlineData("{\"platform\":\"android\",\"purchases\":[{\"productId\":\"zaghlol_gold_lifetime\",\"purchaseToken\":\"t\"}],\"attestation\":{\"type\":\"play_integrity\",\"token\":\"0123456789abcdef\"},\"extra\":1}")]
    [InlineData("{\"platform\":\"android\",\"purchases\":[{\"productId\":\"zaghlol_gold_lifetime\",\"purchaseToken\":\"t\",\"orderId\":\"x\"}],\"attestation\":{\"type\":\"play_integrity\",\"token\":\"0123456789abcdef\"}}")]
    [InlineData("{\"platform\":\"android\",\"purchases\":[{\"productId\":\"zaghlol_gold_lifetime\",\"purchaseToken\":\"t\"}],\"attestation\":{\"type\":\"play_integrity\",\"token\":\"0123456789abcdef\",\"deviceId\":\"x\"}}")]
    [InlineData("{\"platform\":\"android\",\"signedTransactions\":[\"a\"],\"purchases\":[{\"productId\":\"zaghlol_gold_lifetime\",\"purchaseToken\":\"t\"}],\"attestation\":{\"type\":\"play_integrity\",\"token\":\"0123456789abcdef\"}}")]
    public void AMemberTheSchemaDoesNotDeclareIsUnknownFieldAtAnyDepth(string body)
    {
        var parsed = RestoreRequestParser.Parse(Encoding.UTF8.GetBytes(body), InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77"));

        Assert.Null(parsed.Request);
        Assert.Equal(RestoreParseFailure.UnknownField, parsed.Failure);
    }

    [Theory]
    [InlineData("[]")]
    [InlineData("{\"platform\":\"windows\"}")]
    [InlineData("{\"platform\":\"android\",\"purchases\":[],\"attestation\":{\"type\":\"play_integrity\",\"token\":\"0123456789abcdef\"}}")]
    [InlineData("{\"platform\":\"android\",\"purchases\":[{\"productId\":\"BAD ID\",\"purchaseToken\":\"t\"}],\"attestation\":{\"type\":\"play_integrity\",\"token\":\"0123456789abcdef\"}}")]
    [InlineData("{\"platform\":\"android\",\"purchases\":[{\"productId\":\"zaghlol_gold_lifetime\",\"purchaseToken\":\"t\"}],\"attestation\":{\"type\":\"play_integrity\",\"token\":\"short\"}}")]
    [InlineData("{\"platform\":\"android\",\"purchases\":[{\"productId\":\"zaghlol_gold_lifetime\",\"purchaseToken\":\"t\"}],\"attestation\":{\"type\":\"play_integrity\",\"token\":\"0123456789abcdef\",\"seatKeys\":[]}}")]
    [InlineData("{\"platform\":\"android\",\"purchases\":[{\"productId\":\"zaghlol_gold_lifetime\",\"purchaseToken\":1}],\"attestation\":{\"type\":\"play_integrity\",\"token\":\"0123456789abcdef\"}}")]
    [InlineData("not json")]
    [InlineData("")]
    public void MalformedBodiesAreValidationFailures(string body)
    {
        var parsed = RestoreRequestParser.Parse(Encoding.UTF8.GetBytes(body), InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77"));

        Assert.Null(parsed.Request);
        Assert.Equal(RestoreParseFailure.ValidationFailed, parsed.Failure);
    }

    [Fact]
    public void MoreThanTwentyItemsOrAnOverlongTokenIsRefused()
    {
        var item = "{\"productId\":\"zaghlol_gold_lifetime\",\"purchaseToken\":\"t\"}";
        var tooMany = "{\"platform\":\"android\",\"purchases\":[" + string.Join(",", Enumerable.Repeat(item, 21)) + "],\"attestation\":{\"type\":\"play_integrity\",\"token\":\"0123456789abcdef\"}}";
        var longToken = "{\"platform\":\"android\",\"purchases\":[{\"productId\":\"zaghlol_gold_lifetime\",\"purchaseToken\":\"" + new string('a', 513) + "\"}],\"attestation\":{\"type\":\"play_integrity\",\"token\":\"0123456789abcdef\"}}";
        var installId = InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77");

        Assert.Equal(RestoreParseFailure.ValidationFailed, RestoreRequestParser.Parse(Encoding.UTF8.GetBytes(tooMany), installId).Failure);
        Assert.Equal(RestoreParseFailure.ValidationFailed, RestoreRequestParser.Parse(Encoding.UTF8.GetBytes(longToken), installId).Failure);
    }

    [Fact]
    public void TheHashedObjectIsTheBoundObjectMemberOrderAndWhitespaceDoNotChangeIt()
    {
        var installId = InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77");
        const string Compact = "{\"platform\":\"android\",\"purchases\":[{\"productId\":\"zaghlol_gold_lifetime\",\"purchaseToken\":\"t\"}],\"attestation\":{\"type\":\"play_integrity\",\"token\":\"0123456789abcdef\"}}";
        const string Reordered = "{ \"attestation\": {\"token\":\"ffffffffffffffffffff\", \"type\":\"play_integrity\"}, \"purchases\": [ {\"purchaseToken\":\"t\", \"productId\":\"zaghlol_gold_lifetime\"} ], \"platform\":\"android\" }";

        var a = RestoreRequestParser.Parse(Encoding.UTF8.GetBytes(Compact), installId);
        var b = RestoreRequestParser.Parse(Encoding.UTF8.GetBytes(Reordered), installId);

        Assert.Equal(a.Request!.BodyHash, b.Request!.BodyHash);
        Assert.Equal(
            Convert.ToHexStringLower(SHA256.HashData([.. "zaghlol-restore-v1"u8, 0, .. Encoding.ASCII.GetBytes(installId.Value.ToString("D")), 0, .. "{\"platform\":\"android\",\"purchases\":[{\"productId\":\"zaghlol_gold_lifetime\",\"purchaseToken\":\"t\"}]}"u8])),
            Convert.ToHexStringLower(a.Request.BodyHash));
        Assert.Equal(43, Base64Url.EncodeToString(a.Request.BodyHash).Length);
    }
}
