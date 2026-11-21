using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Workers;

namespace Zaghlol.Api.Tests;

/// <summary>T-206: the embedded-workers hosting profile for one IIS site.</summary>
[Collection(ApiHostGroup.Name)]
public class EmbeddedWorkersTests
{
    private static IConfiguration Config(params (string Key, string? Value)[] values) =>
        new ConfigurationBuilder().AddInMemoryCollection(values.Select(v => KeyValuePair.Create(v.Key, v.Value))).Build();

    private static Type[] HostedTypes(IServiceCollection services) =>
        [.. services
            .Where(d => d.ServiceType == typeof(IHostedService))
            .Select(d => d.ImplementationType)
            .OfType<Type>()];

    [Fact]
    public void OffByDefaultRegistersNoWorkerJobsAndNoWorkerLogin()
    {
        var configuration = Config();
        var services = new ServiceCollection();

        services.AddEmbeddedWorkersIfEnabled(configuration);

        Assert.Empty(HostedTypes(services));
        Assert.Equal([DatabaseRole.App, DatabaseRole.Admin], EmbeddedWorkers.DatabaseRoles(configuration));
    }

    [Fact]
    public void EnabledRegistersEveryWorkerJobAndOpensTheWorkerLogin()
    {
        var configuration = Config((EmbeddedWorkers.EnabledKey, "true"));
        var services = new ServiceCollection();

        services.AddEmbeddedWorkersIfEnabled(configuration);

        var registered = HostedTypes(services);
        foreach (var job in WorkerJobRegistration.JobTypes)
        {
            Assert.Contains(job, registered);
        }

        Assert.Contains(DatabaseRole.Worker, EmbeddedWorkers.DatabaseRoles(configuration));
        Assert.Equal(WorkerJobRegistration.JobTypes.Count, registered.Distinct().Count(WorkerJobRegistration.JobTypes.Contains));
    }

    [Fact]
    public void EmbeddedJobsAndADeclaredSeparateWorkerRefuseToStart()
    {
        var configuration = Config((EmbeddedWorkers.EnabledKey, "true"), (EmbeddedWorkers.SeparateWorkerKey, "true"));

        Assert.Throws<EmbeddedWorkersConfigurationException>(() => new ServiceCollection().AddEmbeddedWorkersIfEnabled(configuration));
    }

    [Fact]
    public void SeparateWorkerAloneIsFineWhileEmbeddingIsOff()
    {
        var services = new ServiceCollection().AddEmbeddedWorkersIfEnabled(Config((EmbeddedWorkers.SeparateWorkerKey, "true")));

        Assert.Empty(HostedTypes(services));
    }

    [Fact]
    public void SnapshotDirectoryDefaultsToAppDataOnlyWhenEmbeddedAndUnset()
    {
        var root = Path.Combine(Path.GetTempPath(), "site");
        var embedded = new ConfigurationManager();
        embedded[EmbeddedWorkers.EnabledKey] = "true";
        EmbeddedWorkers.ApplyDefaults(embedded, root);
        Assert.Equal(Path.Combine(root, "App_Data", "catalog-snapshots"), embedded["Catalog:Snapshots:Directory"]);

        var explicitDirectory = new ConfigurationManager();
        explicitDirectory[EmbeddedWorkers.EnabledKey] = "true";
        explicitDirectory["Catalog:Snapshots:Directory"] = "/data/snap";
        EmbeddedWorkers.ApplyDefaults(explicitDirectory, root);
        Assert.Equal("/data/snap", explicitDirectory["Catalog:Snapshots:Directory"]);

        var off = new ConfigurationManager();
        EmbeddedWorkers.ApplyDefaults(off, root);
        Assert.Null(off["Catalog:Snapshots:Directory"]);
    }
}
