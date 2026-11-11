using System.Reflection;
using System.Security.Cryptography;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Testing;
using static Zaghlol.Application.Tests.Seats.SeatKeyTestKit;

namespace Zaghlol.Application.Tests.Seats;

/// <summary>T-182 design note §1, §4, §5: keyed-hash construction, element 0, seat matching and failure behaviour.</summary>
public sealed class SeatKeyHasherTests : IDisposable
{
    private readonly RecordingSeatMetrics metrics = new();
    private readonly CountingSeatMac mac = new();
    private readonly List<SeatKeyTestSigner> signers = [.. Enumerable.Range(0, 5).Select(_ => new SeatKeyTestSigner())];

    private SeatKeyHasher Hasher => new(mac, metrics);

    public void Dispose() => signers.ForEach(s => s.Dispose());

    [Fact]
    public void TheThreeInputsHaveFixedDistinctLengthsAndFirstBytes()
    {
        var point = signers[0].PublicPoint;
        var install = SeatKeyHasher.InstallKeyInput(Install, point);
        var seat = SeatKeyHasher.SeatKeyInput(Purchase, point);
        var check = SeatKeyHasher.SeatCheckInput();

        Assert.Equal(109, install.Length);
        Assert.Equal(101, seat.Length);
        Assert.Equal(22, check.Length);
        Assert.Equal((byte)'i', install[0]);
        Assert.True(seat[0] is (>= (byte)'0' and <= (byte)'9') or (>= (byte)'a' and <= (byte)'f'));
        Assert.Equal((byte)'z', check[0]);
        Assert.Equal("install\0" + Install, System.Text.Encoding.ASCII.GetString(install, 0, 44));
        Assert.Equal(point, install[44..]);
        Assert.Equal(Purchase.ToString("D"), System.Text.Encoding.ASCII.GetString(seat, 0, 36));
        Assert.Equal(point, seat[36..]);
    }

    [Fact]
    public void TheInputBuildersRefuseAnythingButAnUncompressedPoint()
    {
        Assert.Throws<ArgumentException>(() => SeatKeyHasher.InstallKeyInput(Install, new byte[64]));
        Assert.Throws<ArgumentException>(() => SeatKeyHasher.SeatKeyInput(Purchase, [0x06, .. new byte[64]]));
    }

    [Fact]
    public async Task TheSamePublicKeyGivesDifferentInstallAndSeatHashes()
    {
        var keys = Verify(1);

        var install = await Hasher.InstallKeyHashAsync(Install, keys.ElementZero, CancellationToken.None);
        var seat = await Hasher.SeatKeyHashAsync(Purchase, keys.ElementZero, CancellationToken.None);

        Assert.NotEqual(install.ToStorage(), seat.ToStorage());
        Assert.Equal(HMACSHA256.HashData(Key(), SeatKeyHasher.InstallKeyInput(Install, signers[0].PublicPoint)), install.ToStorage());
        Assert.Equal(HMACSHA256.HashData(Key(), SeatKeyHasher.SeatKeyInput(Purchase, signers[0].PublicPoint)), seat.ToStorage());
    }

    [Fact]
    public async Task SeatHashesArePerPurchaseAndInstallHashesPerInstall()
    {
        var keys = Verify(1);
        var other = Guid.Parse("5f0c8a7e-2b1d-4e3f-9a6b-7c8d9e0f1a2c");

        var a = await Hasher.SeatKeyHashAsync(Purchase, keys.ElementZero, CancellationToken.None);
        var b = await Hasher.SeatKeyHashAsync(other, keys.ElementZero, CancellationToken.None);

        Assert.False(a.Matches(b));
        Assert.True(a.Matches(SeatKeyHash.FromStored(a.ToStorage())));
    }

    [Fact]
    public async Task ElementZeroIsNoneRegisteredMatchesOrMismatch()
    {
        var keys = Verify(2);
        var own = await Hasher.InstallKeyHashAsync(Install, keys.ElementZero, CancellationToken.None);
        var otherKeys = Verify(1, offset: 1);
        var other = await Hasher.InstallKeyHashAsync(Install, otherKeys.ElementZero, CancellationToken.None);

        var none = await Hasher.CheckElementZeroAsync(Install, null, keys, CancellationToken.None);
        var match = await Hasher.CheckElementZeroAsync(Install, InstallKeyHash.FromStored(own.ToStorage()), keys, CancellationToken.None);
        var mismatch = await Hasher.CheckElementZeroAsync(Install, other, keys, CancellationToken.None);

        Assert.Equal(ElementZeroStatus.NoneRegistered, none.Status);
        Assert.Equal(ElementZeroStatus.MatchesRegistered, match.Status);
        Assert.Equal(ElementZeroStatus.Mismatch, mismatch.Status);
        Assert.True(none.Computed.Matches(own));
        Assert.True(mismatch.Computed.Matches(own));
        Assert.Equal([(SeatOp.Restore, "none_registered"), (SeatOp.Restore, "matches"), (SeatOp.Restore, "mismatch")], metrics.ElementZeros);
    }

