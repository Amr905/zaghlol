using System.Runtime.Versioning;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>
/// T-200 acceptance 4: the production key tool writes 0400 keys into a new 0500 directory outside any source tree, refuses to
/// run inside one, prints public values only, and its printed lines start the File KMS in Production.
/// </summary>
[SupportedOSPlatform("linux")]
public sealed class FileKeyToolTests : IDisposable
{
    private static readonly string[] FullSet =
    [
        "--generate-keys", "--environment", "Production", "--out", "{out}",
        "--kid", "s2026a", "--kid", "e2026a",
        "--secret", "seat", "--secret", "audit", "--secret", "install-pepper", "--secret", "envelope",
    ];

    private readonly string root = Directory.CreateTempSubdirectory("zaghlol-keytool-").FullName;

    public void Dispose()
    {
        foreach (var dir in Directory.EnumerateDirectories(root, "*", SearchOption.AllDirectories))
        {
            File.SetUnixFileMode(dir, FileKmsKeySetModes.Mode0700);
        }

        Directory.Delete(root, recursive: true);
    }

    [LinuxFact]
    public async Task TheFullSetIsWrittenWithTightModesAndItsOutputStartsProduction()
    {
        var output = Path.Combine(root, "kms-production");

        var (code, stdout, stderr) = Run(FullSet, output, workingDirectory: root);

        Assert.True(code == FileKeyTool.Ok, stderr);
        Assert.Equal(FileKmsKeySetModes.Mode0500, File.GetUnixFileMode(output));
        var files = Directory.EnumerateFiles(output).Select(Path.GetFileName).Order(StringComparer.Ordinal).ToList();
        Assert.Equal(["audit.key", "e2026a.pem", "envelope.key", "install-pepper.key", "s2026a.pem", "seat.key"], files);
        Assert.All(Directory.EnumerateFiles(output), f => Assert.Equal(FileKmsKeySetModes.Mode0400, File.GetUnixFileMode(f)));

        // No private byte in the output: every PEM body line and every secret (base64 and hex) is absent.
        foreach (var file in Directory.EnumerateFiles(output))
        {
            var text = File.ReadAllText(file);
            var sentinels = file.EndsWith(".pem", StringComparison.Ordinal)
                ? text.Split('\n').Where(l => l.Length >= 16 && !l.StartsWith("-----", StringComparison.Ordinal)).ToList()
                : [text.Trim(), Convert.ToHexStringLower(Convert.FromBase64String(text.Trim()))];
            Assert.NotEmpty(sentinels);
            foreach (var sentinel in sentinels)
            {
                Assert.DoesNotContain(sentinel, stdout, StringComparison.OrdinalIgnoreCase);
                Assert.DoesNotContain(sentinel, stderr, StringComparison.OrdinalIgnoreCase);
            }
        }

        // The printed lines, as the operator pastes them (signing keys flipped to Active), start the File KMS in Production.
        var settings = stdout.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(l => !l.StartsWith('#'))
            .Select(l => (Key: l[..l.IndexOf('=', StringComparison.Ordinal)].Replace("__", ":", StringComparison.Ordinal), Value: l[(l.IndexOf('=', StringComparison.Ordinal) + 1)..]))
            .ToDictionary(p => p.Key, p => (string?)(p.Key.EndsWith(":Status", StringComparison.Ordinal) ? "Active" : p.Value), StringComparer.Ordinal);
        Assert.Equal(64, settings["Kms:HmacKeys:SeatCheck"]!.Length);
        settings["Kms:File:KeyDirectory"] = output;
        settings["Kms:File:NoOtherEnvironment"] = "true";
        settings["Kms:HmacKeys:Seat"] = "file:seat";
        settings["Kms:HmacKeys:Audit"] = "file:audit";
        settings["Kms:HmacKeys:InstallHashPepper"] = "file:install-pepper";
        settings["Kms:Envelope:KeyRef"] = "file:envelope";

        await using var services = FileKmsHost.Services("Production", settings);
        await FileKmsHost.StartAsync(services);
    }

    [LinuxFact]
    public void TheToolRefusesToRunInsideTheRepository()
    {
        var output = Path.Combine(root, "kms");

        // The test binaries are inside this repository (backend/tests/.../bin).
        var (code, _, stderr) = Run(FullSet, output, workingDirectory: AppContext.BaseDirectory);

        Assert.Equal(FileKeyTool.Usage, code);
        Assert.Contains("source tree", stderr, StringComparison.Ordinal);
        Assert.False(Directory.Exists(output));
    }

