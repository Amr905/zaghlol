using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Serilog.Core;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests;

/// <summary>
/// Starts a real, migrated PostgreSQL 17 (roles bootstrapped like production) and boots the API in-process against it
/// with its two least-privilege logins.
/// </summary>
public sealed class ApiFixture : IAsyncLifetime
{
    private ZaghlolTestDatabase? database;
    private WebApplicationFactory<Program>? factory;

    public CapturingSink LogSink { get; } = new();

    public string PostgresConnectionString { get; private set; } = string.Empty;

    public HttpClient Client { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        database = await ZaghlolTestDatabase.StartAsync();
        PostgresConnectionString = database.Superuser;

        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseSetting("ConnectionStrings:App", database.Api);
            builder.UseSetting("ConnectionStrings:Admin", database.Admin);
            builder.ConfigureServices(services =>
            {
                services.AddSingleton<ILogEventSink>(LogSink);
                services.AddSingleton<IStartupFilter, FaultInjectionStartupFilter>();
            });
        });
        Client = factory.CreateClient();
    }

    public async Task DisposeAsync()
    {
        Client?.Dispose();
        if (factory is not null)
        {
            await factory.DisposeAsync();
        }

        if (database is not null)
        {
            await database.DisposeAsync();
        }
    }
}
