using System.Buffers.Text;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json.Nodes;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.AppStore;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.AppStore;

/// <summary>
/// T-131 design note §2 and AC 1 ("unit tests with Apple test vectors"): the in-house verifier against synthetic vectors signed at
/// test time by a test PKI shaped like Apple's, plus the real pinned root.
/// </summary>
public sealed class AppleJwsVerifierTests : IDisposable
{
    private static readonly DateTimeOffset Now = DateTimeOffset.UtcNow;

    private readonly AppleTestPki pki = AppleTestPki.Create();

    private AppleJwsVerifier Verifier => new(pki.RootDer);

    public void Dispose() => pki.Dispose();

    [Fact]
    public void AGenuineTransactionVerifiesAndOnlyTheReadFieldsComeBack()
    {
        var install = InstallId.FromGuid(Guid.NewGuid());
        var payload = AppleTestPki.Transaction("app.zaghlol", "zaghlol_gold_yearly", "2000000123456789", "2000000123456700", StoreBindingRef.Compute(install), "Sandbox");

        var transaction = Verifier.VerifyTransaction(Jws(pki.Sign(payload)), JwsSource.Api, Now);

        Assert.Equal("app.zaghlol", transaction.BundleId);
        Assert.Equal(AppleEnvironment.Sandbox, transaction.Environment);
        Assert.Equal(AppleProductType.AutoRenewable, transaction.Type);
        Assert.Equal("2000000123456789", transaction.TransactionId!.Value.Reveal());
        Assert.Equal("2000000123456700", transaction.OriginalTransactionId!.Value.Reveal());
        Assert.True(StoreBindingRef.MatchesAppAccountToken(transaction.AppAccountToken?.Reveal(), install));
        Assert.Equal(AppleOwnershipType.Purchased, transaction.OwnershipType);
        Assert.Equal(AppleTransactionReason.Purchase, transaction.Reason);
        Assert.NotNull(transaction.ExpiresDate);
        Assert.Null(transaction.RevocationDate);
        Assert.DoesNotContain("2000000123456789", transaction.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void RenewalInfoVerifies()
    {
        var renewal = Verifier.VerifyRenewalInfo(Jws(pki.Sign(AppleTestPki.Renewal("2000000123456700", "zaghlol_gold_yearly", 0, gracePeriodExpiresDate: Now.AddDays(3)))), JwsSource.Api, Now);

        Assert.Equal(0, renewal.AutoRenewStatus);
        Assert.Equal(AppleEnvironment.Production, renewal.Environment);
        Assert.NotNull(renewal.GracePeriodExpiresDate);
    }

    // AC 1: every tampering is refused, each for its own reason.

    [Fact]
    public void AFlippedPayloadByteIsASignatureFailure()
    {
        var parts = pki.Sign(Payload()).Split('.');
        var payload = Encoding.UTF8.GetString(Base64Url.DecodeFromChars(parts[1])).Replace("zaghlol_gold_yearly", "zaghlol_gold_yearlz", StringComparison.Ordinal);

        AssertFails(parts[0] + "." + AppleTestPki.B64Url(payload) + "." + parts[2], AppleJwsFailure.Signature);
    }

    [Fact]
    public void AFlippedSignatureByteIsASignatureFailure()
    {
        var parts = pki.Sign(Payload()).Split('.');
        var signature = Base64Url.DecodeFromChars(parts[2]);
        signature[10] ^= 0x01;

        AssertFails(parts[0] + "." + parts[1] + "." + AppleTestPki.B64Url(signature), AppleJwsFailure.Signature);
    }

    [Fact]
    public void ADerEncodedSignatureIsRefused()
    {
        var parts = pki.Sign(Payload()).Split('.');
        var der = pki.LeafKey.SignData(Encoding.ASCII.GetBytes(parts[0] + "." + parts[1]), HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence);

        AssertFails(parts[0] + "." + parts[1] + "." + AppleTestPki.B64Url(der), AppleJwsFailure.Signature);
    }

    [Theory]
    [InlineData("none")]
    [InlineData("HS256")]
    [InlineData("ES384")]
    [InlineData("es256")]
    public void AnyAlgorithmButEs256IsRefused(string alg)
    {
        var header = pki.Header();
        header["alg"] = alg;

        AssertFails(pki.Sign(Payload(), header), AppleJwsFailure.Alg);
    }

    [Theory]
    [InlineData("jwk")]
    [InlineData("jku")]
    [InlineData("x5u")]
    [InlineData("kid")]
    [InlineData("crit")]
    public void AKeyLocatorOrCriticalHeaderIsRefused(string member)
    {
        var header = pki.Header();
        header[member] = member == "jwk" ? new JsonObject { ["kty"] = "EC" } : "x";

        AssertFails(pki.Sign(Payload(), header), AppleJwsFailure.Alg);
    }

    [Theory]
    [InlineData(2)]
    [InlineData(4)]
    [InlineData(0)]
    public void AChainOfAnyLengthButThreeIsRefused(int count)
    {
        var header = pki.Header();
        var certs = new[] { pki.LeafDer, pki.IntermediateDer, pki.RootDer, pki.RootDer }.Take(count).Select(c => (JsonNode)Convert.ToBase64String(c));
        header["x5c"] = new JsonArray([.. certs]);

        AssertFails(pki.Sign(Payload(), header), AppleJwsFailure.Chain);
    }

    [Fact]
    public void ALeafWithoutAppleMarkerIsRefused()
    {
        using var forged = AppleTestPki.Create(leafOid: false);

        AssertFails(new AppleJwsVerifier(forged.RootDer), forged.Sign(Payload()), AppleJwsFailure.Oid);
    }

    [Fact]
    public void AnIntermediateWithoutAppleMarkerIsRefused()
    {
        using var forged = AppleTestPki.Create(intermediateOid: false);

        AssertFails(new AppleJwsVerifier(forged.RootDer), forged.Sign(Payload()), AppleJwsFailure.Oid);
    }

    [Fact]
    public void ALeafKeyThatIsNotP256IsRefused()
    {
        using var forged = AppleTestPki.Create(leafCurve: ECCurve.NamedCurves.nistP384);
        var header = forged.Header();
        var input = AppleTestPki.B64Url(header.ToJsonString()) + "." + AppleTestPki.B64Url(Payload().ToJsonString());
        var signature = forged.LeafKey.SignData(Encoding.ASCII.GetBytes(input), HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);

        AssertFails(new AppleJwsVerifier(forged.RootDer), input + "." + AppleTestPki.B64Url(signature), AppleJwsFailure.Oid);
    }

    [Fact]
    public void ASelfMadeRootWithThePinnedRootsSubjectIsRefused()
    {
        using var pinnedRoot = X509CertificateLoader.LoadCertificate(pki.RootDer);
        using var forged = AppleTestPki.Create(rootSubject: pinnedRoot.Subject);

        AssertFails(forged.Sign(Payload()), AppleJwsFailure.Chain);

        // Even with the genuine root bytes in x5c[2], the forged intermediate doesn't chain to it.
        var header = forged.Header();
        header["x5c"]![2] = Convert.ToBase64String(pki.RootDer);
        AssertFails(forged.Sign(Payload(), header), AppleJwsFailure.Chain);
    }

    [Fact]
    public void ATestPkiJwsNeverPassesTheRealPinnedAppleRoot()
    {
        var verifier = new AppleJwsVerifier(AppleRootCertificate.Der);

        AssertFails(verifier, pki.Sign(Payload()), AppleJwsFailure.Chain);
    }

    [Fact]
    public void DuplicateJsonMembersAreMalformed()
    {
        var header = pki.Header().ToJsonString();
        var payload = Payload().ToJsonString();
        var duplicatePayload = payload[..^1] + ",\"bundleId\":\"com.example.other\"}";
        var duplicateHeader = header[..^1] + ",\"alg\":\"ES256\"}";

        AssertFails(pki.Sign(header, duplicatePayload), AppleJwsFailure.Malformed);
        AssertFails(pki.Sign(duplicateHeader, payload), AppleJwsFailure.Malformed);
    }

    [Fact]
    public void AnOverlongJwsIsRefusedBeforeAnyDecode()
    {
        var text = new string('A', AppleJwsVerifier.MaxLength - 4) + ".A.A";
        Assert.Equal(AppleJwsVerifier.MaxLength, text.Length);

        AssertFails(text + "A", AppleJwsFailure.Malformed);
    }

    [Theory]
    [InlineData("")]
    [InlineData("a.b")]
    [InlineData("a.b.c.d")]
    [InlineData("eyJhbGciOiJFUzI1NiJ9.e30.")]
    [InlineData("eyJhbGciOiJFUzI1NiJ9=.e30.c2ln")]
    [InlineData("eyJhbGciOiJFUzI1NiJ9 .e30.c2ln")]
    [InlineData("eyJhbGciOiJFUzI1NiJ9.e30+.c2ln")]
    [InlineData("WzFd.e30.c2ln")]
    public void ShapeErrorsAreMalformed(string text) => AssertFails(text, AppleJwsFailure.Malformed);

    [Fact]
    public void ANonCanonicalBase64UrlSegmentIsMalformed()
    {
        var parts = pki.Sign(Payload()).Split('.');

        // "e31" decodes like "e30" when the stray low bits are ignored; strict decoding refuses it.
        AssertFails(parts[0] + "." + parts[1] + "." + parts[2][..^1] + Flip(parts[2][^1]), AppleJwsFailure.Malformed, AppleJwsFailure.Signature);
    }

    [Fact]
    public void UnreadablePayloadFieldsArePayloadFailures()
    {
        var payload = Payload();
        payload["purchaseDate"] = "yesterday";

        AssertFails(pki.Sign(payload), AppleJwsFailure.Payload);
    }

    // §2 step 6: the validation time.

    [Fact]
    public void AnAppJwsUnderAnIntermediateThatHasSinceExpiredVerifiesAtItsSignedDateButNotAtNow()
    {
        using var old = AppleTestPki.Create(intermediateNotAfter: Now.AddDays(-30));
        var verifier = new AppleJwsVerifier(old.RootDer);
        var jws = old.Sign(Payload(signedDate: Now.AddDays(-40)));

        var transaction = verifier.VerifyTransaction(Jws(jws), JwsSource.App, Now);
        Assert.Equal(AppleTestPki.Ms(Now.AddDays(-40)), transaction.SignedDate.ToUnixTimeMilliseconds());

        // Apple's own API answers are validated at now: the same chain is refused.
        AssertFails(verifier, jws, AppleJwsFailure.Chain, source: JwsSource.Api);
    }

    [Fact]
    public void AnAppJwsSignedInTheFutureOrWithoutASignedDateIsRefused()
    {
        AssertFails(pki.Sign(Payload(signedDate: Now.AddMinutes(6))), AppleJwsFailure.Payload, source: JwsSource.App);
        Assert.NotNull(Verifier.VerifyTransaction(Jws(pki.Sign(Payload(signedDate: Now.AddMinutes(4)))), JwsSource.App, Now));

        var unsigned = Payload();
        unsigned.Remove("signedDate");
        AssertFails(pki.Sign(unsigned), AppleJwsFailure.Payload, source: JwsSource.App);
    }

    [Fact]
    public void AnAppJwsBackdatedBeforeTheChainWasValidIsRefused()
    {
        AssertFails(pki.Sign(Payload(signedDate: Now.AddYears(-20))), AppleJwsFailure.Chain, source: JwsSource.App);
    }

    [Fact]
    public void TheExceptionNeverCarriesTheJws()
    {
        var parts = pki.Sign(Payload()).Split('.');
        var error = Assert.Throws<AppleJwsException>(() => Verifier.VerifyTransaction(Jws(parts[0] + "." + parts[1] + ".AAAA"), JwsSource.Api, Now));

        Assert.DoesNotContain(parts[1], error.ToString(), StringComparison.Ordinal);
        Assert.Equal(AppleJwsException.DefaultMessage, error.Message);
    }

    private static JsonObject Payload(DateTimeOffset? signedDate = null) =>
        AppleTestPki.Transaction("app.zaghlol", "zaghlol_gold_yearly", "2000000123456789", "2000000123456700", null, signedDate: signedDate);

    private static Sensitive<string> Jws(string text) => new(text);

    private static char Flip(char c) => c == 'A' ? 'B' : 'A';

    private void AssertFails(string jws, AppleJwsFailure expected, AppleJwsFailure? alternative = null, JwsSource source = JwsSource.Api) =>
        AssertFails(Verifier, jws, expected, alternative, source);

    private static void AssertFails(AppleJwsVerifier verifier, string jws, AppleJwsFailure expected, AppleJwsFailure? alternative = null, JwsSource source = JwsSource.Api)
    {
        var error = Assert.Throws<AppleJwsException>(() => verifier.VerifyTransaction(Jws(jws), source, Now));
        Assert.True(error.Reason == expected || error.Reason == alternative, $"expected {expected}, got {error.Reason}");
    }
}
