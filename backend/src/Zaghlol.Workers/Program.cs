using Serilog;
using Zaghlol.Infrastructure;
using Zaghlol.Infrastructure.Logging;
using Zaghlol.Workers;

// `dotnet Zaghlol.Workers.dll --healthcheck` is used by container health checks (no shell in the runtime image).
if (args.Contains("--healthcheck", StringComparer.Ordinal))
{
    return WorkerHealthProbe.Run();
}

Log.Logger = new LoggerConfiguration().ConfigureZaghlol("worker").CreateLogger();

var builder = Host.CreateApplicationBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddSerilog(Log.Logger, dispose: true);

builder.Services.AddInfrastructure();
builder.Services.AddHostedService<WorkerHeartbeatService>();

using var host = builder.Build();
await host.RunAsync();
return 0;
