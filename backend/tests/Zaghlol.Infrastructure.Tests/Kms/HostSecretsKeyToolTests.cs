using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>
/// T-205 acceptance 3: <c>--generate-keys --format host-secrets</c> prints the keys once as host settings and writes no file;
/// <c>--from-dir</c> converts a File KMS key directory (AC4 in <see cref="HostSecretsKmsTests"/>); refusals print nothing.
/// </summary>
public sealed class HostSecretsKeyToolTests : IDisposable
{
    private static readonly string[] AllKeys =
    [
        "--kid", "s2026a", "--kid", "e2026a", "--secret", "seat", "--secret", "audit", "--secret", "install-pepper", "--secret", "envelope",
    ];

    private readonly string scratch = Directory.CreateTempSubdirectory("zaghlol-host-tool-").FullName;

    public void Dispose() => Directory.Delete(scratch, recursive: true);

    /// <summary>The printed <c>NAME=value</c> lines as configuration keys (<c>__</c> becomes <c>:</c>); comments skipped.</summary>
    internal static Dictionary<string, string?> ParseLines(string output) =>
        output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(l => !l.StartsWith('#'))
            .Select(l => (Key: l[..l.IndexOf('=', StringComparison.Ordinal)], Value: l[(l.IndexOf('=', StringComparison.Ordinal) + 1)..]))
            .ToDictionary(p => p.Key.Replace("__", ":", StringComparison.Ordinal), p => (string?)p.Value, StringComparer.Ordinal);

    [Fact]
    public async Task TheGeneratedSettingsStartTheProviderAndNothingIsWritten()
    {
        var cwd = Directory.CreateDirectory(Path.Combine(scratch, "cwd")).FullName;
        var (code, stdout, stderr) = Run(["--generate-keys", "--format", "host-secrets", "--environment", "Production", .. AllKeys], cwd);

        Assert.Equal(0, code);
        Assert.Empty(stderr);
        Assert.Equal([cwd], Directory.EnumerateFileSystemEntries(scratch, "*", SearchOption.AllDirectories));

        var settings = ParseLines(stdout);
        var secretLines = settings.Where(p => p.Key.StartsWith("ZAGHLOL_KEYS:", StringComparison.Ordinal)).ToList();
        Assert.Equal(6, secretLines.Count);
        Assert.All(secretLines, p => Assert.StartsWith(HostSecretsKms.ValueMarker, p.Value, StringComparison.Ordinal));
        var publicPart = stdout[stdout.IndexOf("# PUBLIC", StringComparison.Ordinal)..];
        Assert.DoesNotContain("ZAGHLOL_KEYS", publicPart, StringComparison.Ordinal);
        Assert.False(settings.ContainsKey("Kms:AcceptSharedHostCustody"), "the operator sets the custody flag, not the tool");

        foreach (var key in settings.Keys.Where(k => k.EndsWith(":Status", StringComparison.Ordinal)).ToList())
        {
            settings[key] = "Active";
        }

        settings["Kms:AcceptSharedHostCustody"] = "true";
        settings["Kms:File:NoOtherEnvironment"] = "true";
        settings["Kms:HmacKeys:Seat"] = "file:seat";
        settings["Kms:HmacKeys:Audit"] = "file:audit";
        settings["Kms:HmacKeys:InstallHashPepper"] = "file:install-pepper";
        settings["Kms:Envelope:KeyRef"] = "file:envelope";
        await using var services = FileKmsHost.Services("Production", settings, contentRoot: cwd);
        await FileKmsHost.StartAsync(services);
        Assert.IsType<HostSecretsKms>(services.GetRequiredService<ISigningKeyProvider>());
    }

    [Fact]
    public void TheToolRefusesToRunInsideTheRepository()
    {
        var (code, stdout, stderr) = Run(["--generate-keys", "--format", "host-secrets", "--environment", "Production", "--secret", "seat"], AppContext.BaseDirectory);

        Assert.Equal(FileKeyTool.Usage, code);
        Assert.Empty(stdout);
        Assert.Contains("source tree", stderr, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("files")]
    [InlineData("env")]
    public void AnUnknownFormatIsRefused(string format)
    {
        var (code, stdout, stderr) = Run(["--generate-keys", "--format", format, "--environment", "Production", "--secret", "seat"], scratch);

        Assert.Equal(FileKeyTool.Usage, code);
        Assert.Empty(stdout);
        Assert.Contains("--format must be host-secrets", stderr, StringComparison.Ordinal);
    }

    [Fact]
    public void FromDirCannotBeCombinedWithNewKeys()
    {
        var (code, stdout, _) = Run(["--generate-keys", "--format", "host-secrets", "--environment", "Production", "--from-dir", scratch, "--kid", "s2026a"], scratch);

        Assert.Equal(FileKeyTool.Usage, code);
        Assert.Empty(stdout);
    }

    [Fact]
    public async Task FromDirRefusesDevelopmentKeys()
    {
        var keys = Directory.CreateDirectory(Path.Combine(scratch, "dev")).FullName;
        var secret = Convert.ToBase64String(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));
        await File.WriteAllTextAsync(Path.Combine(keys, "seat.key"), secret + "\n");
        await File.WriteAllTextAsync(Path.Combine(keys, "kms.env"), "Kms__Provider=Local\n");
        var cwd = Directory.CreateDirectory(Path.Combine(scratch, "cwd")).FullName;

        var (code, stdout, stderr) = Run(["--generate-keys", "--format", "host-secrets", "--environment", "Production", "--from-dir", keys], cwd);

        Assert.Equal(FileKeyTool.Usage, code);
        Assert.Empty(stdout);
        Assert.Contains("kms.env", stderr, StringComparison.Ordinal);
        Assert.DoesNotContain(secret, stderr, StringComparison.Ordinal);
    }

    [Fact]
    public async Task FromDirRefusesACommittedKey()
    {
        var keys = Directory.CreateDirectory(Path.Combine(scratch, "committed")).FullName;
        var secret = Convert.ToBase64String(FakeKms.FixedSeatKey);
        await File.WriteAllTextAsync(Path.Combine(keys, "seat.key"), secret + "\n");
        var cwd = Directory.CreateDirectory(Path.Combine(scratch, "cwd")).FullName;

        var (code, stdout, stderr) = Run(["--generate-keys", "--format", "host-secrets", "--environment", "Production", "--from-dir", keys], cwd);

        Assert.Equal(FileKeyTool.Usage, code);
        Assert.Empty(stdout);
        Assert.Contains(HostSecretsKms.KnownTestKeyMessage, stderr, StringComparison.Ordinal);
        Assert.DoesNotContain(secret, stderr, StringComparison.Ordinal);
    }

    private static (int Code, string Stdout, string Stderr) Run(string[] args, string cwd)
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var code = FileKeyTool.Run(args, stdout, stderr, cwd);
        return (code, stdout.ToString(), stderr.ToString());
    }
}
