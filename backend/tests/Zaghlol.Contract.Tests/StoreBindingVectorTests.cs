using System.Text.Json.Nodes;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// The shared <c>StoreBindingRef</c> vectors (backend-api §4.3, T-130 design note §5). The values were computed by an independent
/// implementation; T-131 (.NET) and T-145 (Dart) must reproduce the same file.
/// </summary>
public class StoreBindingVectorTests
{
    private static readonly JsonObject Vectors =
        JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "vectors", "store-binding-v1.json")))!.AsObject();

    [Fact]
    public void EveryVectorIsReproducedAndIsAVersion8Uuid()
    {
        Assert.Equal(StoreBindingRef.KeyLabel, Vectors["key"]!.GetValue<string>());
        var vectors = Vectors["vectors"]!.AsArray();
        Assert.True(vectors.Count >= 5);

        foreach (var vector in vectors)
        {
            var installId = InstallId.Parse(vector!["installId"]!.GetValue<string>());
            var expected = vector["storeBindingRef"]!.GetValue<string>();

            var actual = StoreBindingRef.Compute(installId);

            Assert.Equal(expected, actual);
            Assert.Equal(StoreBindingRef.Length, actual.Length);
            Assert.Equal('8', actual[14]);
            Assert.Contains(actual[19], "89ab");
            Assert.True(StoreBindingRef.Matches(expected, installId));
            Assert.True(Guid.TryParseExact(actual, "D", out _));

            // The first 16 HMAC bytes, apart from the version and variant bits, are the UUID bytes.
            var hmac = Convert.FromHexString(vector["hmacSha256Hex"]!.GetValue<string>());
            var bytes = Convert.FromHexString(actual.Replace("-", string.Empty, StringComparison.Ordinal));
            Assert.Equal(hmac[..6], bytes[..6]);
            Assert.Equal(hmac[9..16], bytes[9..16]);
        }
    }

    [Fact]
    public void EveryMismatchIsRejected()
    {
        var mismatches = Vectors["mismatches"]!.AsArray();
        Assert.NotEmpty(mismatches);
        foreach (var mismatch in mismatches)
        {
            var installId = InstallId.Parse(mismatch!["installId"]!.GetValue<string>());
            Assert.False(StoreBindingRef.Matches(mismatch["storeValue"]!.GetValue<string>(), installId), mismatch["why"]!.GetValue<string>());
        }

        Assert.False(StoreBindingRef.Matches(null, InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77")));
    }

    /// <summary>
    /// T-131: every vector verifies as an Apple <c>appAccountToken</c>, which is compared as a UUID (16 bytes). So the one mismatch
    /// that is the same UUID in upper-case hex matches for Apple (Apple's payload carries a UUID, not our string); every other
    /// mismatch is rejected there too.
    /// </summary>
    [Fact]
    public void EveryVectorVerifiesAsAnAppAccountToken()
    {
        foreach (var vector in Vectors["vectors"]!.AsArray())
        {
            var installId = InstallId.Parse(vector!["installId"]!.GetValue<string>());
            var expected = vector["storeBindingRef"]!.GetValue<string>();

            Assert.True(StoreBindingRef.MatchesAppAccountToken(expected, installId));
            Assert.True(StoreBindingRef.MatchesAppAccountToken(expected.ToUpperInvariant(), installId));
            Assert.True(StoreBindingRef.TryCanonicalUuid(expected.ToUpperInvariant(), out var canonical));
            Assert.Equal(expected, canonical);
        }

        foreach (var mismatch in Vectors["mismatches"]!.AsArray())
        {
            var installId = InstallId.Parse(mismatch!["installId"]!.GetValue<string>());
            var value = mismatch["storeValue"]!.GetValue<string>();
            var sameUuid = string.Equals(value, StoreBindingRef.Compute(installId), StringComparison.OrdinalIgnoreCase);
            Assert.Equal(sameUuid, StoreBindingRef.MatchesAppAccountToken(value, installId));
        }

        Assert.False(StoreBindingRef.MatchesAppAccountToken(null, InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77")));
        Assert.False(StoreBindingRef.MatchesAppAccountToken("{" + StoreBindingRef.Compute(InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77")) + "}", InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77")));
    }
}
