using System.Formats.Cbor;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Logging.Abstractions;
using Zaghlol.Application.Purchases.Attestation;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Attestation;
using Zaghlol.Infrastructure.Tests.Seats;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Attestation;

/// <summary>T-181 App Attest attestation and assertion rules, over the test signer and an in-memory key store.</summary>
public sealed class AppAttestVerifierTests : IDisposable
{
    private static readonly byte[] ClientDataHash = SHA256.HashData("client data"u8);
    private readonly AppAttestTestSigner signer = new();
    private readonly InMemoryAppAttestKeyStore store = new();
    private readonly InstallId install = SeatDb.NewInstallId();

    public void Dispose() => signer.Dispose();

    [Fact]
    public async Task AValidAttestationRegistersTheKeyToTheCallingInstall()
    {
        using var key = AppAttestTestSigner.NewKey();
        var result = await Verifier().RegisterAttestationAsync(store, install, key.KeyId, signer.Attest(key, ClientDataHash), ClientDataHash, default);

        Assert.True(result.IsVerified);
        var row = store.Rows[install.Value];
        Assert.Equal(key.KeyId, row.KeyId);
        Assert.Equal(key.Point, row.PublicKey);
        Assert.Equal(0, row.SignCount);
    }

    /// <summary>Core safety property (negative proof 1): a chain not rooted in the configured root is refused.</summary>
    [Fact]
    public async Task AChainUnderAnotherRootIsRefused()
    {
        using var forger = new AppAttestTestSigner(rootSubject: "CN=Zaghlol Test App Attestation Root CA, O=Zaghlol Tests, C=EG");
        using var key = AppAttestTestSigner.NewKey();

        var result = await Verifier().RegisterAttestationAsync(store, install, key.KeyId, forger.Attest(key, ClientDataHash), ClientDataHash, default);

        Assert.Equal(AttestationFailure.Chain, result.Failure);
        Assert.Empty(store.Rows);
    }

    [Fact]
    public async Task ATestChainIsRefusedByThePinnedAppleRoot()
    {
        using var key = AppAttestTestSigner.NewKey();
        var pinned = new AppAttestVerifier(new AppAttestOptions { AppId = AppAttestTestSigner.AppId }, TimeProvider.System, NullLogger<AppAttestVerifier>.Instance);

        var result = await pinned.RegisterAttestationAsync(store, install, key.KeyId, signer.Attest(key, ClientDataHash), ClientDataHash, default);

        Assert.Equal(AttestationFailure.Chain, result.Failure);
    }

    /// <summary>Core safety property (negative proof 2): an attestation made over another clientDataHash is refused.</summary>
    [Fact]
    public async Task AWrongNonceIsRefused()
    {
        using var key = AppAttestTestSigner.NewKey();
        var other = SHA256.HashData("another body"u8);

        var overOther = await Verifier().RegisterAttestationAsync(store, install, key.KeyId, signer.Attest(key, other), ClientDataHash, default);
        var forgedNonce = await Verifier().RegisterAttestationAsync(store, install, key.KeyId, signer.Attest(key, ClientDataHash, nonceOverride: new byte[32]), ClientDataHash, default);

        Assert.Equal(AttestationFailure.HashMismatch, overOther.Failure);
        Assert.Equal(AttestationFailure.HashMismatch, forgedNonce.Failure);
        Assert.Empty(store.Rows);
    }

    [Fact]
    public async Task AWrongRpIdIsRefused()
    {
        using var key = AppAttestTestSigner.NewKey();
        var result = await Verifier().RegisterAttestationAsync(
            store, install, key.KeyId, signer.Attest(key, ClientDataHash, appId: "TESTTEAM00.app.other"), ClientDataHash, default);
        Assert.Equal(AttestationFailure.AppUnrecognized, result.Failure);
    }

    [Fact]
    public async Task ANonZeroCounterIsRefused()
    {
        using var key = AppAttestTestSigner.NewKey();
        var result = await Verifier().RegisterAttestationAsync(store, install, key.KeyId, signer.Attest(key, ClientDataHash, counter: 1), ClientDataHash, default);
        Assert.Equal(AttestationFailure.Counter, result.Failure);
    }

