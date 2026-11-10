using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Application.Health;
using Zaghlol.Testing;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// Boots the real API in-process so responses can be checked against the OpenAPI document. There is no database:
/// readiness is a switchable fake, and the connection strings point nowhere (they are only checked for presence).
/// </summary>
public sealed class ContractApiFixture : IDisposable
{
    private const string Unreachable = "Host=127.0.0.1;Port=1;Database=none;Username=none";

    private readonly WebApplicationFactory<Program> factory;
    private readonly FakeKms kms = FakeKms.CreateDefault();

    public ContractApiFixture()
    {
        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseSetting("ConnectionStrings:App", Unreachable);
            builder.UseSetting("ConnectionStrings:Admin", Unreachable);
            foreach (var (key, value) in kms.Settings())
            {
                builder.UseSetting(key, value);
            }

            builder.ConfigureServices(services =>
            {
                kms.Use(services);
                services.AddSingleton<IStartupFilter, FaultEndpointsStartupFilter>();
                services.RemoveAll<IDatabaseReadiness>();
                services.AddSingleton<IDatabaseReadiness>(Readiness);
            });
        });
        Client = factory.CreateClient();
    }

    public HttpClient Client { get; }

    public IServiceProvider Services => factory.Services;

    public SwitchableReadiness Readiness { get; } = new();

    public void Dispose()
    {
        Client.Dispose();
        factory.Dispose();
        kms.Dispose();
    }
}

/// <summary>
/// Appends test-only endpoints after the application pipeline so that their failures flow through the real
/// exception handler and status-code pages, producing the same problem+json bodies as production.
/// </summary>
internal sealed class FaultEndpointsStartupFilter : IStartupFilter
{
    public const string Secret = "contract-secret-4d2b";

    public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next)
    {
        ArgumentNullException.ThrowIfNull(next);

        return app =>
        {
            next(app);
            app.Map("/test/boom", branch => branch.Run(_ => throw new InvalidOperationException(Secret)));
            app.Map("/test/bad-request", branch => branch.Run(_ => throw new BadHttpRequestException(Secret, StatusCodes.Status400BadRequest)));
        };
    }
}

/// <summary>Readiness the tests can switch off to exercise the 503 contract.</summary>
public sealed class SwitchableReadiness : IDatabaseReadiness
{
    private volatile bool ready = true;

    public bool Ready
    {
        get => ready;
        set => ready = value;
    }

    public ValueTask<bool> IsReadyAsync(CancellationToken cancellationToken) => ValueTask.FromResult(ready);
}
