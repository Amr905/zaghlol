using System.Text;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Testing;
using static Zaghlol.Application.Tests.Seats.SeatKeyTestKit;

namespace Zaghlol.Application.Tests.Seats;

/// <summary>T-182 design note §2–§3 and the acceptance criteria, with real software-key proofs.</summary>
public class SeatKeyProofVerifierTests
{
    private readonly RecordingSeatMetrics metrics = new();

    private SeatKeyProofVerifier Verifier => new(metrics);

    [Theory]
    [InlineData(SeatOp.Verify)]
    [InlineData(SeatOp.Restore)]
    [InlineData(SeatOp.SignIn)]
    public void AValidProofVerifiesForItsOp(SeatOp op)
    {
        using var signer = new SeatKeyTestSigner();
        var challenge = For(op);

        var result = Verifier.ParseAndVerify([signer.Prove(challenge, Install)], challenge, Install);

        Assert.True(result.IsValid, result.ToString());
        Assert.Equal(op, result.Keys.Op);
        Assert.Equal(Install, result.Keys.InstallId);
        Assert.Equal(0, result.Keys.ElementZero.Position);
        Assert.Empty(result.Keys.Others);
        Assert.Equal([(op, "valid")], metrics.Proofs);
    }

    [Fact]
    public void TheMessageIsTheDocumentedBytes()
    {
        var challenge = Restore(0xab);
        var expected = SeatKeyTestSigner.Message("restore", Install.ToString(), challenge.ToArray());

        var message = SeatKeyProofVerifier.Message(SeatOp.Restore, Install, challenge.ToArray());

        Assert.Equal(expected, message);
        Assert.Equal(15 + 1 + 7 + 1 + 36 + 1 + 32, message.Length);
        Assert.Equal("zaghlol-seat-v1\0restore\00193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\0", Encoding.ASCII.GetString(message, 0, message.Length - 32));
    }

    [Fact]
    public void ASignatureForAnotherInstallFails()
    {
        using var signer = new SeatKeyTestSigner();
        var challenge = Restore();

        var result = Verifier.ParseAndVerify([signer.Prove(challenge, OtherInstall)], challenge, Install);

        Assert.Equal(SeatKeyRejection.BadSignature, result.Rejection);
    }

    [Theory]
    [InlineData(SeatOp.Restore, "signin")]
    [InlineData(SeatOp.SignIn, "restore")]
    [InlineData(SeatOp.Verify, "restore")]
    [InlineData(SeatOp.Restore, "RESTORE")]
    public void ASignatureForAnotherOpFails(SeatOp op, string signedOp)
    {
        using var signer = new SeatKeyTestSigner();
        var challenge = For(op);

        var result = Verifier.ParseAndVerify([signer.Prove(signedOp, Install.ToString(), challenge.ToArray())], challenge, Install);

        Assert.Equal(SeatKeyRejection.BadSignature, result.Rejection);
    }

    [Fact]
    public void ASignatureForAnotherChallengeFails()
    {
        using var signer = new SeatKeyTestSigner();

        var result = Verifier.ParseAndVerify([signer.Prove(Restore(0x22), Install)], Restore(0x23), Install);

        Assert.Equal(SeatKeyRejection.BadSignature, result.Rejection);
    }

    [Fact]
    public void AnUpperCaseInstallIdInTheMessageFails()
    {
        using var signer = new SeatKeyTestSigner();
        var challenge = Restore();

        var result = Verifier.ParseAndVerify([signer.Prove("restore", Install.ToString().ToUpperInvariant(), challenge.ToArray())], challenge, Install);

        Assert.Equal(SeatKeyRejection.BadSignature, result.Rejection);
    }

    [Fact]
    public void KeyBWithKeyAsSignatureFails()
    {
        using var a = new SeatKeyTestSigner();
        using var b = new SeatKeyTestSigner();
        var challenge = Restore();

        var result = Verifier.ParseAndVerify([b.WithSignatureOf(a.Prove(challenge, Install))], challenge, Install);

        Assert.Equal(SeatKeyRejection.BadSignature, result.Rejection);
    }

    [Theory]
    [MemberData(nameof(Defects))]
    public void EveryDefectIsRejectedWithItsReason(SeatKeyDefect defect)
    {
        using var signer = new SeatKeyTestSigner();
        var challenge = Restore();
        var proof = SeatKeyTestSigner.Defective(signer.Prove(challenge, Install), defect);

        var result = Verifier.ParseAndVerify([proof], challenge, Install);

        Assert.False(result.IsValid);
        Assert.Equal(SeatKeyTestSigner.ExpectedRejection(defect), result.Rejection);
        Assert.Equal([(SeatOp.Restore, SeatKeyTags.Result(result.Rejection))], metrics.Proofs);
    }

    public static TheoryData<SeatKeyDefect> Defects() => [.. Enum.GetValues<SeatKeyDefect>()];

    [Fact]
    public void HighAndLowSAreBothAccepted()
    {
        using var signer = new SeatKeyTestSigner();
        var challenge = Restore();
        var proof = signer.Prove(challenge, Install);

        Assert.True(Verifier.ParseAndVerify([proof], challenge, Install).IsValid);
        Assert.True(Verifier.ParseAndVerify([SeatKeyTestSigner.FlipS(proof)], challenge, Install).IsValid);
    }

