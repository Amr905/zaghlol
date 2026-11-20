using System.Runtime.Versioning;
using System.Security.Cryptography;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>
/// T-201 acceptance 4: the BYOK import of the T-200 HMAC and envelope keys. The pins it prints for HMAC keys equal the T-200
/// File pins (same key), it re-runs without importing twice, refuses a different key under a taken name and a committed
/// test key, and never prints key material.
/// </summary>
[SupportedOSPlatform("linux")]
public sealed class OpenBaoKeyToolTests : IAsyncLifetime
{
    private OpenBaoTestBed bed = null!;

    public async Task InitializeAsync() => bed = await OpenBaoTestBed.CreateAsync(import: false);

    public async Task DisposeAsync() => await bed.DisposeAsync();

    [LinuxFact]
    public void ImportedHmacKeysPinTheSameFingerprintsAsT200()
    {
        var (code, output, errors) = OpenBaoTestBed.RunTool(bed.ImportArguments());

        Assert.Equal(OpenBaoKeyTool.Ok, code);
        var printed = OpenBaoTestBed.ParseEnvLines(output).ToDictionary(p => p.Key, p => p.Value, StringComparer.Ordinal);
        var file = bed.FileKeys.Settings();
        Assert.Equal(file["Kms:File:Fingerprints:seat"], printed["Kms:OpenBao:Fingerprints:seat"]);
        Assert.Equal(file["Kms:File:Fingerprints:audit"], printed["Kms:OpenBao:Fingerprints:audit"]);
        Assert.Equal(file["Kms:File:Fingerprints:install-pepper"], printed["Kms:OpenBao:Fingerprints:install_pepper"]);
        Assert.Equal("file:envelope", printed["Kms:Envelope:PreviousKeyRefs:0"]);
        Assert.True(KeyFingerprints.IsWellFormed(printed["Kms:OpenBao:Fingerprints:file_envelope"]));
        Assert.Equal("openbao:s2027a", printed["Signing:Keys:0:KeyRef"]);
        Assert.Equal("Next", printed["Signing:Keys:0:Status"]);
        Assert.Equal("Entitlement", printed["Signing:Keys:1:Purpose"]);
        Assert.Contains("imported: hmac key seat", errors, StringComparison.Ordinal);
        Assert.Contains("imported: envelope key file-envelope", errors, StringComparison.Ordinal);
        AssertNoSecrets(output + errors);
    }

    [LinuxFact]
    public void TheImportedKeysAreNonExportableHmacAndAesKeys()
    {
        Assert.Equal(OpenBaoKeyTool.Ok, OpenBaoTestBed.RunTool(bed.ImportArguments()).Code);

        var import = Assert.Single(bed.Stub.Requests, r => r.StartsWith("POST /v1/transit/keys/seat/import ", StringComparison.Ordinal));
        Assert.Contains("\"type\":\"hmac\"", import, StringComparison.Ordinal);
        Assert.Contains("\"exportable\":false", import, StringComparison.Ordinal);
        Assert.Contains("\"allow_plaintext_backup\":false", import, StringComparison.Ordinal);
        Assert.Contains("\"hash_function\":\"SHA256\"", import, StringComparison.Ordinal);
        var legacy = Assert.Single(bed.Stub.Requests, r => r.StartsWith("POST /v1/transit/keys/file-envelope/import ", StringComparison.Ordinal));
        Assert.Contains("\"type\":\"aes256-gcm96\"", legacy, StringComparison.Ordinal);
    }

    [LinuxFact]
    public void ARerunVerifiesWithoutImportingAgain()
    {
        Assert.Equal(OpenBaoKeyTool.Ok, OpenBaoTestBed.RunTool(bed.ImportArguments()).Code);
        bed.Stub.Requests.Clear();

        var (code, output, errors) = OpenBaoTestBed.RunTool(bed.ImportArguments());

        Assert.Equal(OpenBaoKeyTool.Ok, code);
        Assert.Contains("exists: hmac key seat (verifying, not importing)", errors, StringComparison.Ordinal);
        Assert.DoesNotContain(bed.Stub.Requests, r => r.Contains("/import ", StringComparison.Ordinal));
        Assert.Contains("Kms__OpenBao__Fingerprints__seat=", output, StringComparison.Ordinal);
    }

    [LinuxFact]
    public void ADifferentKeyUnderTheSameNameIsRefused()
    {
        bed.Stub.PutRawKey("seat", "hmac", RandomNumberGenerator.GetBytes(32));

        var (code, output, errors) = OpenBaoTestBed.RunTool(bed.ImportArguments());

        Assert.Equal(OpenBaoKeyTool.Failed, code);
        Assert.Empty(output);
        Assert.Contains("is not the File key of that name", errors, StringComparison.Ordinal);
    }

