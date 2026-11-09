using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Application.Flags;
using Zaghlol.Application.Health;

namespace Zaghlol.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.AddSingleton<GetHealthHandler>();
        services.AddSingleton<FlagAdminService>();
        return services;
    }
}
