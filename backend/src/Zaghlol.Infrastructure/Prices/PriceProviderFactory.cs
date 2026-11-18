using System.Globalization;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Prices;

namespace Zaghlol.Infrastructure.Prices;

/// <summary>
/// Builds the provider list from <c>Prices:Providers</c> (comma-separated names, highest priority first). Adapters: <c>fake</c>
/// (refused in Production), <c>goldapi</c> and <c>metalpriceapi</c> (API key from <c>Prices:&lt;Name&gt;:ApiKey</c>, a secret, wrapped in a
/// cache with a TTL of <c>Prices:IntervalMinutes</c>). Startup fails on a name with no adapter yet (<c>local_gold</c>, <c>fx</c>,
/// <c>spot_gold</c>: BLK-03 / D-41 is the PO's provider choice) and on an unknown name.
/// </summary>
public static class PriceProviderFactory
{
    public static IReadOnlyList<IPriceProvider> Create(IConfiguration configuration, IHostEnvironment environment, TimeProvider clock, IHttpClientFactory? clients = null)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(environment);
        ArgumentNullException.ThrowIfNull(clock);

        var names = (configuration["Prices:Providers"] ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Distinct(StringComparer.Ordinal)
            .ToList();
        var providers = new List<IPriceProvider>();
        foreach (var name in names)
        {
            if (name == PriceProviderNames.Fake)
            {
                if (environment.IsProduction())
                {
                    throw new InvalidOperationException("Prices:Providers must not include 'fake' in Production.");
                }

                providers.Add(new FakePriceProvider(configuration, clock));
            }
            else if (name == PriceProviderNames.GoldApi)
            {
                var http = Http(clients, GoldApiProvider.HttpClientName);
                providers.Add(Cached(
                    new GoldApiProvider(http, PriceHttp.ApiKey(configuration, "Prices:GoldApi:ApiKey"), PriceHttp.Bounds(configuration), clock),
                    configuration,
                    clock));
            }
            else if (name == PriceProviderNames.MetalpriceApi)
            {
                var http = Http(clients, MetalpriceApiProvider.HttpClientName);
                var fx = (configuration["Prices:MetalpriceApi:FxCurrencies"] ?? "SAR,EUR,GBP,KWD")
                    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                    .Where(PriceSymbols.IsCurrencyShape)
                    .ToList();
                providers.Add(Cached(
                    new MetalpriceApiProvider(http, PriceHttp.ApiKey(configuration, "Prices:MetalpriceApi:ApiKey"), PriceHttp.Bounds(configuration), fx, clock),
                    configuration,
                    clock));
            }
            else if (PriceProviderNames.Known.Contains(name, StringComparer.Ordinal))
            {
                throw new InvalidOperationException(
                    $"Prices:Providers names '{name}', which has no adapter yet (the provider contract, BLK-03, is pending).");
            }
            else
            {
                throw new InvalidOperationException("Prices:Providers names an unknown provider.");
            }
        }

        return providers;
    }

    private static HttpClient Http(IHttpClientFactory? clients, string name) =>
        (clients ?? throw new InvalidOperationException("An HTTP price provider needs the HTTP client factory.")).CreateClient(name);

    private static CachingPriceProvider Cached(IPriceProvider inner, IConfiguration configuration, TimeProvider clock)
    {
        // The TTL is the fetch interval less a minute of slack, so a scheduled run is never answered from a cache that is a hair too young.
        var minutes = int.TryParse(configuration["Prices:IntervalMinutes"], NumberStyles.None, CultureInfo.InvariantCulture, out var parsed) && parsed > 0 ? parsed : 60;
        return new CachingPriceProvider(inner, TimeSpan.FromMinutes(Math.Max(1, minutes - 1)), clock);
    }
}
