using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>Signer failure tests and the sign_verify metric tests share the process-wide KMS meter, so they run one at a time.</summary>
internal static class SignerMetricsCollection
{
    public const string Name = "kms-signer-metrics";
}

/// <summary>T-123: ES256 signatures, JWS, rotation and fail-closed behaviour of <see cref="ISigner"/>.</summary>
[Collection(SignerMetricsCollection.Name)]
public partial class SignerTests
{
    private static readonly byte[] Body = "{\"serverTime\":\"2026-11-08T00:00:00Z\",\"timeNonce\":null}"u8.ToArray();

    [GeneratedRegex("^kid=([se][0-9]{4}[a-z]); alg=ES256; sig=([A-Za-z0-9_-]{86})\\z")]
    private static partial Regex HeaderPattern();

    [Fact]
    public async Task SignatureVerifiesWithTheExportedPublicKey()
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices();
        var signer = services.GetRequiredService<ISigner>();

        var signature = await signer.SignAsync(SigningPurpose.Sync, Body, CancellationToken.None);

        var match = HeaderPattern().Match(signature.HeaderValue);
        Assert.True(match.Success, signature.HeaderValue);
        Assert.Equal(FakeKms.SyncKid, match.Groups[1].Value);
        Assert.True(VerifyWithJwks(EcPublicJwk.ToJwks(signer.PublishedKeys(SigningPurpose.Sync)), match.Groups[1].Value, Body, Base64Url.DecodeFromChars(match.Groups[2].Value)));
    }

    [Fact]
    public async Task RotationKeepsTheOldKidVerifiableUntilItIsRemoved()
    {
        using var kms = FakeKms.CreateDefault();
        kms.AddSigningKey("s0001t", SigningPurpose.Sync, SigningKeyStatus.Next);

        ResponseSignature before;
        await using (var services = kms.BuildServices())
        {
            var signer = services.GetRequiredService<ISigner>();
            before = await signer.SignAsync(SigningPurpose.Sync, Body, CancellationToken.None);
            Assert.Equal(FakeKms.SyncKid, before.Kid);

            // The next key is already published (embedded in the app a release early) but never signs.
            Assert.Contains(signer.PublishedKeys(SigningPurpose.Sync), k => k.Kid == "s0001t" && k.Status == SigningKeyStatus.Next);
        }

        // A rotation is a config deploy: A -> retired, B -> active.
        kms.SetStatus(FakeKms.SyncKid, SigningKeyStatus.Retired);
        kms.SetStatus("s0001t", SigningKeyStatus.Active);
        await using (var services = kms.BuildServices())
        {
            var signer = services.GetRequiredService<ISigner>();
            var after = await signer.SignAsync(SigningPurpose.Sync, Body, CancellationToken.None);
            var jwks = EcPublicJwk.ToJwks(signer.PublishedKeys(SigningPurpose.Sync));

            Assert.Equal("s0001t", after.Kid);
            Assert.True(VerifyWithJwks(jwks, before.Kid, Body, before.Signature.ToArray()));
            Assert.True(VerifyWithJwks(jwks, after.Kid, Body, after.Signature.ToArray()));
            Assert.Contains(signer.PublishedKeys(SigningPurpose.Sync), k => k.Kid == FakeKms.SyncKid && k.Status == SigningKeyStatus.Retired);
        }
    }

    [Fact]
    public async Task JwsHasTheFixedHeaderAndVerifiesWithTheEntitlementKey()
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices();
        var signer = services.GetRequiredService<ISigner>();

        var token = await signer.CreateJwsAsync(SigningPurpose.Entitlement, new { InstallId = "01JZAGHLOLTESTINSTALL00000", Status = "active" }, CancellationToken.None);

        var parts = token.Split('.');
        Assert.Equal(3, parts.Length);
        Assert.DoesNotContain("=", token, StringComparison.Ordinal);
        Assert.Equal("{\"alg\":\"ES256\",\"kid\":\"e0000t\",\"typ\":\"JWT\"}", Encoding.UTF8.GetString(Base64Url.DecodeFromChars(parts[0])));
        Assert.Equal("{\"installId\":\"01JZAGHLOLTESTINSTALL00000\",\"status\":\"active\"}", Encoding.UTF8.GetString(Base64Url.DecodeFromChars(parts[1])));
        var jwks = EcPublicJwk.ToJwks(signer.PublishedKeys(SigningPurpose.Entitlement));
        Assert.True(VerifyWithJwks(jwks, FakeKms.EntitlementKid, Encoding.ASCII.GetBytes(parts[0] + "." + parts[1]), Base64Url.DecodeFromChars(parts[2])));
    }

    [Fact]
    public async Task EachPurposeSignsOnlyInItsOwnPlace()
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices();
        var signer = services.GetRequiredService<ISigner>();

        await Assert.ThrowsAsync<ArgumentException>(async () => await signer.SignAsync(SigningPurpose.Entitlement, Body, CancellationToken.None));
        await Assert.ThrowsAsync<ArgumentException>(async () => await signer.CreateJwsAsync(SigningPurpose.Sync, new { a = 1 }, CancellationToken.None));
        Assert.All(signer.PublishedKeys(SigningPurpose.Sync), k => Assert.StartsWith("s", k.Kid, StringComparison.Ordinal));
        Assert.All(signer.PublishedKeys(SigningPurpose.Entitlement), k => Assert.StartsWith("e", k.Kid, StringComparison.Ordinal));
    }

    [Theory]
    [InlineData(FakeKmsFault.Throw)]
    [InlineData(FakeKmsFault.Hang)]
    [InlineData(FakeKmsFault.WrongKey)]
    public async Task AFailingKmsFailsClosedAfterOneRetry(FakeKmsFault fault)
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices(configure: s => s.AddSingleton(new KmsCallPolicy { Timeout = TimeSpan.FromMilliseconds(200) }));
        var signer = services.GetRequiredService<ISigner>();
        kms.Fault = fault;

        var error = await Assert.ThrowsAsync<KmsUnavailableException>(async () => await signer.SignAsync(SigningPurpose.Sync, Body, CancellationToken.None));

        Assert.Equal(KmsUnavailableException.DefaultMessage, error.Message);
        Assert.Null(error.InnerException);
        Assert.Equal(fault == FakeKmsFault.WrongKey ? 1 : 2, kms.Calls);
    }

    [Fact]
    public async Task CallerCancellationIsNotAnOutage()
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices();
        var signer = services.GetRequiredService<ISigner>();
        kms.Fault = FakeKmsFault.Hang;
        using var cancelled = new CancellationTokenSource(TimeSpan.FromMilliseconds(100));

        await Assert.ThrowsAnyAsync<OperationCanceledException>(async () => await signer.SignAsync(SigningPurpose.Sync, Body, cancelled.Token));
        Assert.Equal(1, kms.Calls);
    }

    [Fact]
    public async Task HighSSignaturesFromTheKmsAreAccepted()
    {
        // ECDSA is randomized; verifiers must accept high-S. The signer must not reject one either.
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices();
        var signer = services.GetRequiredService<ISigner>();
        var jwk = signer.PublishedKeys(SigningPurpose.Sync).Single().PublicJwk;

        var signature = (await signer.SignAsync(SigningPurpose.Sync, Body, CancellationToken.None)).Signature.ToArray();
        var flipped = HighS.FlipS(signature);

        Assert.True(jwk.Verifies(Body, signature));
        Assert.True(jwk.Verifies(Body, flipped));
        Assert.True(HighS.IsHighS(signature) || HighS.IsHighS(flipped));
    }

    internal static bool VerifyWithJwks(string jwks, string kid, byte[] data, byte[] signature)
    {
        using var document = JsonDocument.Parse(jwks);
        foreach (var key in document.RootElement.GetProperty("keys").EnumerateArray())
        {
            if (key.GetProperty("kid").GetString() != kid)
            {
                continue;
            }

            Assert.Equal("EC", key.GetProperty("kty").GetString());
            Assert.Equal("P-256", key.GetProperty("crv").GetString());
            Assert.Equal("ES256", key.GetProperty("alg").GetString());
            using var ec = ECDsa.Create(new ECParameters
            {
                Curve = ECCurve.NamedCurves.nistP256,
                Q = new ECPoint
                {
                    X = Base64Url.DecodeFromChars(key.GetProperty("x").GetString()),
                    Y = Base64Url.DecodeFromChars(key.GetProperty("y").GetString()),
                },
            });
            return ec.VerifyData(data, signature, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
        }

        return false;
    }
}

/// <summary>P-256 order arithmetic for high-S tests.</summary>
internal static class HighS
{
    private static readonly System.Numerics.BigInteger Order = System.Numerics.BigInteger.Parse(
        "0FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551", System.Globalization.NumberStyles.HexNumber, System.Globalization.CultureInfo.InvariantCulture);

    public static bool IsHighS(byte[] p1363) => S(p1363) > Order / 2;

    /// <summary><c>(r, s) → (r, n − s)</c>: the other valid signature for the same message.</summary>
    public static byte[] FlipS(byte[] p1363)
    {
        var flipped = (Order - S(p1363)).ToByteArray(isUnsigned: true, isBigEndian: true);
        var result = p1363.ToArray();
        Array.Clear(result, 32, 32);
        flipped.CopyTo(result, 64 - flipped.Length);
        return result;
    }

    private static System.Numerics.BigInteger S(byte[] p1363) => new(p1363.AsSpan(32, 32), isUnsigned: true, isBigEndian: true);
}