    [Theory]
    [InlineData(SeatOp.Verify, 1)]
    [InlineData(SeatOp.Restore, 5)]
    [InlineData(SeatOp.SignIn, 5)]
    public void TheMaximumCountPassesAndOneMoreIsTooMany(SeatOp op, int max)
    {
        var signers = Enumerable.Range(0, max + 1).Select(_ => new SeatKeyTestSigner()).ToList();
        try
        {
            var challenge = For(op);
            var proofs = signers.Select(s => (SeatKeyProofInput?)s.Prove(challenge, Install)).ToList();

            var atMax = Verifier.ParseAndVerify(proofs[..max], challenge, Install);
            Assert.True(atMax.IsValid, atMax.ToString());
            Assert.Equal(max - 1, atMax.Keys.Others.Count);
            Assert.Equal(Enumerable.Range(1, max - 1), atMax.Keys.Others.Select(k => k.Position));

            Assert.Equal(SeatKeyRejection.TooMany, Verifier.ParseAndVerify(proofs, challenge, Install).Rejection);
        }
        finally
        {
            signers.ForEach(s => s.Dispose());
        }
    }

    [Fact]
    public void TheCountIsCheckedBeforeAnyDecoding()
    {
        var garbage = Enumerable.Repeat((SeatKeyProofInput?)new SeatKeyProofInput("x", "y"), 6).ToList();

        Assert.Equal(SeatKeyRejection.TooMany, Verifier.Parse(SeatOp.Restore, garbage).Rejection);
        Assert.Equal(SeatKeyRejection.TooMany, Verifier.Parse(SeatOp.Verify, garbage[..2]).Rejection);
        Assert.Equal(SeatKeyRejection.Empty, Verifier.Parse(SeatOp.Restore, []).Rejection);
        Assert.Equal(SeatKeyRejection.Empty, Verifier.Parse(SeatOp.Restore, null).Rejection);
    }

    [Fact]
    public void ARepeatedPublicKeyIsADuplicate()
    {
        using var signer = new SeatKeyTestSigner();
        var challenge = Restore();
        var proof = signer.Prove(challenge, Install);

        Assert.Equal(SeatKeyRejection.Duplicate, Verifier.ParseAndVerify([proof, proof], challenge, Install).Rejection);

        // Same key with a different (equally valid) signature is still a duplicate.
        Assert.Equal(SeatKeyRejection.Duplicate, Verifier.ParseAndVerify([proof, SeatKeyTestSigner.FlipS(proof)], challenge, Install).Rejection);
    }

    [Fact]
    public void EveryElementMustBeValidAndTheFirstFailingReasonIsReported()
    {
        using var a = new SeatKeyTestSigner();
        using var b = new SeatKeyTestSigner();
        using var c = new SeatKeyTestSigner();
        var challenge = Restore();
        var good = a.Prove(challenge, Install);
        var badSignature = SeatKeyTestSigner.Defective(b.Prove(challenge, Install), SeatKeyDefect.FlippedSignatureBit);
        var offCurve = SeatKeyTestSigner.Defective(c.Prove(challenge, Install), SeatKeyDefect.OffCurve);

        Assert.Equal(SeatKeyRejection.BadSignature, Verifier.ParseAndVerify([good, badSignature, offCurve], challenge, Install).Rejection);
        Assert.Equal(SeatKeyRejection.BadPoint, Verifier.ParseAndVerify([good, offCurve, badSignature], challenge, Install).Rejection);
        Assert.Equal(SeatKeyRejection.BadSignature, Verifier.ParseAndVerify([badSignature, good], challenge, Install).Rejection);
        Assert.Equal(SeatKeyRejection.BadSignature, Verifier.ParseAndVerify([good, b.Prove(Restore(0x99), Install)], challenge, Install).Rejection);
    }

    [Fact]
    public void NullElementsAndNullMembersAreEncodingFailures()
    {
        using var signer = new SeatKeyTestSigner();
        var challenge = Restore();
        var proof = signer.Prove(challenge, Install);

        Assert.Equal(SeatKeyRejection.Encoding, Verifier.ParseAndVerify([null], challenge, Install).Rejection);
        Assert.Equal(SeatKeyRejection.Encoding, Verifier.ParseAndVerify([proof with { PublicKey = null! }], challenge, Install).Rejection);
        Assert.Equal(SeatKeyRejection.Encoding, Verifier.ParseAndVerify([proof with { Signature = null! }], challenge, Install).Rejection);
    }

