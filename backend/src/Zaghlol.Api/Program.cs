using Serilog;
using Serilog.Core;
using Zaghlol.Api;
using Zaghlol.Api.Endpoints;
using Zaghlol.Application;
using Zaghlol.Infrastructure;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Logging;
using Zaghlol.Infrastructure.Persistence;

// `dotnet Zaghlol.Api.dll --healthcheck` is used by container health checks (the runtime image has no shell or curl).
if (args.Contains("--healthcheck", StringComparer.Ordinal))
{
    return await HealthProbe.RunAsync();
}

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel(options => options.AddServerHeader = false);

builder.Host.UseSerilog((_, services, logger) =>
{
    logger.ConfigureZaghlol("api");
    foreach (var sink in services.GetServices<ILogEventSink>())
    {
        logger.WriteTo.Sink(sink);
    }
});

builder.Services.AddApplication();
builder.Services.AddInfrastructure();

// Signing, keyed hashes and envelopes through the KMS (T-123); refuses to start on a misconfigured key ring.
builder.Services.AddZaghlolKms();

// Two logins: app_rw for /v1/*, ops_rw for /admin/v1/* (T-122), so an injection in /v1 can't write catalog or audit rows.
builder.Services.AddZaghlolDatabase(DatabaseRole.App, DatabaseRole.Admin);
builder.Services.AddDatabaseReadiness();
builder.Services.AddZaghlolHttp();

var app = builder.Build();

app.UseZaghlolPipeline();
app.MapHealth();

await app.RunAsync();

// Non-zero when a guard stopped the host (FU-023), e.g. a rejected database login.
return app.Services.GetRequiredService<HostExitCode>().Value;

public partial class Program;
