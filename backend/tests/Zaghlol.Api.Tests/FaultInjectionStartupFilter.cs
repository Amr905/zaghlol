using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;

namespace Zaghlol.Api.Tests;

/// <summary>
/// Appends test-only endpoints after the application pipeline so that their exceptions flow back
/// through the real exception handler.
/// </summary>
public sealed class FaultInjectionStartupFilter : IStartupFilter
{
    public const string Secret = "sensitive-detail-9f3a";

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
