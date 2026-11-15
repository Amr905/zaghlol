using System.Diagnostics;

namespace Zaghlol.Api.Tests.Dev;

/// <summary>Batch-23a B2: <c>tools/dev-keys.sh</c> never empties a folder it didn't create.</summary>
public sealed class DevKeysScriptTests
{
    private static string Script()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, "tools", "dev-keys.sh");
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new FileNotFoundException("tools/dev-keys.sh");
    }

    private static (int Exit, string Error) Run(string keysDir, params string[] arguments)
    {
        var start = new ProcessStartInfo("sh") { RedirectStandardError = true, RedirectStandardOutput = true };
        start.ArgumentList.Add(Script());
        foreach (var argument in arguments)
        {
            start.ArgumentList.Add(argument);
        }

        start.Environment["DEV_KEYS_DIR"] = keysDir;
        using var process = Process.Start(start)!;
        var error = process.StandardError.ReadToEnd();
        process.StandardOutput.ReadToEnd();
        process.WaitForExit();
        return (process.ExitCode, error);
    }

    [Fact]
    public void ARandomNonEmptyFolderIsRefusedAndKeptIntact()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var dir = Directory.CreateTempSubdirectory("dev-keys-").FullName;
        try
        {
            var precious = Path.Combine(dir, "precious.txt");
            File.WriteAllText(precious, "keep me");

            var (exit, error) = Run(dir, "--force");

            Assert.NotEqual(0, exit);
            Assert.Contains("refusing", error, StringComparison.Ordinal);
            Assert.True(File.Exists(precious));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void ForceReplacesOnlyItsOwnFilesInAKeysFolder()
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        var dir = Directory.CreateTempSubdirectory("dev-keys-").FullName;
        try
        {
            Assert.Equal(0, Run(dir).Exit);
            var other = Path.Combine(dir, "notes.txt");
            File.WriteAllText(other, "mine");

            Assert.Equal(0, Run(dir, "--force").Exit);

            Assert.True(File.Exists(Path.Combine(dir, "kms.env")));
            Assert.True(File.Exists(other));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }
}