    [Fact]
    public async Task TheDevelopmentAaguidIsRefusedUnlessTheEnvironmentAllowsIt()
    {
        using var key = AppAttestTestSigner.NewKey();
        var attestation = signer.Attest(key, ClientDataHash, aaguid: AppAttestTestSigner.DevelopmentAaguid);

        var production = await Verifier().RegisterAttestationAsync(store, install, key.KeyId, attestation, ClientDataHash, default);
        var staging = await Verifier(allowDevelopment: true).RegisterAttestationAsync(store, install, key.KeyId, attestation, ClientDataHash, default);
        var unknown = await Verifier(allowDevelopment: true).RegisterAttestationAsync(
            store, install, key.KeyId, signer.Attest(key, ClientDataHash, aaguid: [.. "appattestXXXXXXX"u8]), ClientDataHash, default);

        Assert.Equal(AttestationFailure.AppUnrecognized, production.Failure);
        Assert.True(staging.IsVerified);
        Assert.Equal(AttestationFailure.AppUnrecognized, unknown.Failure);
    }

    [Fact]
    public async Task AKeyIdThatIsNotTheCredentialKeyIsRefused()
    {
        using var key = AppAttestTestSigner.NewKey();
        using var other = AppAttestTestSigner.NewKey();

        var wrongClaim = await Verifier().RegisterAttestationAsync(store, install, other.KeyId, signer.Attest(key, ClientDataHash), ClientDataHash, default);
        var wrongCredential = await Verifier().RegisterAttestationAsync(
            store, install, key.KeyId, signer.Attest(key, ClientDataHash, credentialIdOverride: other.KeyId), ClientDataHash, default);

        Assert.Equal(AttestationFailure.Chain, wrongClaim.Failure);
        Assert.Equal(AttestationFailure.Chain, wrongCredential.Failure);
    }

    [Fact]
    public async Task AKeyRegisteredToAnotherInstallIsRefused()
    {
        using var key = AppAttestTestSigner.NewKey();
        var other = SeatDb.NewInstallId();
        Assert.True((await Verifier().RegisterAttestationAsync(store, other, key.KeyId, signer.Attest(key, ClientDataHash), ClientDataHash, default)).IsVerified);

        var result = await Verifier().RegisterAttestationAsync(store, install, key.KeyId, signer.Attest(key, ClientDataHash), ClientDataHash, default);

        Assert.Equal(AttestationFailure.KeyUnknown, result.Failure);
        Assert.False(store.Rows.ContainsKey(install.Value));
    }

    [Fact]
    public async Task AReplayedAttestationForTheSameKeyKeepsTheCounter()
    {
        using var key = AppAttestTestSigner.NewKey();
        var attestation = signer.Attest(key, ClientDataHash);
        await Verifier().RegisterAttestationAsync(store, install, key.KeyId, attestation, ClientDataHash, default);
        Assert.True((await Verifier().VerifyAssertionAsync(store, install, key.KeyId, AppAttestTestSigner.Assert(key, ClientDataHash, 5), ClientDataHash, default)).IsVerified);

        Assert.True((await Verifier().RegisterAttestationAsync(store, install, key.KeyId, attestation, ClientDataHash, default)).IsVerified);

        Assert.Equal(5, store.Rows[install.Value].SignCount);
        var replayed = await Verifier().VerifyAssertionAsync(store, install, key.KeyId, AppAttestTestSigner.Assert(key, ClientDataHash, 5), ClientDataHash, default);
        Assert.Equal(AttestationFailure.Counter, replayed.Failure);
    }

    [Fact]
    public async Task ReAttestingWithANewKeyReplacesTheOldOne()
    {
        using var first = AppAttestTestSigner.NewKey();
        using var second = AppAttestTestSigner.NewKey();
        await Verifier().RegisterAttestationAsync(store, install, first.KeyId, signer.Attest(first, ClientDataHash), ClientDataHash, default);
        await Verifier().RegisterAttestationAsync(store, install, second.KeyId, signer.Attest(second, ClientDataHash), ClientDataHash, default);

        Assert.Equal(second.KeyId, store.Rows[install.Value].KeyId);
        var old = await Verifier().VerifyAssertionAsync(store, install, first.KeyId, AppAttestTestSigner.Assert(first, ClientDataHash, 1), ClientDataHash, default);
        Assert.Equal(AttestationFailure.KeyUnknown, old.Failure);
    }

