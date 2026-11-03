using Serilog;
using Serilog.Events;
using Serilog.Formatting.Compact;

namespace Zaghlol.Infrastructure.Logging;

public static class LoggingConfigurationExtensions
{
    /// <summary>
    /// Structured JSON logs on stdout. Request/response bodies, tokens and other sensitive values
    /// must never be passed to the logger (error-handling-and-observability.md section 3.2).
    /// </summary>
    public static LoggerConfiguration ConfigureZaghlol(this LoggerConfiguration configuration, string service)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentException.ThrowIfNullOrWhiteSpace(service);

        return configuration
            .MinimumLevel.Information()
            .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
            .MinimumLevel.Override("Microsoft.Hosting.Lifetime", LogEventLevel.Information)
            .MinimumLevel.Override("System", LogEventLevel.Warning)
            .Enrich.FromLogContext()
            .Enrich.WithProperty("service", service)
            .WriteTo.Console(new RenderedCompactJsonFormatter());
    }
}
