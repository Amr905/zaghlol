using System.Diagnostics;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Seats;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>
/// T-201 acceptance 1, 2 and 4 against the in-process OpenBao (<see cref="OpenBaoStub"/>): the adapter serves every port
/// after the migration, keeps the T-200 hashes and envelopes valid, pins key versions, maps outages to
/// <see cref="KmsUnavailableException"/> (503) without ever turning a doubt into "undecryptable", and refuses to start on
/// each guard of the design note §6 without leaking a credential or a key.
/// </summary>
[SupportedOSPlatform("linux")]
public sealed class OpenBaoKmsTests : IAsyncLifetime
{
    private OpenBaoTestBed bed = null!;

    public async Task InitializeAsync() => bed = await OpenBaoTestBed.CreateAsync();

    public async Task DisposeAsync() => await bed.DisposeAsync();

    [LinuxTheory]
    [InlineData("Staging")]
    [InlineData("Production")]
    [InlineData("Testing")]
    public async Task AfterTheMigrationEveryPortWorksAndT200ValuesStayValid(string environment)
    {
        var logs = new FileKmsHost.CapturingLogs();
        await using var services = OpenBaoHost.Services(environment, bed.Settings(), logs);

        await FileKmsHost.StartAsync(services);

        // Sign/verify with the published key (the startup check also proved JWK = Transit public key).
        var signer = services.GetRequiredService<ISigner>();
        var signature = await signer.SignAsync(SigningPurpose.Sync, "{}"u8.ToArray(), CancellationToken.None);
        Assert.Equal(OpenBaoTestBed.SyncKid, signature.Kid);
        Assert.True(signer.PublishedKeys(SigningPurpose.Sync).Single().PublicJwk.Verifies("{}"u8, signature.Signature.Span));
        _ = await signer.CreateJwsAsync(SigningPurpose.Entitlement, new { gold = true }, CancellationToken.None);

        // HMAC: the imported key is the T-200 key, so stored hashes stay valid.
        var hasher = services.GetRequiredService<IKeyedHasher>();
        foreach (var (key, name) in new[] { (KeyedHashKey.Seat, "seat"), (KeyedHashKey.Audit, "audit"), (KeyedHashKey.InstallHashPepper, "install-pepper") })
        {
            var mac = await hasher.HmacSha256Async(key, "install-1"u8.ToArray(), CancellationToken.None);
            Assert.Equal(HMACSHA256.HashData(bed.FileKeys.ReadSecret(name), "install-1"u8), mac);
        }

        // New envelopes round-trip and carry the Transit key reference and a vault:v1: wrap.
        var cipher = services.GetRequiredService<IEnvelopeCipher>();
        var blob = await cipher.EncryptAsync("hello"u8.ToArray(), "ctx", CancellationToken.None);
        var keyRef = Encoding.ASCII.GetString(blob, 2, blob[1]);
        Assert.Equal("openbao:" + OpenBaoTestBed.Envelope, keyRef);
        Assert.StartsWith("vault:v1:", Encoding.ASCII.GetString(blob, 2 + blob[1] + 2, 9), StringComparison.Ordinal);
        Assert.Equal("hello"u8.ToArray(), await cipher.DecryptAsync(blob, "ctx", CancellationToken.None));

        Assert.Contains(logs.Lines, l => l.Contains("KMS key ring verified", StringComparison.Ordinal));
        AssertNoSecrets(logs.Lines);
    }