    [Theory]
    [InlineData("empty")]
    [InlineData("garbage")]
    [InlineData("oversized")]
    [InlineData("extra-member")]
    [InlineData("wrong-fmt")]
    public async Task AMalformedAttestationIsRefused(string shape)
    {
        using var key = AppAttestTestSigner.NewKey();
        var bytes = shape switch
        {
            "empty" => [],
            "garbage" => RandomNumberGenerator.GetBytes(300),
            "oversized" => new byte[AppAttestVerifier.MaxAttestationBytes + 1],
            "extra-member" => Map(("fmt", "apple-appattest"), ("attStmt", "x"), ("authData", "x"), ("extra", "x")),
            _ => Map(("fmt", "packed"), ("attStmt", "x"), ("authData", "x")),
        };

        var result = await Verifier().RegisterAttestationAsync(store, install, key.KeyId, bytes, ClientDataHash, default);

        Assert.Equal(AttestationFailure.Chain, result.Failure);
    }

    [Fact]
    public async Task AValidAssertionPassesAndRaisesTheCounter()
    {
        using var key = await RegisteredKeyAsync();

        var result = await Verifier().VerifyAssertionAsync(store, install, key.KeyId, AppAttestTestSigner.Assert(key, ClientDataHash, 3), ClientDataHash, default);

        Assert.True(result.IsVerified);
        Assert.Equal(3, store.Rows[install.Value].SignCount);
    }

    [Theory]
    [InlineData(0u)]
    [InlineData(2u)]
    public async Task ACounterThatDoesNotIncreaseFails(uint counter)
    {
        using var key = await RegisteredKeyAsync();
        await Verifier().VerifyAssertionAsync(store, install, key.KeyId, AppAttestTestSigner.Assert(key, ClientDataHash, 2), ClientDataHash, default);

        var result = await Verifier().VerifyAssertionAsync(store, install, key.KeyId, AppAttestTestSigner.Assert(key, ClientDataHash, counter), ClientDataHash, default);

        Assert.Equal(AttestationFailure.Counter, result.Failure);
        Assert.Equal(2, store.Rows[install.Value].SignCount);
    }

    [Fact]
    public async Task AKeyOfAnotherInstallFails()
    {
        using var key = await RegisteredKeyAsync();
        var other = SeatDb.NewInstallId();
        using var otherKey = AppAttestTestSigner.NewKey();
        await Verifier().RegisterAttestationAsync(store, other, otherKey.KeyId, signer.Attest(otherKey, ClientDataHash), ClientDataHash, default);

        // Install `other` presents install's key ID and an assertion made with install's key.
        var foreign = await Verifier().VerifyAssertionAsync(store, other, key.KeyId, AppAttestTestSigner.Assert(key, ClientDataHash, 1), ClientDataHash, default);
        var none = await Verifier().VerifyAssertionAsync(store, SeatDb.NewInstallId(), key.KeyId, AppAttestTestSigner.Assert(key, ClientDataHash, 1), ClientDataHash, default);

        Assert.Equal(AttestationFailure.KeyUnknown, foreign.Failure);
        Assert.Equal(AttestationFailure.KeyUnknown, none.Failure);
        Assert.Equal(0, store.Rows[install.Value].SignCount);
    }

    [Fact]
    public async Task AnAssertionOverADifferentClientDataHashFails()
    {
        using var key = await RegisteredKeyAsync();
        var signed = AppAttestTestSigner.Assert(key, ClientDataHash, 1);

        var result = await Verifier().VerifyAssertionAsync(store, install, key.KeyId, signed, SHA256.HashData("one seat key changed"u8), default);

        Assert.Equal(AttestationFailure.HashMismatch, result.Failure);
        Assert.Equal(0, store.Rows[install.Value].SignCount);
    }

    [Fact]
    public async Task AnAssertionForAnotherAppFails()
    {
        using var key = await RegisteredKeyAsync();
        var result = await Verifier().VerifyAssertionAsync(
            store, install, key.KeyId, AppAttestTestSigner.Assert(key, ClientDataHash, 1, appId: "TESTTEAM00.app.other"), ClientDataHash, default);
        Assert.Equal(AttestationFailure.AppUnrecognized, result.Failure);
    }

