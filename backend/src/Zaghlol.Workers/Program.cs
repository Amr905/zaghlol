using Serilog;
using Zaghlol.Infrastructure;
using Zaghlol.Infrastructure.Contributions;
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

Log.Logger = new LoggerConfiguration().ConfigureZaghlol("worker").CreateLogger();

var builder = Host.CreateApplicationBuilder(args);

builder.Logging.ClearProviders();
builder.Logging.AddSerilog(Log.Logger, dispose: true);

builder.Services.AddInfrastructure();
builder.Services.AddZaghlolTelemetry(builder.Configuration, builder.Environment, "zaghlol-worker");
builder.Services.AddZaghlolDatabase(DatabaseRole.Worker);
builder.Services.AddHostedService<WorkerHeartbeatService>();

// Price fetcher (T-127): providers from Prices:Providers, hourly.
builder.Services.AddZaghlolPriceWorker();
builder.Services.AddHostedService<PriceFetcherService>();

// Contribution aggregator (T-129): roll raw rows into aggregates, A-48 threshold, retention purge.
builder.Services.AddZaghlolContributionWorker();
builder.Services.AddHostedService<ContributionAggregatorService>();
// RetentionPurger (T-139): daily, Retention:IntervalHours / Retention:BatchSize.
builder.Services.AddZaghlolRetention();
builder.Services.AddHostedService<RetentionPurgerService>();
// Google acknowledge sweeper (T-130): every 15 min, one instance across replicas (advisory lock), Purchases:Google:* config.
builder.Services.AddZaghlolPlayAckSweeper();
builder.Services.AddHostedService<PlayAckSweeperService>();
// App Store Server Notifications V2 (T-134): processor (5 s idle poll), daily history reconciliation, hourly expiry sweep; one
// instance of each across replicas (advisory locks), Purchases:Apple:* config, the worker's share of the Apple budget.
builder.Services.AddZaghlolAppleNotificationWorker();
builder.Services.AddHostedService<AppleNotificationProcessorService>();
builder.Services.AddHostedService<AppleNotificationHistoryService>();
builder.Services.AddHostedService<AppleExpirySweepService>();

using var host = builder.Build();
await host.RunAsync();

// Non-zero when a guard stopped the host (FU-023), e.g. a rejected database login.
return host.Services.GetRequiredService<HostExitCode>().Value;
