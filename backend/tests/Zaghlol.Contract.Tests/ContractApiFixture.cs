using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;

namespace Zaghlol.Contract.Tests;

/// <summary>Boots the real API in-process so responses can be checked against the OpenAPI document.</summary>
public sealed class ContractApiFixture : IDisposable
{
    private readonly WebApplicationFactory<Program> factory;

    public ContractApiFixture()
    {
        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.ConfigureServices(services => services.AddSingleton<IStartupFilter, FaultEndpointsStartupFilter>()));
        Client = factory.CreateClient();
    }

    public HttpClient Client { get; }

    public void Dispose()
    {
        Client.Dispose();
        factory.Dispose();
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
