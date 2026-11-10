using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Prices;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Prices;

public static class PricesServiceCollectionExtensions
{
    /// <summary>
    /// The API side: the override store on the Admin login and the read-only reader on the App login. Call after
    /// <c>AddZaghlolDatabase</c> with <c>DatabaseRole.App</c> and <c>DatabaseRole.Admin</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolPrices(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<IPriceAdminStore, PriceAdminStore>();
        services.TryAddSingleton<IPriceReader, PriceReader>();
        services.TryAddSingleton<PriceOverrideService>();
        services.TryAddSingleton<PriceReadService>();
        return services;
    }

    /// <summary>
    /// The worker side: the feed store on the Worker login, the providers named by <c>Prices:Providers</c> and the job. Call after
    /// <c>AddZaghlolDatabase</c> with <c>DatabaseRole.Worker</c> and <c>AddZaghlolTelemetry</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolPriceWorker(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<IPriceFeedStore, PriceFeedStore>();
        services.TryAddSingleton<IPriceMetrics, ZaghlolPriceMetrics>();
        services.TryAddSingleton(provider => new PriceFetchJob(
            PriceProviderFactory.Create(
                provider.GetRequiredService<IConfiguration>(),
                provider.GetRequiredService<IHostEnvironment>(),
                provider.GetRequiredService<TimeProvider>()),
            provider.GetRequiredService<IPriceFeedStore>(),
            provider.GetRequiredService<IPriceMetrics>(),
            provider.GetRequiredService<TimeProvider>()));
        return services;
    }
}

internal sealed class ZaghlolPriceMetrics(ZaghlolMetrics metrics) : IPriceMetrics
{
    public void Fetched(string provider, string outcome) => metrics.PriceFetched(provider, outcome);

    public void SetAge(string symbol, TimeSpan age) => metrics.SetPriceAge(symbol, age);
}