    [LinuxFact]
    public void AWrongLegacyEnvelopeKeyIsRefused()
    {
        bed.Stub.PutRawKey("file-envelope", "aes256-gcm96", RandomNumberGenerator.GetBytes(32));

        var (code, output, errors) = OpenBaoTestBed.RunTool(bed.ImportArguments());

        Assert.Equal(OpenBaoKeyTool.Failed, code);
        Assert.Empty(output);
        Assert.Contains("does not open envelopes of the File key", errors, StringComparison.Ordinal);
    }

    [LinuxFact]
    public void ACommittedTestKeyIsNotImported()
    {
        bed.FileKeys.WriteSecret("seat", [.. Enumerable.Range(0, 32).Select(i => (byte)i)]);

        var (code, _, errors) = OpenBaoTestBed.RunTool(bed.ImportArguments());

        Assert.Equal(OpenBaoKeyTool.Failed, code);
        Assert.Contains(FileKms.KnownTestKeyMessage, errors, StringComparison.Ordinal);
        Assert.False(bed.Stub.HasKey("seat"));
    }

    [LinuxFact]
    public void AnExportableSigningKeyIsRefused()
    {
        bed.Stub.DeleteKey(OpenBaoTestBed.SyncKid);
        bed.Stub.CreateKey(OpenBaoTestBed.SyncKid, "ecdsa-p256", exportable: true);

        var (code, output, errors) = OpenBaoTestBed.RunTool(bed.ImportArguments());

        Assert.Equal(OpenBaoKeyTool.Failed, code);
        Assert.Empty(output);
        Assert.Contains(OpenBaoKms.KeyAttributesMessage, errors, StringComparison.Ordinal);
    }

    [LinuxFact]
    public void TheToolTrustsOnlyTheGivenCa()
    {
        using var other = new TestCa("someone-else");
        OpenBaoTestBed.WritePrivate(bed.CaFile, other.Pem);

        var (code, output, _) = OpenBaoTestBed.RunTool(bed.ImportArguments());

        Assert.Equal(OpenBaoKeyTool.Failed, code);
        Assert.Empty(output);
        Assert.DoesNotContain(bed.Stub.Requests, r => r.Contains("/import ", StringComparison.Ordinal));
    }

    [LinuxFact]
    public void ATokenFileReadableByOthersIsRefused()
    {
        File.SetUnixFileMode(bed.ToolTokenFile, UnixFileMode.UserRead | UnixFileMode.OtherRead);

        var (code, _, errors) = OpenBaoTestBed.RunTool(bed.ImportArguments());

        Assert.Equal(OpenBaoKeyTool.Failed, code);
        Assert.Contains("refused:", errors, StringComparison.Ordinal);
        Assert.Empty(bed.Stub.Requests);
    }

    [LinuxTheory]
    [InlineData("--address", "http://127.0.0.1:8200")]
    [InlineData("--kid", "s0000a")]
    [InlineData("--import-hmac", "Bad_Name")]
    [InlineData("--surprise", "s3cr3t-value")]
    public void BadArgumentsAreRefusedWithoutEcho(string option, string value)
    {
        var args = bed.ImportArguments();
        var at = args.IndexOf(option);
        if (at >= 0)
        {
            args[at + 1] = value;
        }
        else
        {
            args.AddRange([option, value]);
        }

        var (code, output, errors) = OpenBaoTestBed.RunTool(args);

        Assert.Equal(OpenBaoKeyTool.Usage, code);
        Assert.Empty(output);
        Assert.DoesNotContain(value, errors, StringComparison.Ordinal);
        Assert.Empty(bed.Stub.Requests);
    }

    [LinuxFact]
    public void TheImportCiphertextIsOpenBaosByokLayout()
    {
        using var rsa = RSA.Create(4096);
        var key = RandomNumberGenerator.GetBytes(32);

        var blob = Convert.FromBase64String(OpenBaoKeyTool.ImportCiphertext(rsa, key));

        // OpenBao decryptImportedKey: the first 512 bytes are RSA-OAEP-SHA256 of the AES key, the rest AES-KWP of the key.
        var ephemeral = rsa.Decrypt(blob.AsSpan(0, 512), RSAEncryptionPadding.OaepSHA256);
        using var aes = Aes.Create();
        aes.Key = ephemeral;
        Assert.Equal(key, aes.DecryptKeyWrapPadded(blob.AsSpan(512)));
    }

    private void AssertNoSecrets(string text)
    {
        foreach (var sentinel in bed.Sentinels)
        {
            Assert.DoesNotContain(sentinel, text, StringComparison.OrdinalIgnoreCase);
        }
    }
}
