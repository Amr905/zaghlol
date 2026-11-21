using System.Runtime.Versioning;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Workers.Tests;

/// <summary>
/// T-205 acceptance 1 and 3 end to end: the settings printed by <c>--generate-keys --format host-secrets</c>, passed as
/// environment variables exactly as the host injects them, start the shipped worker in Production (ring verified, no key
/// material in its output); without <c>Kms__AcceptSharedHostCustody</c> it stops.
/// </summary>
[SupportedOSPlatform("linux")]
public sealed class HostSecretsWorkerTests : IDisposable
{
    private readonly string root = Directory.CreateTempSubdirectory("zaghlol-worker-host-").FullName;

    public void Dispose() => Directory.Delete(root, recursive: true);

    [WorkerLinuxFact]
    public async Task TheToolOutputStartsTheWorkerFromEnvironmentVariables()
    {
        var (settings, secrets) = Generate();
        settings["Kms__AcceptSharedHostCustody"] = "true";

        var (exited, output) = await FileKmsWorkerTests.RunWorkerAsync(root, "Production", settings, until: "KMS key ring verified");

        Assert.False(exited, "the worker stopped: " + output);
        Assert.Contains("KMS key ring verified", output, StringComparison.Ordinal);
        Assert.All(secrets, s => Assert.DoesNotContain(s, output, StringComparison.Ordinal));
        Assert.Empty(Directory.EnumerateFileSystemEntries(Path.Combine(root, "tool"))); // the tool wrote nothing
    }

    [WorkerLinuxFact]
    public async Task WithoutTheCustodyFlagTheWorkerStops()
    {
        var (settings, secrets) = Generate();

        var (exited, output) = await FileKmsWorkerTests.RunWorkerAsync(root, "Production", settings, until: null);

        Assert.True(exited);
        Assert.Contains("Kms:AcceptSharedHostCustody = true", output, StringComparison.Ordinal);
        Assert.DoesNotContain("KMS key ring verified", output, StringComparison.Ordinal);
        Assert.All(secrets, s => Assert.DoesNotContain(s, output, StringComparison.Ordinal));
    }

    private (Dictionary<string, string> Settings, List<string> Secrets) Generate()
    {
        var cwd = Directory.CreateDirectory(Path.Combine(root, "tool")).FullName;
        using var stdout = new StringWriter();
        using var stderr = new StringWriter();
        var code = FileKeyTool.Run(
            ["--generate-keys", "--format", "host-secrets", "--environment", "Production", "--kid", "s2026a", "--kid", "e2026a", "--secret", "seat", "--secret", "audit", "--secret", "install-pepper", "--secret", "envelope"],
            stdout,
            stderr,
            cwd);
        Assert.True(code == 0, stderr.ToString());

        var settings = stdout.ToString().Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(l => !l.StartsWith('#'))
            .Select(l => (Key: l[..l.IndexOf('=', StringComparison.Ordinal)], Value: l[(l.IndexOf('=', StringComparison.Ordinal) + 1)..]))
            .ToDictionary(p => p.Key, p => p.Key.EndsWith("__Status", StringComparison.Ordinal) ? "Active" : p.Value, StringComparer.Ordinal);
        var secrets = settings.Where(p => p.Key.StartsWith("ZAGHLOL_KEYS__", StringComparison.Ordinal)).Select(p => p.Value).ToList();
        Assert.Equal(6, secrets.Count);
        settings["Kms__File__NoOtherEnvironment"] = "true";
        settings["Kms__HmacKeys__Seat"] = "file:seat";
        settings["Kms__HmacKeys__Audit"] = "file:audit";
        settings["Kms__HmacKeys__InstallHashPepper"] = "file:install-pepper";
        settings["Kms__Envelope__KeyRef"] = "file:envelope";
        return (settings, secrets);
    }
}
