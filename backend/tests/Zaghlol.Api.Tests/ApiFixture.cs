using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Serilog.Core;
using Testcontainers.PostgreSql;

namespace Zaghlol.Api.Tests;

/// <summary>
/// Starts a real PostgreSQL 17 container and boots the API in-process against it.
/// </summary>
public sealed class ApiFixture : IAsyncLifetime
{
    private PostgreSqlContainer? postgres;
    private WebApplicationFactory<Program>? factory;

    public CapturingSink LogSink { get; } = new();

    public string PostgresConnectionString { get; private set; } = string.Empty;

    public HttpClient Client { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        postgres = new PostgreSqlBuilder().WithImage("postgres:17").Build();
        await postgres.StartAsync();
        PostgresConnectionString = postgres.GetConnectionString();

        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseSetting("ConnectionStrings:Postgres", PostgresConnectionString);
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

        if (postgres is not null)
        {
            await postgres.DisposeAsync();
        }
    }
}
