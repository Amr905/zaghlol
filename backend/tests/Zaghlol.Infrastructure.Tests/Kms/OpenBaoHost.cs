using System.Runtime.Versioning;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Seats;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>T-201: the KMS services of a host (AddZaghlolKms, plus AddZaghlolSeatKeys for the API scope).</summary>
[SupportedOSPlatform("linux")]
internal static class OpenBaoHost
{
    public static ServiceProvider Services(string environment, Dictionary<string, string?> settings, FileKmsHost.CapturingLogs? logs = null, KmsCallPolicy? policy = null)
    {
        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(new ConfigurationBuilder().AddInMemoryCollection(settings).Build());
        services.AddSingleton<IHostEnvironment>(new FileKmsHost.TestEnvironment(environment, AppContext.BaseDirectory));
        services.AddLogging(l => l.ClearProviders().AddProvider(logs ?? new FileKmsHost.CapturingLogs()).SetMinimumLevel(LogLevel.Trace));
        if (policy is not null)
        {
            services.AddSingleton(policy);
        }

        services.AddZaghlolKms();
        if (settings.GetValueOrDefault("Kms:Scope") != "Envelope")
        {
            services.AddZaghlolSeatKeys();
        }

        return services.BuildServiceProvider();
    }
}