    [LinuxTheory]
    [InlineData("repo")]
    [InlineData("git-marker")]
    [InlineData("app")]
    public void TheToolRefusesToWriteIntoASourceTree(string where)
    {
        string output;
        switch (where)
        {
            case "repo":
                output = Path.Combine(AppContext.BaseDirectory, "kms-" + Guid.NewGuid().ToString("N"));
                break;
            case "git-marker":
                Directory.CreateDirectory(Path.Combine(root, "checkout", ".git"));
                output = Path.Combine(root, "checkout", "kms");
                break;
            default:
                output = Path.Combine(AppContext.BaseDirectory.TrimEnd('/'), "kms");
                break;
        }

        var (code, _, stderr) = Run(FullSet, output, workingDirectory: root);

        Assert.Equal(FileKeyTool.Usage, code);
        Assert.Contains("never be written there", stderr, StringComparison.Ordinal);
        Assert.False(Directory.Exists(output));
    }

    [LinuxFact]
    public void AnExistingOutputDirectoryIsRefusedAndLeftAlone()
    {
        var output = Path.Combine(root, "existing");
        Directory.CreateDirectory(output);
        File.WriteAllText(Path.Combine(output, "keep.txt"), "x");

        var (code, _, _) = Run(FullSet, output, workingDirectory: root);

        Assert.Equal(FileKeyTool.Usage, code);
        Assert.Equal(["keep.txt"], Directory.EnumerateFiles(output).Select(Path.GetFileName));
    }

    [LinuxTheory]
    [InlineData("--generate-keys --environment Development --out {out} --kid s2026a")]
    [InlineData("--generate-keys --environment Production --out {out} --kid s0000d")]
    [InlineData("--generate-keys --environment Production --out {out} --kid x2026a")]
    [InlineData("--generate-keys --environment Production --out {out} --secret Seat")]
    [InlineData("--generate-keys --environment Production --out {out} --secret seat --secret seat")]
    [InlineData("--generate-keys --environment Production --out {out}")]
    [InlineData("--generate-keys --environment Production --out relative/dir --kid s2026a")]
    [InlineData("--generate-keys --environment Production --out {out} --kid s2026a --out {out}")]
    [InlineData("--generate-keys --environment Production --out {out} --kid")]
    public void BadArgumentsAreRefused(string line)
    {
        var output = Path.Combine(root, "kms");

        var (code, stdout, _) = Run(line.Split(' '), output, workingDirectory: root);

        Assert.Equal(FileKeyTool.Usage, code);
        Assert.Empty(stdout);
        Assert.False(Directory.Exists(output));
    }

    [LinuxFact]
    public void AnUnknownArgumentIsNotEchoed()
    {
        var output = Path.Combine(root, "kms");

        var (code, stdout, stderr) = Run(["--generate-keys", "--private-key=SENTINEL-4711", "--out", "{out}"], output, workingDirectory: root);

        Assert.Equal(FileKeyTool.Usage, code);
        Assert.DoesNotContain("SENTINEL-4711", stdout + stderr, StringComparison.Ordinal);
    }

    [LinuxFact]
    public void ARotationKeyAloneIsWrittenWithItsRingEntry()
    {
        var output = Path.Combine(root, "rotation");

        var (code, stdout, stderr) = Run(["--generate-keys", "--environment", "Staging", "--out", "{out}", "--kid", "s2027a"], output, workingDirectory: root);

        Assert.True(code == FileKeyTool.Ok, stderr);
        Assert.Equal(["s2027a.pem"], Directory.EnumerateFiles(output).Select(Path.GetFileName));
        Assert.Contains("Signing__Keys__0__Status=Next", stdout, StringComparison.Ordinal);
        Assert.Contains("Kms__File__Fingerprints__s2027a=", stdout, StringComparison.Ordinal);
        Assert.DoesNotContain("Kms__HmacKeys__SeatCheck", stdout, StringComparison.Ordinal);
    }

    private static (int Code, string Stdout, string Stderr) Run(IEnumerable<string> args, string output, string workingDirectory)
    {
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var code = FileKeyTool.Run(args.Select(a => a.Replace("{out}", output, StringComparison.Ordinal)).ToList(), stdout, stderr, workingDirectory);
        return (code, stdout.ToString(), stderr.ToString());
    }
}

internal static class FileKmsKeySetModes
{
    public const UnixFileMode Mode0700 = UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute;
    public const UnixFileMode Mode0500 = UnixFileMode.UserRead | UnixFileMode.UserExecute;
    public const UnixFileMode Mode0400 = UnixFileMode.UserRead;
}
