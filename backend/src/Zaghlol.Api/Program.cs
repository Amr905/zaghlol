using Serilog;
using Serilog.Core;
using Zaghlol.Api;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Endpoints;
using Zaghlol.Api.Endpoints.Admin;
using Zaghlol.Api.Endpoints.V1;
using Zaghlol.Api.Observability;
using Zaghlol.Application;
using Zaghlol.Infrastructure;
using Zaghlol.Infrastructure.Catalog;
using Zaghlol.Infrastructure.Flags;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Logging;
using Zaghlol.Infrastructure.Observability;
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

// OpenTelemetry (redacted spans, the Zaghlol meter) and the monthly log key for installHash (T-138).
builder.Services.AddZaghlolApiTelemetry(builder.Configuration, builder.Environment);
builder.Services.AddZaghlolLogPseudonymizer();

// Install registration, install-token auth and the idempotency store (T-124); after the pseudonymizer for its startup check.
builder.Services.AddZaghlolInstalls();

// Catalog versions, deltas, signed snapshots and the operator draft/publish API (T-125); operator auth comes from AddOperatorAuthentication (T-126, real validator T-136).
builder.Services.AddZaghlolCatalog();
// Feature flags (T-126): the admin store on the Admin login, the reader on the App login, the ops-channel notifier.
builder.Services.AddZaghlolFlagAdmin();
builder.Services.AddZaghlolFlagReader();

var app = builder.Build();

app.UseZaghlolPipeline();
app.MapHealth();
app.MapInstalls();
app.MapCatalog();
app.MapCatalogAdmin();
app.MapFlagAdmin();

await app.RunAsync();

// Non-zero when a guard stopped the host (FU-023), e.g. a rejected database login.
return app.Services.GetRequiredService<HostExitCode>().Value;

public partial class Program;
