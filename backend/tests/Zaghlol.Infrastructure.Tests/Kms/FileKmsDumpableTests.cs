using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>Runs alone: the dumpable flag is process-wide and other File KMS tests set it.</summary>
[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class DumpableGroup
{
    public const string Name = "process-dumpable-flag";
}

/// <summary>
/// Review S2: in Staging and Production the File KMS marks the process non-dumpable (<c>PR_SET_DUMPABLE 0</c>) before it
/// reads a key, read back with <c>PR_GET_DUMPABLE</c>; Development and Testing leave the flag alone.
/// </summary>
[Collection(DumpableGroup.Name)]
[SupportedOSPlatform("linux")]
public sealed class FileKmsDumpableTests : IDisposable
{
    private const int PrGetDumpable = 3;
    private const int PrSetDumpable = 4;

    private readonly FileKmsKeySet keys = new();

    public void Dispose()
    {
        // Give the test host its default back so later tests and crash diagnostics behave as usual.
        if (OperatingSystem.IsLinux())
        {
            _ = prctl(PrSetDumpable, 1, 0, 0, 0);
        }

        keys.Dispose();
    }

    [LinuxTheory]
    [InlineData("Staging")]
    [InlineData("Production")]
    public async Task StagingAndProductionMakeTheProcessNonDumpable(string environment)
    {
        Assert.Equal(0, prctl(PrSetDumpable, 1, 0, 0, 0));
        Assert.Equal(1, prctl(PrGetDumpable, 0, 0, 0, 0));
        await using var services = FileKmsHost.Services(environment, keys.Settings());

        await FileKmsHost.StartAsync(services);

        Assert.Equal(0, prctl(PrGetDumpable, 0, 0, 0, 0));
        Assert.Equal(0, PosixFiles.Dumpable());
    }

    [LinuxFact]
    public async Task TestingLeavesTheFlagAlone()
    {
        Assert.Equal(0, prctl(PrSetDumpable, 1, 0, 0, 0));
        await using var services = FileKmsHost.Services("Testing", keys.Settings());

        await FileKmsHost.StartAsync(services);

        Assert.Equal(1, prctl(PrGetDumpable, 0, 0, 0, 0));
    }

    [DllImport("libc.so.6")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.SafeDirectories)]
#pragma warning disable SYSLIB1054 // A test-only call; the product's own P/Invoke is in PosixFiles.
    private static extern int prctl(int option, nuint arg2, nuint arg3, nuint arg4, nuint arg5);
#pragma warning restore SYSLIB1054
}
