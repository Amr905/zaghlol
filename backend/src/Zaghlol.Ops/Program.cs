using Zaghlol.Ops;

using var cancellation = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    cancellation.Cancel();
};

return await OpsCli.RunAsync(args, cancellation.Token).ConfigureAwait(false);
