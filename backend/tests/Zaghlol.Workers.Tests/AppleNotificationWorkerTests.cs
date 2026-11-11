using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Purchases;
using Zaghlol.Infrastructure;
using Zaghlol.Infrastructure.AppStore;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Purchases;

namespace Zaghlol.Workers.Tests;

/// <summary>T-134: the worker's ASSN registrations resolve, on the worker budget partition, and refuse the API partition.</summary>
public sealed class AppleNotificationWorkerTests
{
    [Fact]
    public async Task TheWorkerResolvesTheProcessorHistoryAndSweepOnTheWorkerPartition()
    {
        await using var services = Build().BuildServiceProvider();

        Assert.NotNull(services.GetRequiredService<AppleNotificationProcessor>());
        Assert.NotNull(services.GetRequiredService<AppleNotificationHistoryJob>());
        Assert.NotNull(services.GetRequiredService<AppleExpirySweepJob>());
        var budget = services.GetRequiredService<AppleCallBudget>();
        Assert.Equal(AppleBudgetPartition.Worker, budget.Partition);
        Assert.False(budget.TryAcquire(StoreLane.Verify));
        Assert.True(budget.TryAcquire(StoreLane.Notification));
    }

    [Fact]
    public void TheApiAndWorkerPartitionsCannotBeMixedInOneProcess()
    {
        var services = Build();

        Assert.Throws<InvalidOperationException>(() => services.AddZaghlolAppStore(AppleBudgetPartition.Api));
        services.AddZaghlolAppleNotificationWorker();
    }

    [Fact]
    public void TheServiceIntervalsAreTheDesignedOnes()
    {
        Assert.Equal(TimeSpan.FromSeconds(5), AppleNotificationProcessorService.IdleDelay);
        Assert.Equal(TimeSpan.FromHours(24), AppleNotificationHistoryService.Interval);
        Assert.Equal(TimeSpan.FromHours(1), AppleExpirySweepService.Interval);
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
        services.AddZaghlolAppleNotificationWorker();
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
