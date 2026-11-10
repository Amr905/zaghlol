using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Prices;

namespace Zaghlol.Infrastructure.Prices;

/// <summary>
/// Builds the provider list from <c>Prices:Providers</c> (comma-separated names, highest priority first). Startup fails on a
/// name that has no adapter yet: the real adapters (local gold feed, licensed FX) arrive once BLK-03 / D-41 is settled, and
/// <c>fake</c> is refused in Production so the stub can never serve real users.
/// </summary>
public static class PriceProviderFactory
{
    public static IReadOnlyList<IPriceProvider> Create(IConfiguration configuration, IHostEnvironment environment, TimeProvider clock)
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
}
