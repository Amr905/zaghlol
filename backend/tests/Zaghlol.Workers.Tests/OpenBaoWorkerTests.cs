using System.Runtime.Versioning;
using Zaghlol.Testing;

namespace Zaghlol.Workers.Tests;

/// <summary>
/// T-201 acceptance 1 through the shipped worker binary: after the T-200 migration the worker starts in Production with
/// <c>Kms:Provider = OpenBao</c>, <c>Kms:Scope = Envelope</c> and its own AppRole (envelope keys only); with the API's full
/// scope its policy refuses the signing keys, so it stops. No credential or key appears in its output.
/// </summary>
[SupportedOSPlatform("linux")]
public sealed class OpenBaoWorkerTests : IAsyncLifetime
{
    private readonly string root = Directory.CreateTempSubdirectory("zaghlol-worker-openbao-").FullName;
    private OpenBaoTestBed bed = null!;

    public async Task InitializeAsync() => bed = await OpenBaoTestBed.CreateAsync();

    public async Task DisposeAsync()
    {
        await bed.DisposeAsync();
        Directory.Delete(root, recursive: true);
    }

    [WorkerLinuxFact]
    public async Task TheWorkerStartsWithEnvelopeKeysOnly()
    {
        var (exited, output) = await FileKmsWorkerTests.RunWorkerAsync(root, "Production", Env(bed.Settings(worker: true)), until: "KMS envelope keys verified");

        Assert.False(exited, "the worker stopped: " + output);
        Assert.Contains("KMS envelope keys verified (Kms:Scope = Envelope)", output, StringComparison.Ordinal);
        Assert.DoesNotContain(bed.Stub.Requests, r => r.Contains("/transit/sign/", StringComparison.Ordinal) && !r.Contains("import", StringComparison.Ordinal));
        AssertNoSecrets(output);
    }

    [WorkerLinuxFact]
    public async Task TheWorkerAppRoleCanNotRunWithTheFullScope()
    {
        var settings = bed.Settings(worker: true);
        settings.Remove("Kms:Scope");

        var (exited, output) = await FileKmsWorkerTests.RunWorkerAsync(root, "Production", Env(settings), until: null);

        Assert.True(exited);
        Assert.Contains("OpenBao could not be used at start", output, StringComparison.Ordinal);
        Assert.DoesNotContain("KMS key ring verified", output, StringComparison.Ordinal);
        AssertNoSecrets(output);
    }

    private static Dictionary<string, string> Env(Dictionary<string, string?> settings) =>
        settings.Where(p => p.Value is not null).ToDictionary(p => p.Key.Replace(":", "__", StringComparison.Ordinal), p => p.Value!, StringComparer.Ordinal);

    private void AssertNoSecrets(string output)
    {
        foreach (var sentinel in bed.Sentinels)
        {
            Assert.DoesNotContain(sentinel, output, StringComparison.OrdinalIgnoreCase);
        }
    }
}
