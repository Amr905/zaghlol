using System.Text.Json.Nodes;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Seats;
using Zaghlol.Testing;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// <c>seat-key-hash-v1.json</c> (T-182 design note §4, §9): the production input builders give the pinned bytes, and the
/// production hasher over <see cref="IKeyedHasher"/> and the fake KMS with the fixed <c>K_seat</c> gives the pinned MACs, which
/// were computed independently with Python <c>hmac</c>.
/// </summary>
public class SeatKeyHashVectorTests
{
    private static readonly JsonObject Vector = JsonNode.Parse(
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "vectors", "seat-key-hash-v1.json")))!.AsObject();

    private static readonly JsonObject Proofs = JsonNode.Parse(
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "vectors", "seat-proof-v1.json")))!.AsObject();

    [Fact]
    public void TheInputBuildersGiveThePinnedBytes()
    {
        var restore = Restore();
        var point = Convert.FromHexString(Text("installKeyInputHex"))[44..];
        Assert.Equal(Text("publicKey"), Text(restore, "publicKey"));

        Assert.Equal(Text("installKeyInputHex"), Hex(SeatKeyHasher.InstallKeyInput(InstallId.Parse(Text("installId")), point)));
        Assert.Equal(Text("seatKeyInputHex"), Hex(SeatKeyHasher.SeatKeyInput(Guid.Parse(Text("purchaseId")), point)));
        Assert.Equal(Text("seatCheckInputHex"), Hex(SeatKeyHasher.SeatCheckInput()));
        Assert.Equal(Hex(FakeKms.FixedSeatKey), Text("keyHex"));
    }

    [Fact]
    public async Task TheKeyedHasherWithTheFixedKeyGivesThePinnedMacs()
    {
        using var kms = FakeKms.CreateDefault().UseFixedSeatKey();
        await using var services = kms.BuildServices(configure: s => s.AddZaghlolSeatKeys());
        var hasher = services.GetRequiredService<IKeyedHasher>();

        foreach (var (input, expected) in new[] { ("installKeyInputHex", "installKeyHashHex"), ("seatKeyInputHex", "seatKeyHashHex"), ("seatCheckInputHex", "seatCheckHex") })
        {
            var mac = await hasher.HmacSha256Async(KeyedHashKey.Seat, Convert.FromHexString(Text(input)), CancellationToken.None);
            Assert.Equal(Text(expected), Hex(mac));
        }

        Assert.Equal(Text("seatCheckHex"), kms.SeatCheckHex());
    }

    [Fact]
    public async Task TheSeatKeyHasherOverAVerifiedKeyGivesThePinnedHashes()
    {
        using var kms = FakeKms.CreateDefault().UseFixedSeatKey();
        await using var services = kms.BuildServices(configure: s => s.AddZaghlolSeatKeys());
        var verifier = services.GetRequiredService<SeatKeyProofVerifier>();
        var hasher = services.GetRequiredService<SeatKeyHasher>();
        var restore = Restore();
        var installId = InstallId.Parse(Text("installId"));
        Assert.Equal(Text(restore, "installId"), installId.ToString());

        var verified = verifier.ParseAndVerify(
            [new SeatKeyProofInput(Text(restore, "publicKey"), Text(restore, "signature"))],
            SeatChallenge.ForRestore(Convert.FromHexString(Text(restore, "challengeHex"))),
            installId);
        Assert.True(verified.IsValid);

        var install = await hasher.InstallKeyHashAsync(installId, verified.Keys.ElementZero, CancellationToken.None);
        var seat = await hasher.SeatKeyHashAsync(Guid.Parse(Text("purchaseId")), verified.Keys.ElementZero, CancellationToken.None);
        var check = await hasher.SeatCheckAsync(CancellationToken.None);

        Assert.Equal(Text("installKeyHashHex"), Hex(install.ToStorage()));
        Assert.Equal(Text("seatKeyHashHex"), Hex(seat.ToStorage()));
        Assert.Equal(Text("seatCheckHex"), Hex(check));

        var zero = await hasher.CheckElementZeroAsync(installId, InstallKeyHash.FromStored(Convert.FromHexString(Text("installKeyHashHex"))), verified.Keys, CancellationToken.None);
        Assert.Equal(ElementZeroStatus.MatchesRegistered, zero.Status);
    }

    private static JsonNode Restore() => Proofs["valid"]!.AsArray().Single(v => v!["name"]!.GetValue<string>() == "restore")!;

    private static string Text(string name) => Vector[name]!.GetValue<string>();

    private static string Text(JsonNode node, string name) => node[name]!.GetValue<string>();

    private static string Hex(byte[] bytes) => Convert.ToHexStringLower(bytes);
}