    [Fact]
    public void StandardBase64AndUnicodeLookalikesAreEncodingFailures()
    {
        using var signer = new SeatKeyTestSigner();
        var challenge = Restore();
        var proof = signer.Prove(challenge, Install);
        var standard = proof.PublicKey.Replace('-', '+').Replace('_', '/');

        if (!string.Equals(standard, proof.PublicKey, StringComparison.Ordinal))
        {
            Assert.Equal(SeatKeyRejection.Encoding, Verifier.ParseAndVerify([proof with { PublicKey = standard }], challenge, Install).Rejection);
        }

        // Fullwidth 'A' (U+FF21) and Arabic-Indic digit zero keep the length but are outside the alphabet.
        Assert.Equal(SeatKeyRejection.Encoding, Verifier.ParseAndVerify([proof with { PublicKey = "Ａ" + proof.PublicKey[1..] }], challenge, Install).Rejection);
        Assert.Equal(SeatKeyRejection.Encoding, Verifier.ParseAndVerify([proof with { Signature = "٠" + proof.Signature[1..] }], challenge, Install).Rejection);
    }

    [Fact]
    public void ParseAndVerifyNeverThrowOnRandomInput()
    {
        var random = new Random(182);
        const string Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_+/= ٠";
        var challenge = Restore();
        for (var i = 0; i < 2000; i++)
        {
            string Text(int length) => new([.. Enumerable.Range(0, length).Select(_ => Alphabet[random.Next(Alphabet.Length)])]);
            var key = random.Next(4) == 0 ? "BA" + Text(85) : Text(random.Next(80, 92));
            var signature = Text(random.Next(80, 92));
            var result = Verifier.ParseAndVerify([new SeatKeyProofInput(key, signature)], challenge, Install);
            Assert.False(result.IsValid);
        }
    }

    [Fact]
    public void ParseRecordsARejectionButAValidParseIsCountedOnlyByVerify()
    {
        using var signer = new SeatKeyTestSigner();
        var challenge = Restore();

        var parsed = Verifier.Parse(SeatOp.Restore, [signer.Prove(challenge, Install)]);
        Assert.True(parsed.IsValid);
        Assert.Empty(metrics.Proofs);

        _ = Verifier.Verify(parsed.Keys, challenge, Install);
        _ = Verifier.Parse(SeatOp.Restore, []);
        Assert.Equal([(SeatOp.Restore, "valid"), (SeatOp.Restore, "empty")], metrics.Proofs);
    }

    [Fact]
    public void AChallengeOfAnotherOpIsACallerBug()
    {
        using var signer = new SeatKeyTestSigner();
        var parsed = Verifier.Parse(SeatOp.Restore, [signer.Prove(Restore(), Install)]);

        var error = Assert.Throws<ArgumentException>(() => Verifier.Verify(parsed.Keys!, For(SeatOp.SignIn), Install));
        Assert.DoesNotContain(signer.PublicKey, error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void TheDigestCoversThePointsInRequestOrder()
    {
        using var a = new SeatKeyTestSigner();
        using var b = new SeatKeyTestSigner();
        var challenge = Restore();
        var pa = a.Prove(challenge, Install);
        var pb = b.Prove(challenge, Install);

        var ab = Verifier.ParseAndVerify([pa, pb], challenge, Install).Keys!;
        var ba = Verifier.Parse(SeatOp.Restore, [pb, pa]).Keys!;

        Assert.Equal(System.Security.Cryptography.SHA256.HashData([.. a.PublicPoint, .. b.PublicPoint]), ab.Digest());
        Assert.NotEqual(ab.Digest(), ba.Digest());
        Assert.Equal(Convert.FromHexString("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"), SeatKeysDigest.Empty);
    }

    [Fact]
    public void ChallengeFactoriesHashTheirInputs()
    {
        Assert.Equal(System.Security.Cryptography.SHA256.HashData("tx.payload.sig"u8), SeatChallenge.ForVerify("tx.payload.sig").ToArray());
        Assert.Equal(System.Security.Cryptography.SHA256.HashData("nonce-1"u8), SeatChallenge.ForSignIn("nonce-1").ToArray());
        Assert.Equal(SeatOp.Verify, SeatChallenge.ForVerify("x").Op);
        Assert.Equal(SeatOp.SignIn, SeatChallenge.ForSignIn("x").Op);
        Assert.Throws<ArgumentException>(() => SeatChallenge.ForRestore(new byte[31]));
        Assert.Throws<ArgumentException>(() => SeatChallenge.ForRestore(new byte[33]));
        Assert.Throws<ArgumentException>(() => SeatChallenge.ForSignIn("nönce"));

        var bytes = Enumerable.Repeat((byte)7, 32).ToArray();
        var restore = SeatChallenge.ForRestore(bytes);
        bytes[0] = 8;
        Assert.Equal(7, restore.ToArray()[0]);
    }

    [Fact]
    public void WireLiteralsAndLimitsArePinned()
    {
        Assert.Equal(["verify", "restore", "signin"], Enum.GetValues<SeatOp>().Select(SeatOps.Wire));
        Assert.Equal([1, 5, 5], Enum.GetValues<SeatOp>().Select(SeatOps.MaxKeys));
        Assert.Equal(
            ["empty", "too_many", "encoding", "bad_point", "duplicate", "bad_signature"],
            Enum.GetValues<SeatKeyRejection>().Select(r => SeatKeyTags.Result(r)));
        Assert.Equal(SeatKeyTags.Results, ["valid", .. Enum.GetValues<SeatKeyRejection>().Select(r => SeatKeyTags.Result(r))]);
    }
}