    /// <summary>
    /// R4-1(3): the vector's clientDataHash is reproduced from bodyHash and the seat keys; an assertion over it verifies, and the
    /// same assertion checked against the hash of the reordered seat keys (what a relay would produce) fails.
    /// </summary>
    [Fact]
    public async Task RestoreBindingVectorAssertionVerifiesAndReorderedSeatKeysFail()
    {
        var vector = JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "vectors", "restore-binding-v1.json")))!["valid"]!
            .AsArray().Single(v => (string)v!["name"]! == "ios-two-seat-keys")!;
        var bodyHash = Convert.FromHexString((string)vector["bodyHashHex"]!);
        var points = vector["body"]!["attestation"]!["seatKeys"]!.AsArray().Select(k => Base64Url((string)k!["publicKey"]!)).ToArray();
        var expected = Convert.FromHexString((string)vector["clientDataHashHex"]!);
        Assert.Equal(expected, RestoreClientDataHash(bodyHash, points));
        var reordered = RestoreClientDataHash(bodyHash, [points[1], points[0]]);

        using var key = AppAttestTestSigner.NewKey();
        var attest = await Verifier().RegisterAttestationAsync(store, install, key.KeyId, signer.Attest(key, expected), expected, default);
        var good = await Verifier().VerifyAssertionAsync(store, install, key.KeyId, AppAttestTestSigner.Assert(key, expected, 1), expected, default);
        var relayed = await Verifier().VerifyAssertionAsync(store, install, key.KeyId, AppAttestTestSigner.Assert(key, expected, 2), reordered, default);

        Assert.True(attest.IsVerified);
        Assert.True(good.IsVerified);
        Assert.Equal(AttestationFailure.HashMismatch, relayed.Failure);
    }

    /// <summary>
    /// A real Apple production attestation (public MIT fixture, see the file) verifies against the pinned Apple App Attestation
    /// Root CA at its own issue time, and fails a different clientDataHash or App ID.
    /// </summary>
    [Fact]
    public void ARealAppleAttestationVerifiesUnderThePinnedRoot()
    {
        var fixture = JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Attestation", "fixtures", "apple-appattest-production.json")))!;
        var attestation = Convert.FromBase64String((string)fixture["attestation"]!);
        var keyId = Convert.FromBase64String((string)fixture["keyId"]!);
        var clientDataHash = SHA256.HashData(Convert.FromBase64String((string)fixture["challenge"]!));
        var appId = (string)fixture["teamId"]! + "." + (string)fixture["bundleId"]!;
        var at = new ManualTime(LeafNotBefore(attestation).AddMinutes(1));

        var real = new AppAttestVerifier(new AppAttestOptions { AppId = appId }, at, NullLogger<AppAttestVerifier>.Instance);
        Assert.Null(real.CheckAttestation(keyId, attestation, clientDataHash, out var publicKey, out var development));
        Assert.False(development);
        Assert.Equal(keyId, SHA256.HashData(publicKey!));

        Assert.Equal(AttestationFailure.HashMismatch, real.CheckAttestation(keyId, attestation, SHA256.HashData("x"u8), out _, out _));
        var otherApp = new AppAttestVerifier(new AppAttestOptions { AppId = "V8H6LQ9448.app.zaghlol" }, at, NullLogger<AppAttestVerifier>.Instance);
        Assert.Equal(AttestationFailure.AppUnrecognized, otherApp.CheckAttestation(keyId, attestation, clientDataHash, out _, out _));
        var expired = new AppAttestVerifier(new AppAttestOptions { AppId = appId }, new ManualTime(at.Now.AddYears(1)), NullLogger<AppAttestVerifier>.Instance);
        Assert.Equal(AttestationFailure.Chain, expired.CheckAttestation(keyId, attestation, clientDataHash, out _, out _));
    }

    [Fact]
    public void ThePinnedRootMatchesItsFingerprintAndAWrongResourceIsRefused()
    {
        using var root = X509CertificateLoader.LoadCertificate(AppAttestRootCertificate.Der);
        Assert.Contains("CN=Apple App Attestation Root CA", root.Subject, StringComparison.Ordinal);
        Assert.Equal("0BF3BE0EF1CDD2E0FB8C6E721F621798", root.SerialNumber);
        Assert.Throws<AttestationConfigurationException>(() => AppAttestRootCertificate.Load(new MemoryStream(signer.RootDer), AppAttestRootCertificate.Sha256Fingerprint));
        Assert.Throws<AttestationConfigurationException>(() => AppAttestRootCertificate.Load(null, AppAttestRootCertificate.Sha256Fingerprint));
    }

    /// <summary>Log sentinel: failures log the reason code only, never a key ID, assertion, attestation object or hash.</summary>
    [Fact]
    public async Task FailuresLogTheReasonCodeOnly()
    {
        var logs = new CapturingLogger();
        var verifier = new AppAttestVerifier(
            new AppAttestOptions { AppId = AppAttestTestSigner.AppId, TestRoot = signer.RootDer }, TimeProvider.System, logs);
        using var key = AppAttestTestSigner.NewKey();
        var attestation = signer.Attest(key, ClientDataHash, counter: 9);
        var assertion = AppAttestTestSigner.Assert(key, ClientDataHash, 1);

        await verifier.RegisterAttestationAsync(store, install, key.KeyId, attestation, ClientDataHash, default);
        await verifier.VerifyAssertionAsync(store, install, key.KeyId, assertion, ClientDataHash, default);

        Assert.Equal(["attestation_failed provider=app_attest reason=counter", "attestation_failed provider=app_attest reason=key_unknown"], logs.Lines);
        var haystack = string.Join('\n', logs.Lines);
        foreach (var bytes in new[] { key.KeyId, attestation[..40], assertion[..40], ClientDataHash, key.Point })
        {
            Assert.DoesNotContain(Convert.ToHexString(bytes)[..16], haystack, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain(Convert.ToBase64String(bytes)[..16], haystack, StringComparison.Ordinal);
        }
    }

    internal static byte[] RestoreClientDataHash(byte[] bodyHash, IEnumerable<byte[]> seatKeys)
    {
        var digest = SHA256.HashData(seatKeys.SelectMany(k => k).ToArray());
        return SHA256.HashData([.. Encoding.ASCII.GetBytes("zaghlol-restore-attest-v1"), 0, .. bodyHash, .. digest]);
    }

    private static byte[] Base64Url(string text) =>
        Convert.FromBase64String(text.Replace('-', '+').Replace('_', '/') + new string('=', (4 - (text.Length % 4)) % 4));

    private static DateTimeOffset LeafNotBefore(byte[] attestation)
    {
        var reader = new CborReader(attestation);
        reader.ReadStartMap();
        while (true)
        {
            if (reader.ReadTextString() != "attStmt")
            {
                reader.SkipValue();
                continue;
            }

            reader.ReadStartMap();
            while (reader.ReadTextString() != "x5c")
            {
                reader.SkipValue();
            }

            reader.ReadStartArray();
            using var leaf = X509CertificateLoader.LoadCertificate(reader.ReadByteString());
            return new DateTimeOffset(leaf.NotBefore.ToUniversalTime(), TimeSpan.Zero);
        }
    }

    private static byte[] Map(params (string Key, string Value)[] members)
    {
        var writer = new CborWriter();
        writer.WriteStartMap(members.Length);
        foreach (var (k, v) in members)
        {
            writer.WriteTextString(k);
            writer.WriteTextString(v);
        }

        writer.WriteEndMap();
        return writer.Encode();
    }

    private AppAttestVerifier Verifier(bool allowDevelopment = false) =>
        new(new AppAttestOptions { AppId = AppAttestTestSigner.AppId, AllowDevelopment = allowDevelopment, TestRoot = signer.RootDer }, TimeProvider.System, NullLogger<AppAttestVerifier>.Instance);

    private async Task<AppAttestTestKey> RegisteredKeyAsync()
    {
        var key = AppAttestTestSigner.NewKey();
        Assert.True((await Verifier().RegisterAttestationAsync(store, install, key.KeyId, signer.Attest(key, ClientDataHash), ClientDataHash, default)).IsVerified);
        return key;
    }
}

/// <summary>Collects formatted log lines and their structured values.</summary>
internal sealed class CapturingLogger : Microsoft.Extensions.Logging.ILogger<AppAttestVerifier>
{
    public List<string> Lines { get; } = [];

    public IDisposable? BeginScope<TState>(TState state)
        where TState : notnull => null;

    public bool IsEnabled(Microsoft.Extensions.Logging.LogLevel logLevel) => true;

    public void Log<TState>(
        Microsoft.Extensions.Logging.LogLevel logLevel,
        Microsoft.Extensions.Logging.EventId eventId,
        TState state,
        Exception? exception,
        Func<TState, Exception?, string> formatter)
    {
        ArgumentNullException.ThrowIfNull(formatter);
        Lines.Add(formatter(state, exception));
    }
}
