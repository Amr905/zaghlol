using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Zaghlol.Application.Seats.SeatKeys;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// Published Project Wycheproof vectors (C2SP/wycheproof <c>testvectors_v1/ecdsa_secp256r1_sha256_p1363_test.json</c>,
/// Apache-2.0, pinned commit in <c>vectors/wycheproof/NOTICE.txt</c>) through the production primitive
/// <see cref="P256.VerifyP1363"/> (T-182 design note §9): every <c>valid</c> case verifies and every <c>invalid</c> case fails.
/// <c>acceptable</c> cases are rejected unless their only flag is about high S (which §2 accepts on purpose).
/// </summary>
public class WycheproofP256Tests
{
    private const string PinnedSha256 = "c60de693930e386c3a5472d08081623ef8504decc54b38ac01ec6b2a2575c986";

    private static readonly string FilePath =
        Path.Combine(AppContext.BaseDirectory, "vectors", "wycheproof", "ecdsa_secp256r1_sha256_p1363_test.json");

    [Fact]
    public void TheVendoredFileIsThePinnedOne()
    {
        Assert.Equal(PinnedSha256, Convert.ToHexStringLower(SHA256.HashData(File.ReadAllBytes(FilePath))));
    }

    [Fact]
    public void EveryCaseGivesItsExpectedResult()
    {
        var root = JsonNode.Parse(File.ReadAllText(FilePath))!.AsObject();
        Assert.Equal("ECDSA", root["algorithm"]!.GetValue<string>());

        var failures = new List<string>();
        var counts = new Dictionary<string, int>(StringComparer.Ordinal) { ["valid"] = 0, ["invalid"] = 0, ["acceptable"] = 0 };
        var acceptable = new List<string>();
        foreach (var group in root["testGroups"]!.AsArray())
        {
            Assert.Equal("EcdsaP1363Verify", group!["type"]!.GetValue<string>());
            Assert.Equal("secp256r1", group["publicKey"]!["curve"]!.GetValue<string>());
            Assert.Equal("SHA-256", group["sha"]!.GetValue<string>());
            var point = Convert.FromHexString(group["publicKey"]!["uncompressed"]!.GetValue<string>());

            foreach (var test in group["tests"]!.AsArray())
            {
                var id = test!["tcId"]!.GetValue<int>();
                var result = test["result"]!.GetValue<string>();
                var flags = test["flags"]!.AsArray().Select(f => f!.GetValue<string>()).ToList();
                var verified = P256.VerifyP1363(
                    point, Convert.FromHexString(test["msg"]!.GetValue<string>()), Convert.FromHexString(test["sig"]!.GetValue<string>()));
                counts[result]++;

                var expected = result switch
                {
                    "valid" => true,
                    "invalid" => false,
                    "acceptable" => flags.All(f => f.Contains("Malleab", StringComparison.OrdinalIgnoreCase) || f.Contains("HighS", StringComparison.OrdinalIgnoreCase)),
                    _ => throw new InvalidOperationException("unknown result " + result),
                };
                if (result == "acceptable")
                {
                    acceptable.Add($"tcId {id} [{string.Join(',', flags)}] -> {(verified ? "accepted" : "rejected")}");
                }

                if (verified != expected)
                {
                    failures.Add($"tcId {id} ({result}, {string.Join(',', flags)}): verified={verified}");
                }
            }
        }

        Assert.Empty(failures);
        Assert.Equal(root["numberOfTests"]!.GetValue<int>(), counts.Values.Sum());
        Assert.True(counts["valid"] > 100 && counts["invalid"] > 50, string.Join(", ", counts));
        Assert.Equal(counts["acceptable"], acceptable.Count);
    }
}
