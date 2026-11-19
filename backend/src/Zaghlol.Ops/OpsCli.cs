using Zaghlol.Ops.Auth;
using Zaghlol.Ops.Cli;
using Zaghlol.Ops.Commands;

namespace Zaghlol.Ops;

/// <summary>The <c>zaghlol-ops</c> operator CLI: parse, run one command, map the outcome to an exit code.</summary>
internal static class OpsCli
{
    public const int Success = ExitCode.Success;
    public const int UsageError = ExitCode.Usage;

    /// <summary>Runs against the real terminal, browser, network and credential store.</summary>
    public static Task<int> RunAsync(string[] args, CancellationToken cancellationToken) => RunAsync(args, OpsEnvironment.ForProcess(), cancellationToken);

    public static async Task<int> RunAsync(string[] args, OpsEnvironment environment, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(args);
        ArgumentNullException.ThrowIfNull(environment);

        var printer = new Printer(environment.Output, environment.Error);
        if (args.Length == 1 && args[0] is "-v" or "--version" or "version")
        {
            printer.Out(typeof(OpsCli).Assembly.GetName().Version?.ToString() ?? "0.0.0");
            return Success;
        }

        var outcome = CommandLine.Parse(args, Registry.All);
        if (outcome.Help)
        {
            Help(printer, outcome.Spec);
            return Success;
        }

        if (outcome.Spec is null || outcome.Args is null)
        {
            printer.Err("error: " + outcome.Error);
            return UsageError;
        }

        var context = new CommandContext(environment, outcome.Args, printer, cancellationToken);
        try
        {
            return await outcome.Spec.Run(context).ConfigureAwait(false);
        }
        catch (OpsConfigException e)
        {
            printer.Err("error: " + e.Message);
            return UsageError;
        }
        catch (LoginException e)
        {
            printer.Err("error: sign-in failed: " + e.Message);
            return ExitCode.Auth;
        }
        catch (OperationCanceledException)
        {
            printer.Err("Cancelled.");
            return ExitCode.Unreachable;
        }
    }

    private static void Help(Printer printer, CommandSpec? spec)
    {
        if (spec is not null)
        {
            printer.Out("Usage: zaghlol-ops " + spec.Usage);
            printer.Out(spec.Summary);
            printer.Out("Global options: --config FILE, --no-browser, --help");
            return;
        }

        printer.Out("zaghlol-ops - Zaghlol operator CLI. Usage: zaghlol-ops <command> [options]   (zaghlol-ops <command> --help)");
        printer.Out(string.Empty);
        foreach (var command in Registry.All)
        {
            printer.Out("  " + command.Usage);
        }

        printer.Out(string.Empty);
        printer.Out("Settings: ZAGHLOL_OPS_API_URL, ZAGHLOL_OPS_ISSUER, ZAGHLOL_OPS_CLIENT_ID (or a JSON file, --config / ZAGHLOL_OPS_CONFIG).");
        printer.Out("Exit codes: 0 ok, 1 refused by the API, 2 usage, 3 sign-in or role, 4 network.");
    }
}
