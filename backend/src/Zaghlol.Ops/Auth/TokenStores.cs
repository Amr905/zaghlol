using System.ComponentModel;
using System.Diagnostics;
using System.Text;

namespace Zaghlol.Ops.Auth;

/// <summary>
/// Where a signed-in token is kept between runs (T-137 design note section 2): the OS credential store, or memory. There is
/// no implementation that writes a file. A store that cannot work (no tool, no service, value not storable) says so by
/// returning <c>false</c> or <c>null</c> and never by falling back to something weaker.
/// </summary>
internal interface ITokenStore
{
    /// <summary>A fixed label for status output (<c>memory</c>, <c>windows-credential-manager</c>, <c>keychain</c>, <c>secret-service</c>).</summary>
    string Name { get; }

    /// <summary>The stored value, or <c>null</c> when absent or the store is unavailable.</summary>
    Task<string?> ReadAsync(string key, CancellationToken cancellationToken);

    /// <summary>True only when the value was stored and read back.</summary>
    Task<bool> WriteAsync(string key, string value, CancellationToken cancellationToken);

    /// <summary>True when nothing is stored afterwards.</summary>
    Task<bool> DeleteAsync(string key, CancellationToken cancellationToken);
}

/// <summary>Memory for this process only.</summary>
internal sealed class MemoryTokenStore : ITokenStore
{
    private readonly Dictionary<string, string> values = new(StringComparer.Ordinal);

    public string Name => "memory";

    public Task<string?> ReadAsync(string key, CancellationToken cancellationToken) => Task.FromResult(values.GetValueOrDefault(key));

    public Task<bool> WriteAsync(string key, string value, CancellationToken cancellationToken)
    {
        values[key] = value;
        return Task.FromResult(true);
    }

    public Task<bool> DeleteAsync(string key, CancellationToken cancellationToken)
    {
        values.Remove(key);
        return Task.FromResult(true);
    }
}

/// <summary>The result of one child process.</summary>
internal sealed record ProcessResult(int ExitCode, string StandardOutput);

/// <summary>Runs a program without a shell. <c>Arguments</c> are a list (never joined), and <c>StandardInput</c> carries secrets.</summary>
internal interface IProcessRunner
{
    /// <summary>The result, or <c>null</c> when the program cannot be started or times out.</summary>
    Task<ProcessResult?> RunAsync(string fileName, IReadOnlyList<string> arguments, string? standardInput, TimeSpan timeout, CancellationToken cancellationToken);
}

internal sealed class ProcessRunner : IProcessRunner
{
    public async Task<ProcessResult?> RunAsync(string fileName, IReadOnlyList<string> arguments, string? standardInput, TimeSpan timeout, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(arguments);

        var start = new ProcessStartInfo(fileName)
        {
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            CreateNoWindow = true,
        };
        foreach (var argument in arguments)
        {
            start.ArgumentList.Add(argument);
        }

        Process process;
        try
        {
            process = Process.Start(start) ?? throw new InvalidOperationException();
        }
        catch (Exception e) when (e is Win32Exception or InvalidOperationException)
        {
            return null;
        }

        using (process)
        using (var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken))
        {
            cts.CancelAfter(timeout);
            try
            {
                var output = process.StandardOutput.ReadToEndAsync(cts.Token);
                _ = process.StandardError.ReadToEndAsync(cts.Token);
                try
                {
                    if (standardInput is not null)
                    {
                        await process.StandardInput.WriteAsync(standardInput.AsMemory(), cts.Token).ConfigureAwait(false);
                    }

                    process.StandardInput.Close();
                }
                catch (IOException)
                {
                    // The child closed its input early; its exit code says what happened.
                }

                await process.WaitForExitAsync(cts.Token).ConfigureAwait(false);
                return new ProcessResult(process.ExitCode, await output.ConfigureAwait(false));
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                process.Kill(entireProcessTree: true);
                return null;
            }
        }
    }
}

/// <summary>
/// macOS Keychain (<c>security -i</c>, commands read from stdin) and Linux Secret Service (<c>secret-tool</c>, secret read from
/// stdin). The secret is never an argument, because arguments are readable by every user through the process list. A write
/// is confirmed by reading the value back.
/// </summary>
internal sealed class ProcessTokenStore : ITokenStore
{
    public const string Service = "zaghlol-ops";

    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(30);

    private readonly IProcessRunner runner;
    private readonly bool mac;
    private readonly string tool;

    public ProcessTokenStore(IProcessRunner runner, bool mac, string? toolPath = null)
    {
        ArgumentNullException.ThrowIfNull(runner);
        this.runner = runner;
        this.mac = mac;
        tool = toolPath ?? (mac ? "/usr/bin/security" : "secret-tool");
    }

    public string Name => mac ? "keychain" : "secret-service";

    public async Task<string?> ReadAsync(string key, CancellationToken cancellationToken)
    {
        var args = mac
            ? new[] { "find-generic-password", "-a", key, "-s", Service, "-w" }
            : ["lookup", "service", Service, "account", key];
        var result = await runner.RunAsync(tool, args, null, Timeout, cancellationToken).ConfigureAwait(false);
        if (result is not { ExitCode: 0 })
        {
            return null;
        }

        var value = result.StandardOutput.Trim();
        return value.Length == 0 ? null : value;
    }

    public async Task<bool> WriteAsync(string key, string value, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(value);

        // Only the characters of a token and of a cache key go anywhere near a command line (macOS) or a label (Linux).
        if (!IsSafe(key) || !IsSafe(value))
        {
            return false;
        }

        ProcessResult? result;
        if (mac)
        {
            // `security -i` takes its commands from stdin, so the token never appears in the argument list.
            var commands = $"add-generic-password -U -a \"{key}\" -s \"{Service}\" -w \"{value}\"\n";
            result = await runner.RunAsync(tool, ["-i"], commands, Timeout, cancellationToken).ConfigureAwait(false);
        }
        else
        {
            result = await runner.RunAsync(tool, ["store", "--label", "zaghlol-ops sign-in token", "service", Service, "account", key], value, Timeout, cancellationToken).ConfigureAwait(false);
        }

        if (result is null)
        {
            return false;
        }

        return string.Equals(await ReadAsync(key, cancellationToken).ConfigureAwait(false), value, StringComparison.Ordinal);
    }

    public async Task<bool> DeleteAsync(string key, CancellationToken cancellationToken)
    {
        var args = mac
            ? new[] { "delete-generic-password", "-a", key, "-s", Service }
            : ["clear", "service", Service, "account", key];
        var result = await runner.RunAsync(tool, args, null, Timeout, cancellationToken).ConfigureAwait(false);
        return result is not null && await ReadAsync(key, cancellationToken).ConfigureAwait(false) is null;
    }

    private static bool IsSafe(string text) =>
        text.Length is > 0 and <= 16384 && text.All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '-' or '_');
}
