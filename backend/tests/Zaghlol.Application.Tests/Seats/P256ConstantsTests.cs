using System.Numerics;
using System.Security.Cryptography;
using Zaghlol.Application.Seats.SeatKeys;

namespace Zaghlol.Application.Tests.Seats;

/// <summary>T-182 design note §3 step 5: the managed curve constants equal the platform's explicit P-256 parameters.</summary>
public class P256ConstantsTests
{
    [Fact]
    public void TheConstantsMatchThePlatformsExplicitParameters()
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var curve = key.ExportExplicitParameters(false).Curve;

        Assert.Equal(P256.Prime, Unsigned(curve.Prime!));
        Assert.Equal(P256.A, Unsigned(curve.A!));
        Assert.Equal(P256.B, Unsigned(curve.B!));
        Assert.Equal(P256.Order, Unsigned(curve.Order!));
        Assert.Equal(P256.Gx, Unsigned(curve.G.X!));
        Assert.Equal(P256.Gy, Unsigned(curve.G.Y!));
    }

    [Fact]
    public void TheGeneratorAndFreshKeysAreOnTheCurveAndNeighboursAreNot()
    {
        byte[] g = [0x04, .. Fixed(P256.Gx), .. Fixed(P256.Gy)];
        Assert.True(P256.IsUncompressedOnCurve(g));

        for (var i = 0; i < 20; i++)
        {
            using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
            var q = key.ExportParameters(false).Q;
            byte[] point = [0x04, .. q.X!, .. q.Y!];
            Assert.True(P256.IsUncompressedOnCurve(point));

            var y = new BigInteger(q.Y, isUnsigned: true, isBigEndian: true);
            Assert.False(P256.IsUncompressedOnCurve([0x04, .. q.X!, .. Fixed((y + 1) % P256.Prime)]));

            // (x, p − y) is on the curve too: the negated point is a valid key.
            Assert.True(P256.IsUncompressedOnCurve([0x04, .. q.X!, .. Fixed(P256.Prime - y)]));

            // y + p doesn't fit in 32 bytes, but a coordinate ≥ p must be refused even when it is ≡ y (mod p).
            if (y < BigInteger.Pow(2, 256) - P256.Prime)
            {
                Assert.False(P256.IsUncompressedOnCurve([0x04, .. q.X!, .. Fixed(y + P256.Prime)]));
            }
        }

        Assert.False(P256.IsUncompressedOnCurve([0x04, .. new byte[64]]));
        Assert.False(P256.IsUncompressedOnCurve(g.AsSpan(0, 64)));
        Assert.False(P256.IsUncompressedOnCurve([0x06, .. g[1..]]));
        Assert.False(P256.IsUncompressedOnCurve([0x04, .. Fixed(P256.Prime), .. Fixed(P256.Gy)]));
    }

    private static BigInteger Unsigned(byte[] bytes) => new(bytes, isUnsigned: true, isBigEndian: true);

    private static byte[] Fixed(BigInteger value)
    {
        var bytes = value.ToByteArray(isUnsigned: true, isBigEndian: true);
        return [.. new byte[32 - bytes.Length], .. bytes];
    }
}