    [LinuxFact]
    public async Task EnvelopesSealedByTheT200FileProviderOpenThroughOpenBao()
    {
        // An Apple refresh token sealed before the migration, by the real File provider.
        byte[] legacy;
        await using (var file = FileKmsHost.Services("Production", bed.FileKeys.Settings()))
        {
            await FileKmsHost.StartAsync(file);
            legacy = await file.GetRequiredService<IEnvelopeCipher>().EncryptAsync("refresh-token"u8.ToArray(), "account/apple-rt/v1/x", CancellationToken.None);
        }

        Assert.Equal("file:envelope", Encoding.ASCII.GetString(legacy, 2, legacy[1]));
        await using var services = OpenBaoHost.Services("Production", bed.Settings());
        await FileKmsHost.StartAsync(services);

        var opened = await services.GetRequiredService<IEnvelopeCipher>().DecryptAsync(legacy, "account/apple-rt/v1/x", CancellationToken.None);

        Assert.Equal("refresh-token"u8.ToArray(), opened);
        Assert.Contains(bed.Stub.Requests, r => r.Contains("/v1/transit/decrypt/file-envelope", StringComparison.Ordinal) && r.Contains("\"associated_data\"", StringComparison.Ordinal));
    }

    [LinuxFact]
    public async Task SeatCheckFromT200StillPasses()
    {
        var settings = bed.Settings();
        Assert.Equal(bed.FileKeys.Settings()["Kms:HmacKeys:SeatCheck"], settings["Kms:HmacKeys:SeatCheck"]);
        await using var services = OpenBaoHost.Services("Production", settings);

        await FileKmsHost.StartAsync(services);

        settings["Kms:HmacKeys:SeatCheck"] = new string('0', 64);
        await using var wrong = OpenBaoHost.Services("Production", settings);
        var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => FileKmsHost.StartAsync(wrong));
        Assert.Equal(SeatKeyStartupCheck.MismatchMessage, error.Message);
    }

    [LinuxFact]
    public async Task SignAndHmacPinKeyVersionOneAndSignPrehashedJws()
    {
        await using var services = await StartedAsync();
        bed.Stub.RotateKey(OpenBaoTestBed.SyncKid);
        bed.Stub.RotateKey("seat");
        while (bed.Stub.Requests.TryDequeue(out _))
        {
        }

        var signer = services.GetRequiredService<ISigner>();
        var signature = await signer.SignAsync(SigningPurpose.Sync, "body"u8.ToArray(), CancellationToken.None);
        var mac = await services.GetRequiredService<IKeyedHasher>().HmacSha256Async(KeyedHashKey.Seat, "x"u8.ToArray(), CancellationToken.None);

        // A rotated Transit key changes nothing: version 1 still signs (the published JWK verifies) and still MACs.
        Assert.True(signer.PublishedKeys(SigningPurpose.Sync).Single().PublicJwk.Verifies("body"u8, signature.Signature.Span));
        Assert.Equal(HMACSHA256.HashData(bed.FileKeys.ReadSecret("seat"), "x"u8), mac);
        var sign = Assert.Single(bed.Stub.Requests, r => r.Contains("/transit/sign/", StringComparison.Ordinal));
        Assert.Contains("/v1/transit/sign/s2027a/sha2-256 ", sign, StringComparison.Ordinal);
        Assert.Contains("\"prehashed\":true", sign, StringComparison.Ordinal);
        Assert.Contains("\"marshaling_algorithm\":\"jws\"", sign, StringComparison.Ordinal);
        Assert.Contains("\"key_version\":1", sign, StringComparison.Ordinal);
        Assert.Contains(bed.Stub.Requests, r => r.Contains("/v1/transit/hmac/seat/sha2-256 ", StringComparison.Ordinal) && r.Contains("\"key_version\":1", StringComparison.Ordinal));
    }

    [LinuxFact]
    public async Task PublicKeyFromTransitEqualsThePublishedJwk()
    {
        await using var services = await StartedAsync();
        var provider = services.GetRequiredService<ISigningKeyProvider>();
        var signer = services.GetRequiredService<ISigner>();

        foreach (var purpose in Enum.GetValues<SigningPurpose>())
        {
            var key = signer.PublishedKeys(purpose).Single();
            Assert.Equal(key.PublicJwk.ToX963(), await provider.GetPublicKeyAsync(key.KeyRef, CancellationToken.None));
        }
    }

    [LinuxFact]
    public async Task HmacAndEnvelopesAreStableAcrossAppAndServerRestarts()
    {
        byte[] mac;
        byte[] blob;
        await using (var first = await StartedAsync())
        {
            mac = await first.GetRequiredService<IKeyedHasher>().HmacSha256Async(KeyedHashKey.InstallHashPepper, "i"u8.ToArray(), CancellationToken.None);
            blob = await first.GetRequiredService<IEnvelopeCipher>().EncryptAsync("x"u8.ToArray(), "c", CancellationToken.None);
        }

        await bed.Stub.RestartAsync();
        await using var second = await StartedAsync();

        Assert.Equal(mac, await second.GetRequiredService<IKeyedHasher>().HmacSha256Async(KeyedHashKey.InstallHashPepper, "i"u8.ToArray(), CancellationToken.None));
        Assert.Equal("x"u8.ToArray(), await second.GetRequiredService<IEnvelopeCipher>().DecryptAsync(blob, "c", CancellationToken.None));
    }

    [LinuxFact]
    public async Task ASealedServerIsUnavailableNotUndecryptable()
    {
        await using var services = await StartedAsync();
        var blob = await services.GetRequiredService<IEnvelopeCipher>().EncryptAsync("x"u8.ToArray(), "c", CancellationToken.None);
        bed.Stub.Sealed = true;

        await Assert.ThrowsAsync<KmsUnavailableException>(() => services.GetRequiredService<ISigner>().SignAsync(SigningPurpose.Sync, "b"u8.ToArray(), CancellationToken.None).AsTask());
        await Assert.ThrowsAsync<KmsUnavailableException>(() => services.GetRequiredService<IKeyedHasher>().HmacSha256Async(KeyedHashKey.Seat, "b"u8.ToArray(), CancellationToken.None).AsTask());
        await Assert.ThrowsAsync<KmsUnavailableException>(() => services.GetRequiredService<IEnvelopeCipher>().DecryptAsync(blob, "c", CancellationToken.None).AsTask());
        await Assert.ThrowsAsync<KmsUnavailableException>(() => services.GetRequiredService<IEnvelopeCipher>().EncryptAsync("x"u8.ToArray(), "c", CancellationToken.None).AsTask());
    }

    [LinuxFact]
    public async Task ASealedServerRefusesTheStart()
    {
        bed.Stub.Sealed = true;
        await using var services = OpenBaoHost.Services("Production", bed.Settings());

        var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => FileKmsHost.StartAsync(services));

        Assert.Equal(OpenBaoKms.UnreachableMessage, error.Message);
    }

    [LinuxFact]
    public async Task ASlowServerTimesOutAsUnavailable()
    {
        var policy = new KmsCallPolicy { Timeout = TimeSpan.FromMilliseconds(300) };
        await using var services = await StartedAsync(policy: policy);
        bed.Stub.Delay = TimeSpan.FromSeconds(5);
        var clock = Stopwatch.StartNew();

        await Assert.ThrowsAsync<KmsUnavailableException>(() => services.GetRequiredService<ISigner>().SignAsync(SigningPurpose.Sync, "b"u8.ToArray(), CancellationToken.None).AsTask());

        Assert.True(clock.Elapsed < TimeSpan.FromSeconds(3), clock.Elapsed.ToString());
    }

    [LinuxFact]
    public async Task AnUnreachableServerIsUnavailable()
    {
        await using var services = await StartedAsync(policy: new KmsCallPolicy { Timeout = TimeSpan.FromMilliseconds(500) });
        await bed.Stub.DisposeAsync();

        await Assert.ThrowsAsync<KmsUnavailableException>(() => services.GetRequiredService<IKeyedHasher>().HmacSha256Async(KeyedHashKey.Audit, "b"u8.ToArray(), CancellationToken.None).AsTask());
    }

    [LinuxFact]
    public async Task OnlyAProvenBadTagIsUndecryptable()
    {
        await using var services = await StartedAsync();
        var cipher = services.GetRequiredService<IEnvelopeCipher>();
        var blob = await cipher.EncryptAsync("x"u8.ToArray(), "c", CancellationToken.None);

        // Tamper with the Transit ciphertext inside the envelope (still valid base64 and prefix): the tag fails in OpenBao.
        var tampered = (byte[])blob.Clone();
        var keyRefLength = tampered[1];
        var wrappedStart = 2 + keyRefLength + 2;
        var at = wrappedStart + "vault:v1:".Length + 4;
        tampered[at] = tampered[at] == (byte)'A' ? (byte)'B' : (byte)'A';
        await Assert.ThrowsAsync<EnvelopeDecryptionException>(() => cipher.DecryptAsync(tampered, "c", CancellationToken.None).AsTask());

        // A missing key (deleted, or a misnamed reference) is never "undecryptable": callers delete what can't be opened.
        bed.Stub.DeleteKey(OpenBaoTestBed.Envelope);
        await Assert.ThrowsAsync<KmsUnavailableException>(() => cipher.DecryptAsync(blob, "c", CancellationToken.None).AsTask());
    }

    [LinuxFact]
    public async Task AVersionTooNewIsUnavailableNotUndecryptable()
    {
        // An older snapshot restored under a running API: the key lacks the version the envelope names.
        await using var services = await StartedAsync();
        var cipher = services.GetRequiredService<IEnvelopeCipher>();
        bed.Stub.RotateKey(OpenBaoTestBed.Envelope);
        var blob = await cipher.EncryptAsync("x"u8.ToArray(), "c", CancellationToken.None);
        Assert.Contains("vault:v2:", Encoding.ASCII.GetString(blob), StringComparison.Ordinal);
        bed.Stub.DeleteKey(OpenBaoTestBed.Envelope);
        bed.Stub.CreateKey(OpenBaoTestBed.Envelope, "aes256-gcm96");

        await Assert.ThrowsAsync<KmsUnavailableException>(() => cipher.DecryptAsync(blob, "c", CancellationToken.None).AsTask());
    }

    [LinuxFact]
    public async Task ADeniedDecryptIsUnavailable()
    {
        await using var services = await StartedAsync();
        var cipher = services.GetRequiredService<IEnvelopeCipher>();
        var blob = await cipher.EncryptAsync("x"u8.ToArray(), "c", CancellationToken.None);
        bed.Stub.SetPolicy("zaghlol-api", "path \"transit/keys/x\" {\n  capabilities = [\"read\"]\n}\n");

        await Assert.ThrowsAsync<KmsUnavailableException>(() => cipher.DecryptAsync(blob, "c", CancellationToken.None).AsTask());
    }

    [LinuxFact]
    public async Task AMalformedLegacyWrapIsUndecryptableWithoutAsking()
    {
        await using var services = await StartedAsync();
        var provider = services.GetRequiredService<IDataKeyProvider>();
        bed.Stub.Requests.Clear();

        await Assert.ThrowsAsync<CryptographicException>(() => provider.DecryptDataKeyAsync("file:envelope", new byte[59], CancellationToken.None).AsTask());
        await Assert.ThrowsAsync<CryptographicException>(() => provider.DecryptDataKeyAsync("openbao:" + OpenBaoTestBed.Envelope, "not a wrap"u8.ToArray(), CancellationToken.None).AsTask());
        Assert.Empty(bed.Stub.Requests);
    }

    [LinuxFact]
    public async Task ARevokedTokenLogsInAgainOnce()
    {
        await using var services = await StartedAsync();
        var before = bed.Stub.Logins;
        bed.Stub.RevokeAllTokens();

        _ = await services.GetRequiredService<IKeyedHasher>().HmacSha256Async(KeyedHashKey.Audit, "x"u8.ToArray(), CancellationToken.None);
        _ = await services.GetRequiredService<IKeyedHasher>().HmacSha256Async(KeyedHashKey.Audit, "y"u8.ToArray(), CancellationToken.None);

        Assert.Equal(before + 1, bed.Stub.Logins);
    }

    [LinuxFact]
    public async Task AnExpiringTokenIsRenewedBeforeItLapses()
    {
        bed.Stub.TokenTtlSeconds = 1;
        await using var services = await StartedAsync();
        var before = bed.Stub.Logins;
        await Task.Delay(TimeSpan.FromMilliseconds(800));

        _ = await services.GetRequiredService<IKeyedHasher>().HmacSha256Async(KeyedHashKey.Audit, "x"u8.ToArray(), CancellationToken.None);

        Assert.Equal(before + 1, bed.Stub.Logins);
        Assert.DoesNotContain(bed.Stub.Requests, r => r.Contains("permission denied", StringComparison.Ordinal));
    }

    [LinuxFact]
    public async Task ManyConcurrentCallersShareOneLogin()
    {
        await using var services = OpenBaoHost.Services("Production", bed.Settings());
        var signer = services.GetRequiredService<ISigner>();
        var jwk = signer.PublishedKeys(SigningPurpose.Sync).Single().PublicJwk;

        var results = await Task.WhenAll(Enumerable.Range(0, 64).Select(i => Task.Run(async () =>
        {
            var body = BitConverter.GetBytes(i);
            var signature = await signer.SignAsync(SigningPurpose.Sync, body, CancellationToken.None);
            return jwk.Verifies(body, signature.Signature.Span);
        })));

        Assert.All(results, Assert.True);
        Assert.Equal(1, ((OpenBaoKms)services.GetRequiredService<ISigningKeyProvider>()).Client.Logins);
    }

    [LinuxFact]
    public async Task TheWorkerStartsWithEnvelopeKeysOnly()
    {
        bed.Stub.Requests.Clear();
        await using var services = OpenBaoHost.Services("Production", bed.Settings(worker: true));
        await FileKmsHost.StartAsync(services);

        var cipher = services.GetRequiredService<IEnvelopeCipher>();
        Assert.Equal("x"u8.ToArray(), await cipher.DecryptAsync(await cipher.EncryptAsync("x"u8.ToArray(), "c", CancellationToken.None), "c", CancellationToken.None));
        var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => services.GetRequiredService<ISigner>().SignAsync(SigningPurpose.Sync, "b"u8.ToArray(), CancellationToken.None).AsTask());
        Assert.Equal(OpenBaoKms.ScopeMessage, error.Message);
        Assert.DoesNotContain(bed.Stub.Requests, r => r.Contains("/transit/sign/", StringComparison.Ordinal) || r.Contains("/transit/hmac/seat", StringComparison.Ordinal));
    }

    [LinuxFact]
    public async Task TheWorkerPolicyCanNotSignOrMac()
    {
        // The worker's AppRole with the API's full scope: its policy refuses the signing key read, so the start is refused.
        var settings = bed.Settings();
        settings["Kms:OpenBao:CredentialDirectory"] = bed.WorkerCredentials;
        await using var services = OpenBaoHost.Services("Production", settings);

        var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => FileKmsHost.StartAsync(services));

        Assert.Equal(OpenBaoKms.UnreachableMessage, error.Message);
        Assert.Contains(bed.Stub.Requests, r => r.StartsWith("GET /v1/transit/keys/", StringComparison.Ordinal));
    }

    [LinuxTheory]
    [InlineData("GET", "transit/export/hmac-key/seat")]
    [InlineData("GET", "transit/export/encryption-key/" + OpenBaoTestBed.Envelope)]
    [InlineData("GET", "transit/backup/seat")]
    [InlineData("POST", "transit/keys/seat/rotate")]
    [InlineData("POST", "transit/keys/seat/config")]
    [InlineData("POST", "transit/keys/seat/import")]
    [InlineData("POST", "transit/keys/new-key")]
    [InlineData("GET", "transit/wrapping_key")]
    [InlineData("POST", "transit/datakey/wrapped/" + OpenBaoTestBed.Envelope)]
    [InlineData("POST", "transit/encrypt/" + OpenBaoTestBed.Envelope)]
    [InlineData("POST", "transit/sign/seat/sha2-256")]
    [InlineData("GET", "sys/policies/acl/zaghlol-api")]
    public async Task TheApiAndWorkerPoliciesRefuseEverythingElse(string method, string path)
    {
        var roots = new System.Security.Cryptography.X509Certificates.X509Certificate2Collection { bed.Stub.Ca.Certificate };
        foreach (var policy in new[] { "zaghlol-api", "zaghlol-worker" })
        {
            using var client = OpenBaoClient.WithToken(bed.Stub.Address, OpenBaoClient.CreateHandler(roots, TimeSpan.FromSeconds(5)), bed.Stub.CreateToken(policy), TimeProvider.System);
            using var answer = await client.SendRawAsync(new HttpMethod(method), path, method == "POST" ? w => w.WriteString("input", "AA==") : null, bed.Stub.CreateToken(policy), CancellationToken.None);
            Assert.Equal(System.Net.HttpStatusCode.Forbidden, answer.Status);
        }
    }

    [LinuxFact]
    public async Task AnotherCaIsRefused()
    {
        using var other = new TestCa("someone-else");
        OpenBaoTestBed.WriteCredentials(bed.ApiCredentials, bed.ApiRole, other.Pem);
        await using var services = OpenBaoHost.Services("Production", bed.Settings());

        var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => FileKmsHost.StartAsync(services));

        Assert.Equal(OpenBaoKms.UnreachableMessage, error.Message);
        Assert.Equal(0, bed.Stub.Logins);
    }

    [LinuxTheory]
    [InlineData("http://127.0.0.1:8200", "Production")]
    [InlineData("https://user@127.0.0.1:8200", "Testing")]
    [InlineData("https://127.0.0.1:8200/v1", "Testing")]
    [InlineData("https://127.0.0.1:8200/?x=1", "Testing")]
    [InlineData("127.0.0.1:8200", "Testing")]
    public async Task AnAddressThatIsNotPlainHttpsIsRefused(string address, string environment)
    {
        var settings = bed.Settings();
        settings["Kms:OpenBao:Address"] = address;

        await AssertRefusedAsync(settings, OpenBaoKms.AddressMessage, environment);
    }

    [LinuxFact]
    public async Task ACredentialDirectoryReadableByOthersIsRefused()
    {
        File.SetUnixFileMode(Path.Combine(bed.ApiCredentials, OpenBaoKms.SecretIdFile), FileKmsKeySet.Mode0400 | UnixFileMode.GroupRead);

        var error = await AssertRefusedAsync(bed.Settings(), message: null);

        Assert.Contains("Kms:OpenBao:CredentialDirectory", error.Message, StringComparison.Ordinal);
    }

    [LinuxFact]
    public async Task AMalformedSecretIdIsRefused()
    {
        OpenBaoTestBed.WritePrivate(Path.Combine(bed.ApiCredentials, OpenBaoKms.SecretIdFile), "two words\n");

        await AssertRefusedAsync(bed.Settings(), OpenBaoKms.CredentialMessage);
    }

    [LinuxFact]
    public async Task AMissingCaIsRefused()
    {
        File.Delete(Path.Combine(bed.ApiCredentials, OpenBaoKms.CaFile));

        await AssertRefusedAsync(bed.Settings(), OpenBaoKms.CaMessage);
    }

    [LinuxFact]
    public async Task AWrongSecretIdRefusesTheStart()
    {
        OpenBaoTestBed.WritePrivate(Path.Combine(bed.ApiCredentials, OpenBaoKms.SecretIdFile), Guid.NewGuid() + "\n");

        await AssertRefusedAsync(bed.Settings(), OpenBaoKms.UnreachableMessage);
    }

    [LinuxTheory]
    [InlineData("exportable")]
    [InlineData("plaintext-backup")]
    [InlineData("deletion")]
    public async Task O2_AKeyThatCouldLeaveOpenBaoIsRefused(string flag)
    {
        bed.Stub.DeleteKey(OpenBaoTestBed.Envelope);
        bed.Stub.CreateKey(OpenBaoTestBed.Envelope, "aes256-gcm96", exportable: flag == "exportable", allowPlaintextBackup: flag == "plaintext-backup", deletionAllowed: flag == "deletion");
        var settings = bed.Settings();
        settings[Pin(OpenBaoTestBed.Envelope)] = await PinOfAsync(OpenBaoTestBed.Envelope);

        await AssertRefusedAsync(settings, OpenBaoKms.KeyAttributesMessage);
    }

    [LinuxFact]
    public async Task O1_AKeyOfTheWrongTypeIsRefused()
    {
        var settings = bed.Settings();
        settings["Kms:HmacKeys:Audit"] = "openbao:other";
        bed.Stub.PutRawKey("other", "aes256-gcm96", RandomNumberGenerator.GetBytes(32));
        AllowApiHmacKey("other");

        await AssertRefusedAsync(settings, OpenBaoKms.KeyTypeMessage);
    }

    [LinuxFact]
    public async Task G11_AMissingOrWrongPinIsRefused()
    {
        var settings = bed.Settings();
        settings.Remove("Kms:OpenBao:Fingerprints:seat");
        await AssertRefusedAsync(settings, OpenBaoKms.FingerprintMessage);

        settings = bed.Settings();
        settings[Pin(OpenBaoTestBed.SyncKid)] = new string('a', 64);
        await AssertRefusedAsync(settings, OpenBaoKms.FingerprintMessage);
    }

    [LinuxFact]
    public async Task G11_AKeyRecreatedUnderTheSameNameIsRefused()
    {
        var settings = bed.Settings();
        bed.Stub.DeleteKey(OpenBaoTestBed.Envelope);
        bed.Stub.CreateKey(OpenBaoTestBed.Envelope, "aes256-gcm96");

        await AssertRefusedAsync(settings, OpenBaoKms.FingerprintMessage);
    }

    [LinuxFact]
    public async Task G10_ACommittedTestKeyIsRefused()
    {
        // The fixed K_seat of the vectors (00 01 .. 1f), put straight into OpenBao (the key tool refuses to import it).
        var fixedSeat = Enumerable.Range(0, 32).Select(i => (byte)i).ToArray();
        bed.Stub.PutRawKey("seat-test", "hmac", fixedSeat);
        var settings = bed.Settings();
        settings["Kms:HmacKeys:Seat"] = "openbao:seat-test";
        settings[Pin("seat-test")] = KeyFingerprints.OfSecret(fixedSeat);
        AllowApiHmacKey("seat-test");

        await AssertRefusedAsync(settings, OpenBaoKms.KnownTestKeyMessage);
    }

    [LinuxFact]
    public async Task G12_AnotherEnvironmentsKeyIsRefused()
    {
        var settings = bed.Settings();
        settings["Kms:OpenBao:NoOtherEnvironment"] = null;
        await AssertRefusedAsync(settings, OpenBaoKms.OtherEnvironmentUnsetMessage);

        settings["Kms:OpenBao:OtherEnvironmentFingerprints:0"] = settings["Kms:OpenBao:Fingerprints:audit"];
        await AssertRefusedAsync(settings, OpenBaoKms.OtherEnvironmentMessage);

        settings["Kms:OpenBao:OtherEnvironmentFingerprints:0"] = "not-hex";
        await AssertRefusedAsync(settings, OpenBaoKms.OtherEnvironmentMalformedMessage);
    }

    [LinuxFact]
    public async Task G13_DevelopmentKidsAreRefusedOutsideDevelopmentAndTesting()
    {
        var settings = bed.Settings();
        settings["Signing:Keys:0:Kid"] = "s0000d";

        await AssertRefusedAsync(settings, OpenBaoKms.DevKidMessage);
    }

    [LinuxTheory]
    [InlineData("Kms:Envelope:KeyRef", "file:envelope")]
    [InlineData("Kms:HmacKeys:Seat", "file:seat")]
    [InlineData("Signing:Keys:0:KeyRef", "file:s2027a")]
    [InlineData("Kms:HmacKeys:Audit", "local:audit")]
    [InlineData("Kms:HmacKeys:Audit", "openbao:Audit")]
    public async Task G7_KeyReferencesOutsideTheirRoleAreRefused(string setting, string value)
    {
        var settings = bed.Settings();
        settings[setting] = value;

        await AssertRefusedAsync(settings, OpenBaoKms.KeyRefMessage);
    }

    [LinuxFact]
    public async Task G15_OneTransitKeyInTwoRolesIsRefused()
    {
        var settings = bed.Settings();
        settings["Kms:HmacKeys:Audit"] = "openbao:seat";

        await AssertRefusedAsync(settings, OpenBaoKms.SharedKeyMessage);
    }

    [LinuxFact]
    public async Task LocalIsStillRefusedInProduction()
    {
        var settings = bed.Settings();
        settings["Kms:Provider"] = "Local";
        settings["Kms:Local:KeyDirectory"] = bed.Root;

        await AssertRefusedAsync(settings, "Kms:Provider = Local is allowed only in the Development and Testing environments.");
    }

    private static string Pin(string transitName) => "Kms:OpenBao:Fingerprints:" + transitName.Replace('-', '_');

    /// <summary>Re-renders the API policy from setup.sh with one more HMAC key (as the operator would, for a new key).</summary>
    private void AllowApiHmacKey(string name)
    {
        var environment = new Dictionary<string, string>(OpenBaoTestBed.PolicyEnvironment, StringComparer.Ordinal)
        {
            ["ZAGHLOL_HMAC_KEYS"] = "seat audit install-pepper " + name,
        };
        bed.Stub.LoadSetupPolicy("api", environment);
    }

    private async Task<string> PinOfAsync(string transitName)
    {
        var roots = new System.Security.Cryptography.X509Certificates.X509Certificate2Collection { bed.Stub.Ca.Certificate };
        using var client = OpenBaoClient.WithToken(bed.Stub.Address, OpenBaoClient.CreateHandler(roots, TimeSpan.FromSeconds(5)), bed.Stub.RootToken, TimeProvider.System);
        using var kms = OpenBaoKms.ForTool(client, OpenBaoStub.Mount);
        return Convert.ToHexStringLower(await kms.TransitHmacAsync(transitName, OpenBaoKms.PinLabel, CancellationToken.None));
    }

    private async Task<ServiceProvider> StartedAsync(KmsCallPolicy? policy = null)
    {
        var services = OpenBaoHost.Services("Production", bed.Settings(), policy: policy);
        await FileKmsHost.StartAsync(services);
        return services;
    }

    private async Task<KmsConfigurationException> AssertRefusedAsync(Dictionary<string, string?> settings, string? message, string environment = "Production")
    {
        var logs = new FileKmsHost.CapturingLogs();
        await using var services = OpenBaoHost.Services(environment, settings, logs);

        var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => FileKmsHost.StartAsync(services));

        if (message is not null)
        {
            Assert.Equal(message, error.Message);
        }

        AssertNoSecrets([.. logs.Lines, error.ToString()]);
        Assert.DoesNotContain(bed.Root, error.ToString(), StringComparison.Ordinal);
        return error;
    }

    private void AssertNoSecrets(IEnumerable<string> haystacks)
    {
        foreach (var haystack in haystacks)
        {
            foreach (var sentinel in bed.Sentinels)
            {
                Assert.DoesNotContain(sentinel, haystack, StringComparison.OrdinalIgnoreCase);
            }
        }
    }
}
