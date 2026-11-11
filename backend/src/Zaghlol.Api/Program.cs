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
using Zaghlol.Infrastructure.Contributions;
using Zaghlol.Infrastructure.Flags;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Logging;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Prices;
using Zaghlol.Infrastructure.Purchases;
using Zaghlol.Infrastructure.Seats;
using Zaghlol.Infrastructure.Support;

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
// Seat-key proofs and K_seat keyed hashes (T-182); the K_seat startup check refuses a wrong or rotated key outside Development/Testing.
builder.Services.AddZaghlolSeatKeys();
// The seat service (T-184): every channel's seat decision runs through it, in the caller's transaction.
builder.Services.AddZaghlolSeats();

// Two logins: app_rw for /v1/*, ops_rw for /admin/v1/* (T-122), so an injection in /v1 can't write catalog or audit rows.
builder.Services.AddZaghlolDatabase(DatabaseRole.App, DatabaseRole.Admin);
builder.Services.AddDatabaseReadiness();
builder.Services.AddZaghlolHttp();

// OpenTelemetry (redacted spans, the Zaghlol meter) and the monthly log key for installHash (T-138).
builder.Services.AddZaghlolApiTelemetry(builder.Configuration, builder.Environment);
builder.Services.AddZaghlolLogPseudonymizer();

// Install registration, install-token auth and the idempotency store (T-124); after the pseudonymizer for its startup check.
builder.Services.AddZaghlolInstalls();

// Catalog versions, deltas, signed snapshots and the operator draft/publish API (T-125); operator auth comes from AddOperatorAuthentication and AddZaghlolOperatorAuth (T-136).
builder.Services.AddZaghlolCatalog();
// Contribution review queue (T-129): promote edits the draft under the catalog lock, so it follows the catalog registration.
builder.Services.AddZaghlolContributionAdmin();
// Feature flags (T-126): the admin store on the Admin login, the reader on the App login, the ops-channel notifier.
builder.Services.AddZaghlolFlagAdmin();
builder.Services.AddZaghlolFlagReader();
// Price cache reader (App login) and operator override (Admin login) (T-127).
builder.Services.AddZaghlolPrices();
// Daily sync (T-128): throttle, composition, intake; after the catalog, flag and price readers it composes from.
builder.Services.AddZaghlolSync();
// Purchase verify (T-130, T-131): the Google Play and App Store clients, verifiers and support order lookups on the App login
// (AddZaghlolPurchaseVerification adds the App Store services). Production refuses to start while the NullVerifyGrant
// placeholder (T-132) is registered.
builder.Services.AddZaghlolGooglePlay();
builder.Services.AddZaghlolPurchaseVerification();
// App Store Server Notifications V2 ingest (T-134): verify and store only, on the App login; the worker processes.
builder.Services.AddZaghlolAppleNotificationIngest();
// Google RTDN push (T-133): Pub/Sub OIDC before the body, store only, on the App login; the worker processes. Production refuses to
// start without Purchases:Google:Rtdn:Audience and PushServiceAccount.
builder.Services.AddZaghlolGoogleNotifications();

// Operator OIDC + MFA, the operator directory and the startup check (T-136); the audited support lookup on the Admin login.
builder.Services.AddZaghlolOperatorAuth();
builder.Services.AddZaghlolSupport();

var app = builder.Build();

app.UseZaghlolPipeline();
app.MapHealth();
app.MapInstalls();
app.MapSync();
app.MapPurchases();
app.MapAppleNotifications();
app.MapGoogleNotifications();
app.MapCatalog();
app.MapCatalogAdmin();
app.MapContributionAdmin();
app.MapFlagAdmin();
app.MapSupportAdmin();
app.MapPriceAdmin();

await app.RunAsync();

// Non-zero when a guard stopped the host (FU-023), e.g. a rejected database login.
return app.Services.GetRequiredService<HostExitCode>().Value;

public partial class Program;
