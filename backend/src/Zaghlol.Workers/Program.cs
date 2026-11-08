using Serilog;
using Zaghlol.Infrastructure;
using Zaghlol.Infrastructure.Logging;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;
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

Log.Logger = new LoggerConfiguration().ConfigureZaghlol("worker").CreateLogger();

var builder = Host.CreateApplicationBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddSerilog(Log.Logger, dispose: true);

builder.Services.AddInfrastructure();
builder.Services.AddZaghlolTelemetry(builder.Configuration, builder.Environment, "zaghlol-worker");
builder.Services.AddZaghlolDatabase(DatabaseRole.Worker);
builder.Services.AddHostedService<WorkerHeartbeatService>();

using var host = builder.Build();
await host.RunAsync();

// Non-zero when a guard stopped the host (FU-023), e.g. a rejected database login.
return host.Services.GetRequiredService<HostExitCode>().Value;
