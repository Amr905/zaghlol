namespace Zaghlol.Ops;

/// <summary>The process entry point. It is an explicit class (not top-level statements) so that no type called <c>Program</c> clashes with the API's.</summary>
internal static class OpsProgram
{
    private static async Task<int> Main(string[] args)
    {
        using var cancellation = new CancellationTokenSource();
        Console.CancelKeyPress += (_, e) =>
        {
            e.Cancel = true;
            cancellation.Cancel();
        };

        return await OpsCli.RunAsync(args, cancellation.Token).ConfigureAwait(false);
    }
}
