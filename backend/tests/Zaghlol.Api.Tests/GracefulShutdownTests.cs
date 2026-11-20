using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Net.Sockets;

namespace Zaghlol.Api.Tests;

/// <summary>
/// BUG-002 (QA audit 2026-11-19): the real API process stops cleanly on SIGTERM, as Docker, Cloud Run and Kubernetes send it.
/// <c>Program</c> used to read <c>HostExitCode</c> from the service provider after <c>RunAsync</c> had disposed it, so every
/// graceful stop crashed with <see cref="ObjectDisposedException"/> and exit code 134. <c>WebApplicationFactory</c> never runs
/// the code after <c>RunAsync</c>, so this test starts the built <c>Zaghlol.Api.dll</c> as a child process.
/// </summary>
[Collection(ApiHostGroup.Name)]
public sealed class GracefulShutdownTests : IDisposable
{
    private const string Unreachable = "Host=127.0.0.1;Port=1;Database=none;Username=none";

    private readonly string keyDir = Path.Combine(Path.GetTempPath(), "zaghlol-shutdown-" + Guid.NewGuid().ToString("N"));

    [UnixFact]
    public async Task TheApiExitsZeroOnSigterm()
    {
        var devKeys = Path.Combine(FindBackendRoot(), "tools", "dev-keys.sh");
        Directory.CreateDirectory(keyDir);
        var keys = await RunAsync("sh", [devKeys], new Dictionary<string, string> { ["DEV_KEYS_DIR"] = keyDir });
        Assert.True(keys.ExitCode == 0, "dev-keys.sh failed: " + keys.Output);

        // kms.env names the Docker mount as the key directory; point it at the temp folder instead.
        var envFile = Path.Combine(keyDir, "kms.env");
        var lines = (await File.ReadAllLinesAsync(envFile))
            .Select(l => l.StartsWith("Kms__Local__KeyDirectory=", StringComparison.Ordinal) ? "Kms__Local__KeyDirectory=" + keyDir : l);
        await File.WriteAllLinesAsync(envFile, lines);

        var port = FreePort();
        var start = new ProcessStartInfo("dotnet")
        {
            WorkingDirectory = AppContext.BaseDirectory,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        start.ArgumentList.Add(Path.Combine(AppContext.BaseDirectory, "Zaghlol.Api.dll"));
        start.Environment["ASPNETCORE_ENVIRONMENT"] = "Development";
        start.Environment["ASPNETCORE_URLS"] = string.Create(CultureInfo.InvariantCulture, $"http://127.0.0.1:{port}");
        // The database is unreachable on purpose: the role guard retries quietly and the host still starts (readiness 503).
        start.Environment["ConnectionStrings__App"] = Unreachable;
        start.Environment["ConnectionStrings__Admin"] = Unreachable;
        start.Environment["Dev__KeyEnvFile"] = envFile;

        using var api = Process.Start(start)!;
        var output = CollectAsync(api);
        try
        {
            // No proxy: a CI or workspace HTTP(S)_PROXY must not carry a loopback request.
            using var handler = new HttpClientHandler { UseProxy = false };
            using var http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(2) };
            var deadline = DateTime.UtcNow.AddSeconds(60);
            var up = false;
            while (!up && DateTime.UtcNow < deadline && !api.HasExited)
            {
                try
                {
                    using var response = await http.GetAsync(new Uri(string.Create(CultureInfo.InvariantCulture, $"http://127.0.0.1:{port}/v1/health")));
                    up = true;
                }
                catch (HttpRequestException)
                {
                    await Task.Delay(250);
                }
                catch (TaskCanceledException)
                {
                    await Task.Delay(250);
                }
            }

            if (!up)
            {
                api.Kill(entireProcessTree: true);
                Assert.Fail("the API did not answer /v1/health: " + await output);
            }

            var kill = await RunAsync("kill", ["-TERM", api.Id.ToString(CultureInfo.InvariantCulture)]);
            Assert.Equal(0, kill.ExitCode);

            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            await api.WaitForExitAsync(timeout.Token);
            var log = await output;

            Assert.DoesNotContain("ObjectDisposedException", log, StringComparison.Ordinal);
            Assert.True(api.ExitCode == 0, $"exit code {api.ExitCode}: {log}");
        }
        finally
        {
            if (!api.HasExited)
            {
                api.Kill(entireProcessTree: true);
            }
        }
    }

    public void Dispose()
    {
        if (Directory.Exists(keyDir))
        {
            Directory.Delete(keyDir, recursive: true);
        }
    }

    private static async Task<string> CollectAsync(Process process)
    {
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        return await stdout + await stderr;
    }

    private static async Task<(int ExitCode, string Output)> RunAsync(string file, string[] args, Dictionary<string, string>? env = null)
    {
        var start = new ProcessStartInfo(file) { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false };
        foreach (var arg in args)
        {
            start.ArgumentList.Add(arg);
        }

        foreach (var (key, value) in env ?? [])
        {
            start.Environment[key] = value;
        }

        using var process = Process.Start(start)!;
        var output = CollectAsync(process);
        await process.WaitForExitAsync();
        return (process.ExitCode, await output);
    }

    private static int FreePort()
    {
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        return ((IPEndPoint)listener.LocalEndpoint).Port;
    }

    private static string FindBackendRoot()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            if (File.Exists(Path.Combine(dir.FullName, "tools", "dev-keys.sh")) && File.Exists(Path.Combine(dir.FullName, "Zaghlol.sln")))
            {
                return dir.FullName;
            }
        }

        throw new InvalidOperationException("backend/ not found above " + AppContext.BaseDirectory);
    }
}

/// <summary>A fact that runs only on Linux and macOS (it sends a POSIX signal and runs a shell script).</summary>
public sealed class UnixFactAttribute : FactAttribute
{
    public UnixFactAttribute()
    {
        if (OperatingSystem.IsWindows())
        {
            Skip = "Needs POSIX signals and sh.";
        }
    }
}