    [Fact]
    public async Task ElementZeroForAnotherInstallIsACallerBug()
    {
        var keys = Verify(1);

        await Assert.ThrowsAsync<ArgumentException>(() => Hasher.CheckElementZeroAsync(OtherInstall, null, keys, CancellationToken.None));
        Assert.Equal(0, mac.Calls);
    }

    [Theory]
    [InlineData(1)]
    [InlineData(2)]
    [InlineData(4)]
    public async Task ASeatMatchIsFoundOnlyAtPositionOneOrLater(int position)
    {
        var keys = Verify(5);
        var stored = await Hasher.AnyPositionSeatKeyHashAsync(Purchase, keys.Others[position - 1], CancellationToken.None);
        var before = mac.Calls;

        var match = await Hasher.MatchSeatAsync(Purchase, stored, keys, CancellationToken.None);

        Assert.Equal(position, match);
        Assert.Equal(4, mac.Calls - before);
    }

    [Fact]
    public async Task ElementZeroIsNeverASeatMatch()
    {
        var keys = Verify(3);
        var stored = await Hasher.SeatKeyHashAsync(Purchase, keys.ElementZero, CancellationToken.None);

        Assert.Null(await Hasher.MatchSeatAsync(Purchase, stored, keys, CancellationToken.None));
        Assert.Null(await Hasher.MatchSeatAsync(Purchase, stored, Verify(1), CancellationToken.None));
    }

    [Fact]
    public async Task MatchSeatHashesEveryCandidateInParallelWithAtMostFourInFlight()
    {
        var keys = Verify(5);
        var stored = await Hasher.AnyPositionSeatKeyHashAsync(Purchase, keys.Others[0], CancellationToken.None);
        mac.Delay = TimeSpan.FromMilliseconds(50);
        var before = mac.Calls;

        var match = await Hasher.MatchSeatAsync(Purchase, stored, keys, CancellationToken.None);

        Assert.Equal(1, match);
        Assert.Equal(4, mac.Calls - before);
        Assert.InRange(mac.MaxInFlight, 2, 4);
    }

    [Fact]
    public async Task AMacFailurePropagatesAndIsNeverAResult()
    {
        var keys = Verify(3);
        var stored = await Hasher.AnyPositionSeatKeyHashAsync(Purchase, keys.Others[0], CancellationToken.None);
        mac.Fault = new TimeoutException("kms down");

        await Assert.ThrowsAsync<TimeoutException>(() => Hasher.CheckElementZeroAsync(Install, null, keys, CancellationToken.None));
        await Assert.ThrowsAsync<TimeoutException>(() => Hasher.MatchSeatAsync(Purchase, stored, keys, CancellationToken.None));
        await Assert.ThrowsAsync<TimeoutException>(() => Hasher.SeatCheckAsync(CancellationToken.None));
        Assert.Empty(metrics.ElementZeros);
    }

    [Fact]
    public async Task AMacOfTheWrongLengthIsNeverAHash()
    {
        var keys = Verify(1);
        var shortMac = new ShortMac();

        await Assert.ThrowsAsync<InvalidOperationException>(() => new SeatKeyHasher(shortMac, metrics).InstallKeyHashAsync(Install, keys.ElementZero, CancellationToken.None));
        await Assert.ThrowsAsync<InvalidOperationException>(() => new SeatKeyHasher(shortMac, metrics).SeatKeyHashAsync(Purchase, keys.ElementZero, CancellationToken.None));
    }

    [Fact]
    public void StoredHashesMustBe32BytesAndAreCopied()
    {
        var bytes = Enumerable.Range(0, 32).Select(i => (byte)i).ToArray();
        var install = InstallKeyHash.FromStored(bytes);
        var seat = SeatKeyHash.FromStored(bytes);
        bytes[0] = 0xff;

        Assert.Equal(0, install.ToStorage()[0]);
        Assert.Equal(0, seat.ToStorage()[0]);
        install.ToStorage()[1] = 0xff;
        Assert.Equal(1, install.ToStorage()[1]);

        var error = Assert.Throws<InvalidOperationException>(() => InstallKeyHash.FromStored(new byte[31]));
        Assert.DoesNotContain("00", error.Message, StringComparison.Ordinal);
        Assert.Throws<InvalidOperationException>(() => SeatKeyHash.FromStored(new byte[33]));
        Assert.False(install.Matches(null));
        Assert.False(seat.Matches(null));
    }

    [Fact]
    public void InstallAndSeatHashesCannotBeComparedWithEachOther()
    {
        Assert.Equal(typeof(object), typeof(InstallKeyHash).BaseType);
        Assert.Equal(typeof(object), typeof(SeatKeyHash).BaseType);
        Assert.Empty(typeof(InstallKeyHash).GetInterfaces());
        Assert.Empty(typeof(SeatKeyHash).GetInterfaces());

        foreach (var (type, other) in new[] { (typeof(InstallKeyHash), typeof(SeatKeyHash)), (typeof(SeatKeyHash), typeof(InstallKeyHash)) })
        {
            var methods = type.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly);
            Assert.DoesNotContain(methods, m => m.GetParameters().Any(p => p.ParameterType == other));
            Assert.DoesNotContain(methods, m => m.Name is "Equals" or "op_Equality" or "op_Implicit" or "op_Explicit");
            Assert.Single(methods, m => m.Name == "Matches" && m.GetParameters().Single().ParameterType == type);
        }

