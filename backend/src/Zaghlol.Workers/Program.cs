using Serilog;
using Zaghlol.Infrastructure;
using Zaghlol.Infrastructure.Accounts;
using Zaghlol.Infrastructure.Contributions;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Logging;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Prices;
using Zaghlol.Infrastructure.Purchases;
using Zaghlol.Infrastructure.Retention;
using Zaghlol.Workers;

// `dotnet Zaghlol.Workers.dll --healthcheck` is used by container health checks (no shell in the runtime image).
if (args.Contains("--healthcheck", StringComparer.Ordinal))
{
    return WorkerHealthProbe.Run();
}

// `dotnet Zaghlol.Workers.dll --migrate` is the migration job (T-122): applies migrations as `migrator`, then exits.
if (args.Contains(MigrateCommand.Flag, StringComparer.Ordinal))
{
    return await MigrateCommand.RunAsync(args);
}

// `dotnet Zaghlol.Workers.dll --generate-keys ...` is the production key tool of the File KMS (T-200): run it once on the server,
// inside this image, with no network. It writes key files and prints public values only. With `--format host-secrets` (T-205) it
// writes nothing and prints the keys once as ZAGHLOL_KEYS__<name> settings for the shared host (ADR-026).
if (args.Contains(FileKeyTool.Flag, StringComparer.Ordinal))
{
    return FileKeyTool.Run(args, Console.Out, Console.Error, Environment.CurrentDirectory);
}

// `dotnet Zaghlol.Workers.dll --openbao-keys ...` is the OpenBao migration tool (T-201): imports the File HMAC and envelope keys
// into Transit (BYOK), verifies them and prints pins and ring entries. Public values only.
if (args.Contains(OpenBaoKeyTool.Flag, StringComparer.Ordinal))
{
    return OpenBaoKeyTool.Run(args, Console.Out, Console.Error);
}

Log.Logger = new LoggerConfiguration().ConfigureZaghlol("worker").CreateLogger();

var builder = Host.CreateApplicationBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddSerilog(Log.Logger, dispose: true);

builder.Services.AddInfrastructure();
builder.Services.AddZaghlolTelemetry(builder.Configuration, builder.Environment, "zaghlol-worker");
builder.Services.AddZaghlolDatabase(DatabaseRole.Worker);
// KMS ring first (the Apple revocation job opens sealed refresh tokens with it). With OpenBao (T-201) the worker runs with
// Kms:Scope=Envelope and an AppRole whose policy allows envelope keys only.
builder.Services.AddZaghlolKms();
// Every job (heartbeat, prices, contributions, retention, Play/Apple notifications and sweepers, revocation retry): shared with the
// API's embedded-workers mode (T-206).
builder.Services.AddZaghlolWorkerJobs();

using var host = builder.Build();

// Resolved before RunAsync, which disposes the host and its service provider (BUG-002).
var exitCode = host.Services.GetRequiredService<HostExitCode>();
await host.RunAsync();

// Non-zero when a guard stopped the host (FU-023), e.g. a rejected database login.
return exitCode.Value;
