using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Purchases;
using Zaghlol.Infrastructure;
using Zaghlol.Infrastructure.GooglePlay;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Purchases;

namespace Zaghlol.Workers.Tests;

/// <summary>T-133: the worker's RTDN registrations resolve on the Play worker partition (with the ack sweeper's) and refuse the API one.</summary>
public sealed class PlayNotificationWorkerTests
{
    [Fact]
    public async Task TheWorkerResolvesTheProcessorJobsAndSweeperOnTheWorkerPartition()
    {
        await using var services = Build().BuildServiceProvider();

        Assert.NotNull(services.GetRequiredService<PlayNotificationProcessor>());
        Assert.NotNull(services.GetRequiredService<PlayVoidedReconcileJob>());
        Assert.NotNull(services.GetRequiredService<PlayExpirySweepJob>());
        Assert.NotNull(services.GetRequiredService<PlayAckSweepJob>());
        var budget = services.GetRequiredService<PlayCallBudget>();
        Assert.Equal(PlayBudgetPartition.Worker, budget.Partition);
        Assert.Same(budget, services.GetRequiredService<IStoreCallBudget>());
        Assert.False(budget.TryAcquire(StoreLane.Verify));
        Assert.True(budget.TryAcquire(StoreLane.Notification));
        Assert.True(budget.TryAcquire(StoreLane.Ack));
    }

    [Fact]
    public void TheApiAndWorkerPlayPartitionsCannotBeMixedInOneProcess()
    {
        var services = Build();

        Assert.Throws<InvalidOperationException>(() => services.AddZaghlolGooglePlay(PlayBudgetPartition.Api));
        services.AddZaghlolPlayNotificationWorker();
        services.AddZaghlolPlayAckSweeper();
    }

    [Fact]
    public void TheServiceIntervalsAreTheDesignedOnes()
    {
        Assert.Equal(TimeSpan.FromSeconds(5), PlayNotificationProcessorService.IdleDelay);
        Assert.Equal(TimeSpan.FromHours(24), PlayVoidedReconcileService.Interval);
        Assert.Equal(TimeSpan.FromHours(1), PlayExpirySweepService.Interval);
        Assert.Equal(50, PlayNotificationProcessor.BatchSize);
        Assert.Equal(200, PlayExpirySweepJob.BatchSize);
        Assert.Equal(10, PlayVoidedReconcileJob.MaxPages);
    }

    private static ServiceCollection Build()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["ConnectionStrings:Worker"] = "Host=127.0.0.1;Port=1;Database=none;Username=none" })
            .Build();
        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(configuration);
        services.AddSingleton<IHostEnvironment>(new TestEnvironment());
        services.AddLogging();
        services.AddInfrastructure();
        services.AddZaghlolTelemetry(configuration, new TestEnvironment(), "zaghlol-worker-test");
        services.AddZaghlolDatabase(DatabaseRole.Worker);
        services.AddZaghlolPlayAckSweeper();
        services.AddZaghlolPlayNotificationWorker();
        return services;
    }

    private sealed class TestEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = "Testing";

        public string ApplicationName { get; set; } = "t";

        public string ContentRootPath { get; set; } = "/";

        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = null!;
    }
}
