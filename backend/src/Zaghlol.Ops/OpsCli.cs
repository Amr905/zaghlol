namespace Zaghlol.Ops;

/// <summary>
/// Stub for the operator CLI (`zaghlol-ops`). Commands (catalog, flags, support lookup) and OIDC device-flow
/// sign-in are added in later tasks.
/// </summary>
internal static class OpsCli
{
    public const int Success = 0;
    public const int UsageError = 2;

    public static int Run(string[] args, TextWriter output, TextWriter error)
    {
        ArgumentNullException.ThrowIfNull(args);
        ArgumentNullException.ThrowIfNull(output);
        ArgumentNullException.ThrowIfNull(error);

        if (args.Length == 0 || args[0] is "-h" or "--help" or "help")
        {
            output.WriteLine("zaghlol-ops - Zaghlol operator CLI (stub). Usage: zaghlol-ops [--help | --version]");
            return Success;
        }

        if (args[0] is "-v" or "--version" or "version")
        {
            output.WriteLine(typeof(OpsCli).Assembly.GetName().Version?.ToString() ?? "0.0.0");
            return Success;
        }

        error.WriteLine("Unknown command. Run 'zaghlol-ops --help'.");
        return UsageError;
    }
}
