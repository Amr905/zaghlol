using System.Diagnostics;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;

namespace Zaghlol.Workers.Tests;

/// <summary>
/// T-200 acceptance 2–4 end to end through the shipped worker binary: <c>--generate-keys</c> writes a production key set, and
/// the worker started in Staging or Production with the printed settings verifies the ring and runs (database unreachable on
/// purpose; jobs log and retry). A group-readable key stops it with a non-zero exit and no key material in its output.
/// </summary>
[SupportedOSPlatform("linux")]
public sealed class FileKmsWorkerTests : IDisposable
{
    private const string Unreachable = "Host=127.0.0.1;Port=1;Database=none;Username=none";

    private readonly string root = Directory.CreateTempSubdirectory("zaghlol-worker-kms-").FullName;

    public void Dispose()
    {
        foreach (var dir in Directory.EnumerateDirectories(root, "*", SearchOption.AllDirectories))
        {
            File.SetUnixFileMode(dir, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        }

        Directory.Delete(root, recursive: true);
    }

    [WorkerLinuxTheory]
    [InlineData("Staging")]
    [InlineData("Production")]
    public async Task TheKeyToolOutputStartsTheWorker(string environment)
    {
        var (keys, settings) = await GenerateAsync(environment);

        var (exited, output) = await RunWorkerAsync(environment, settings, until: "KMS key ring verified");

        Assert.False(exited, "the worker stopped: " + output);
        Assert.Contains("KMS key ring verified", output, StringComparison.Ordinal);
        Assert.DoesNotContain("Hosting failed to start", output, StringComparison.Ordinal);
        AssertNoKeyMaterial(keys, output);
    }

    /// <summary>
    /// BUG-002 / FU-263 F8: the worker's copy of the exit-code read (resolved before <c>RunAsync</c> disposes the host) is covered
    /// here; SIGTERM, as Docker and Kubernetes send it, ends the real process with exit code 0 and no disposed-provider error.
    /// </summary>
    [WorkerLinuxFact]
    public async Task TheWorkerExitsZeroOnSigterm()
    {
        var (_, settings) = await GenerateAsync("Production");

        var (code, output) = await RunWorkerAsync(root, "Production", settings, until: "KMS key ring verified", sigterm: true);

        Assert.True(code == 0, $"exit code {code}: {output}");
        Assert.DoesNotContain("ObjectDisposedException", output, StringComparison.Ordinal);
    }

    [WorkerLinuxFact]
    public async Task AGroupReadableKeyStopsTheWorker()
    {
        var (keys, settings) = await GenerateAsync("Production");
        File.SetUnixFileMode(keys, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        File.SetUnixFileMode(Path.Combine(keys, "audit.key"), UnixFileMode.UserRead | UnixFileMode.OtherRead);
        File.SetUnixFileMode(keys, UnixFileMode.UserRead | UnixFileMode.UserExecute);

        var (exited, output) = await RunWorkerAsync("Production", settings, until: null);

        Assert.True(exited);
        Assert.Contains("KmsConfigurationException", output, StringComparison.Ordinal);
        Assert.Contains("group/other accessible", output, StringComparison.Ordinal);
        Assert.DoesNotContain("KMS key ring verified", output, StringComparison.Ordinal);
        Assert.DoesNotContain(keys, output, StringComparison.Ordinal);
        AssertNoKeyMaterial(keys, output);
    }

    [WorkerLinuxFact]
    public async Task TheKeyToolRefusesToRunInsideTheRepository()
    {
        var output = Path.Combine(root, "refused");

        var (code, text) = await RunAsync(
            ["--generate-keys", "--environment", "Production", "--out", output, "--kid", "s2026a"],
            new Dictionary<string, string>(),
            workingDirectory: AppContext.BaseDirectory,
            until: null,
            timeout: TimeSpan.FromSeconds(60));

        Assert.Equal(2, code);
        Assert.Contains("source tree", text, StringComparison.Ordinal);
        Assert.False(Directory.Exists(output));
    }

    private static void AssertNoKeyMaterial(string keys, string output)
    {
        File.SetUnixFileMode(keys, UnixFileMode.UserRead | UnixFileMode.UserExecute);
        foreach (var file in Directory.EnumerateFiles(keys))
        {
            var text = File.ReadAllText(file);
            var sentinels = file.EndsWith(".pem", StringComparison.Ordinal)
                ? text.Split('\n').Where(l => l.Length >= 16 && !l.StartsWith("-----", StringComparison.Ordinal)).ToList()
                : [text.Trim(), Convert.ToHexStringLower(Convert.FromBase64String(text.Trim()))];
            foreach (var sentinel in sentinels)
            {
                Assert.DoesNotContain(sentinel, output, StringComparison.OrdinalIgnoreCase);
            }
        }
    }

    /// <summary>Runs the tool in a scratch folder outside the repository; returns the key folder and the settings as env vars.</summary>
    private async Task<(string Keys, Dictionary<string, string> Settings)> GenerateAsync(string environment)
    {
        var scratch = Directory.CreateDirectory(Path.Combine(root, "tool")).FullName;
        var keys = Path.Combine(root, "kms");
        var (code, stdout) = await RunAsync(
            ["--generate-keys", "--environment", environment, "--out", keys, "--kid", "s2026a", "--kid", "e2026a", "--secret", "seat", "--secret", "audit", "--secret", "install-pepper", "--secret", "envelope"],
            new Dictionary<string, string>(),
            scratch,
            until: null,
            timeout: TimeSpan.FromSeconds(60));
        Assert.True(code == 0, stdout);

        var settings = stdout.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(l => !l.StartsWith('#'))
            .Select(l => (Key: l[..l.IndexOf('=', StringComparison.Ordinal)], Value: l[(l.IndexOf('=', StringComparison.Ordinal) + 1)..]))
            .ToDictionary(p => p.Key, p => p.Key.EndsWith("__Status", StringComparison.Ordinal) ? "Active" : p.Value, StringComparer.Ordinal);
        settings["Kms__File__KeyDirectory"] = keys;
        settings["Kms__File__NoOtherEnvironment"] = "true";
        settings["Kms__HmacKeys__Seat"] = "file:seat";
        settings["Kms__HmacKeys__Audit"] = "file:audit";
        settings["Kms__HmacKeys__InstallHashPepper"] = "file:install-pepper";
        settings["Kms__Envelope__KeyRef"] = "file:envelope";
        return (keys, settings);
    }

    private Task<(bool Exited, string Output)> RunWorkerAsync(string environment, Dictionary<string, string> kms, string? until) =>
        RunWorkerAsync(root, environment, kms, until);

    /// <summary>Starts the worker binary with Production-complete settings plus <paramref name="kms"/> (also used by T-201).</summary>
    internal static async Task<(bool Exited, string Output)> RunWorkerAsync(string root, string environment, Dictionary<string, string> kms, string? until)
    {
        var (code, output) = await RunWorkerAsync(root, environment, kms, until, sigterm: false);
        return (code is not null, output);
    }

    /// <summary>Same, returning the exit code (null when it was killed); with <paramref name="sigterm"/> sends SIGTERM once <paramref name="until"/> appears and waits for a clean exit.</summary>
    internal static async Task<(int? Code, string Output)> RunWorkerAsync(string root, string environment, Dictionary<string, string> kms, string? until, bool sigterm)
    {
        using var appleKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var env = new Dictionary<string, string>(kms, StringComparer.Ordinal)
        {
            ["DOTNET_ENVIRONMENT"] = environment,
            ["ConnectionStrings__Worker"] = Unreachable,
            ["Purchases__Google__PackageName"] = "app.zaghlol",
            ["Purchases__Google__CredentialSource"] = "ApplicationDefault",
            ["Purchases__Google__Rtdn__Audience"] = "https://api.zaghlol.app/v1/notifications/google",
            ["Purchases__Google__Rtdn__PushServiceAccount"] = "push@zaghlol-test.iam.gserviceaccount.com",
            ["Purchases__Apple__BundleId"] = "app.zaghlol",
            ["Purchases__Apple__AllowSandbox"] = "true",
            ["Purchases__Apple__IssuerId"] = "57246542-96fe-1a63-e053-0824d011072a",
            ["Purchases__Apple__KeyId"] = "ABCDE12345",
            ["Purchases__Apple__PrivateKey"] = appleKey.ExportPkcs8PrivateKeyPem(),
            ["Accounts__Google__ClientIds__0"] = "123-abc.apps.googleusercontent.com",
            ["Accounts__Apple__ServicesId"] = "app.zaghlol.signin",
            ["Accounts__Apple__BundleId"] = "app.zaghlol",
            ["Accounts__Apple__TeamId"] = "ABCDE12345",
            ["Accounts__Apple__KeyId"] = "ABCDE12345",
            ["Accounts__Apple__PrivateKey"] = appleKey.ExportPkcs8PrivateKeyPem(),
            ["Worker__HeartbeatFile"] = Path.Combine(root, "heartbeat"),
        };
        foreach (var (plan, kind, type) in new[] { ("monthly", "subscription", "auto_renewable"), ("yearly", "subscription", "auto_renewable"), ("lifetime", "onetime", "non_consumable") })
        {
            env[$"Purchases__Google__Products__zaghlol_gold_{plan}__Kind"] = kind;
            env[$"Purchases__Google__Products__zaghlol_gold_{plan}__Plan"] = plan;
            env[$"Purchases__Apple__Products__zaghlol_gold_{plan}__Type"] = type;
            env[$"Purchases__Apple__Products__zaghlol_gold_{plan}__Plan"] = plan;
        }

        // The content root is the working directory: keep it apart from the key folder (guard G8).
        var workingDirectory = Directory.CreateDirectory(Path.Combine(root, "run")).FullName;
        return await RunAsync([], env, workingDirectory, until, TimeSpan.FromSeconds(90), sigterm);
    }

    /// <summary>
    /// The worker as built by its own project (same configuration and framework as this test), not the copy in this test's
    /// output: this project also references the ASP.NET Core framework (the T-201 OpenBao stub), which leaves the worker's own
    /// dependencies out of the test output.
    /// </summary>
    internal static string WorkerDll
    {
        get
        {
            var output = new DirectoryInfo(AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar));
            var framework = output.Name;
            var configuration = output.Parent!.Name;
            var backend = output.Parent!.Parent!.Parent!.Parent!.Parent!.FullName;
            return Path.Combine(backend, "src", "Zaghlol.Workers", "bin", configuration, framework, "Zaghlol.Workers.dll");
        }
    }

    /// <summary>Runs Zaghlol.Workers.dll. With <paramref name="until"/>, stops it (SIGTERM) once that text appears; the code is then null.</summary>
    private static async Task<(int? Code, string Output)> RunAsync(
        IEnumerable<string> args,
        Dictionary<string, string> environment,
        string workingDirectory,
        string? until,
        TimeSpan timeout,
        bool sigterm = false)
    {
        var start = new ProcessStartInfo("dotnet")
        {
            WorkingDirectory = workingDirectory,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        start.ArgumentList.Add(WorkerDll);
        foreach (var arg in args)
        {
            start.ArgumentList.Add(arg);
        }

        // Inherited Kms/connection settings from the test runner must not leak in.
        foreach (var key in start.Environment.Keys.Where(k => k.StartsWith("Kms__", StringComparison.Ordinal) || k.StartsWith("Signing__", StringComparison.Ordinal)).ToList())
        {
            start.Environment.Remove(key);
        }

        foreach (var (key, value) in environment)
        {
            start.Environment[key] = value;
        }

        using var process = Process.Start(start)!;
        var output = new StringBuilder();
        var seen = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        void OnLine(object sender, DataReceivedEventArgs e)
        {
            if (e.Data is null)
            {
                return;
            }

            lock (output)
            {
                output.AppendLine(e.Data);
            }

            if (until is not null && e.Data.Contains(until, StringComparison.Ordinal))
            {
                seen.TrySetResult();
            }
        }

        process.OutputDataReceived += OnLine;
        process.ErrorDataReceived += OnLine;
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        var exit = process.WaitForExitAsync();
        var finished = await Task.WhenAny(exit, seen.Task, Task.Delay(timeout));
        int? code = null;
        if (finished == exit)
        {
            await exit;
            code = process.ExitCode;
        }
        else if (sigterm && finished == seen.Task)
        {
            using var kill = Process.Start("kill", ["-TERM", process.Id.ToString(System.Globalization.CultureInfo.InvariantCulture)])!;
            await kill.WaitForExitAsync();
            using var limit = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            try
            {
                await process.WaitForExitAsync(limit.Token);
                code = process.ExitCode;
            }
            catch (OperationCanceledException)
            {
                process.Kill(entireProcessTree: true);
                await process.WaitForExitAsync();
            }
        }
        else
        {
            process.Kill(entireProcessTree: true);
            await process.WaitForExitAsync();
        }

        lock (output)
        {
            return (code, output.ToString());
        }
    }
}

/// <summary>A [Fact] that runs only on Linux (the File KMS checks POSIX owner and mode).</summary>
public sealed class WorkerLinuxFactAttribute : FactAttribute
{
    public WorkerLinuxFactAttribute()
    {
        if (!OperatingSystem.IsLinux())
        {
            Skip = "Linux only: the File KMS refuses other systems.";
        }
    }
}

/// <summary>A [Theory] that runs only on Linux.</summary>
public sealed class WorkerLinuxTheoryAttribute : TheoryAttribute
{
    public WorkerLinuxTheoryAttribute()
    {
        if (!OperatingSystem.IsLinux())
        {
            Skip = "Linux only: the File KMS refuses other systems.";
        }
    }
}