        var a = InstallKeyHash.FromStored(new byte[32]);
        var b = SeatKeyHash.FromStored(new byte[32]);
        Assert.False(a.Equals(b));
    }

    [Fact]
    public void NoPublicMemberReturnsKeyOrSignatureBytesAndEveryTypePrintsStars()
    {
        Type[] types =
        [
            typeof(ParsedSeatKeys), typeof(VerifiedSeatKeys), typeof(VerifiedSeatKey), typeof(InstallKeyHash), typeof(SeatKeyHash),
            typeof(SeatChallenge), typeof(SeatKeyProofInput),
        ];
        foreach (var type in types)
        {
            var exposed = type.GetProperties(BindingFlags.Public | BindingFlags.Instance)
                .Where(p => p.PropertyType == typeof(byte[]) || p.PropertyType == typeof(ReadOnlyMemory<byte>) || p.PropertyType.Name.StartsWith("ReadOnlySpan", StringComparison.Ordinal) || p.PropertyType == typeof(byte[][]))
                .Select(p => p.Name);
            Assert.Empty(exposed);
        }

        // Byte-returning public methods are limited to hashes (digests, stored hashes) and the public challenge.
        var byteMethods = types.SelectMany(t => t.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly)
            .Where(m => m.ReturnType == typeof(byte[])).Select(m => $"{t.Name}.{m.Name}")).Order().ToList();
        Assert.Equal(["InstallKeyHash.ToStorage", "ParsedSeatKeys.Digest", "SeatChallenge.ToArray", "SeatKeyHash.ToStorage", "VerifiedSeatKeys.Digest"], byteMethods);

        var keys = Verify(2);
        var proof = signers[0].Prove(Restore(), Install);
        object[] values = [keys, keys.ElementZero, keys.Others[0], Restore(), proof, InstallKeyHash.FromStored(new byte[32]), SeatKeyHash.FromStored(new byte[32])];
        Assert.All(values, v => Assert.Equal("***", v.ToString()));
        Assert.Equal("***", $"{proof}");
    }

    [Fact]
    public void SeatCheckValuesAreStrictLowerCaseHex()
    {
        var computed = HMACSHA256.HashData(Key(), "zaghlol-kseat-check-v1"u8);
        var hex = Convert.ToHexStringLower(computed);

        Assert.True(SeatCheckValue.Matches(hex, computed));
        Assert.False(SeatCheckValue.Matches(hex.ToUpperInvariant(), computed));
        Assert.False(SeatCheckValue.Matches(hex[..63], computed));
        Assert.False(SeatCheckValue.Matches(hex + "0", computed));
        Assert.False(SeatCheckValue.Matches(" " + hex[1..], computed));
        Assert.False(SeatCheckValue.Matches(null, computed));
        Assert.False(SeatCheckValue.Matches(new string('0', 64), computed));
        Assert.Equal("fe38d23ca263a6f7334148b2ae03e1d4b71a9fa54a062f3efe0470055de93e5b", hex);
    }

    [Fact]
    public async Task L1TheSeatHashRefusesAKeyAtPositionOneOrLater()
    {
        var keys = Verify(3);

        foreach (var other in keys.Others)
        {
            await Assert.ThrowsAsync<ArgumentException>(() => Hasher.SeatKeyHashAsync(Purchase, other, CancellationToken.None));
        }

        Assert.Equal(0, mac.Calls);
    }

    [Fact]
    public async Task L1TheHolderHashIsElementZeroWhateverElseTheSetCarries()
    {
        var keys = Verify(3);

        var holder = await Hasher.SeatKeyHashForHolderAsync(Purchase, keys, CancellationToken.None);

        Assert.Equal(HMACSHA256.HashData(Key(), SeatKeyHasher.SeatKeyInput(Purchase, signers[0].PublicPoint)), holder.ToStorage());
        Assert.NotEqual(HMACSHA256.HashData(Key(), SeatKeyHasher.SeatKeyInput(Purchase, signers[1].PublicPoint)), holder.ToStorage());
    }

    private static byte[] Key() => [.. Enumerable.Range(0, 32).Select(i => (byte)i)];

    private VerifiedSeatKeys Verify(int count, int offset = 0)
    {
        var challenge = Restore();
        var proofs = signers.Skip(offset).Take(count).Select(s => (SeatKeyProofInput?)s.Prove(challenge, Install)).ToList();
        var result = new SeatKeyProofVerifier(new RecordingSeatMetrics()).ParseAndVerify(proofs, challenge, Install);
        Assert.True(result.IsValid, result.ToString());
        return result.Keys;
    }

    private sealed class ShortMac : ISeatKeyMac
    {
        public ValueTask<byte[]> MacAsync(ReadOnlyMemory<byte> input, CancellationToken cancellationToken) => ValueTask.FromResult(new byte[16]);
    }
}
