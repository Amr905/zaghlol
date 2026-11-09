using Serilog;
using Serilog.Events;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.Logging;

public static class LoggingConfigurationExtensions
{
    /// <summary>
    /// Framework categories that log URLs, paths and headers at <c>Information</c> or below. They stay at <c>Warning</c> in
    /// every environment (error-handling-and-observability.md section 3.2).
    /// </summary>
    public static IReadOnlyList<string> QuietCategories { get; } =
    [
        "Microsoft.AspNetCore", "Microsoft.EntityFrameworkCore", "System.Net.Http", "Polly", "Microsoft.Extensions.Http.Resilience",
    ];

    /// <summary>
    /// Structured JSON logs on stdout through <see cref="ZaghlolJsonFormatter"/>, an allow-list formatter: only the fields of
    /// <see cref="LogFieldPolicy"/> are written, <c>msg</c> is the message template, and exception text is written only for
    /// <c>SafeException</c> types. Request/response bodies, tokens and other sensitive values must still never be passed to the
    /// logger (error-handling-and-observability.md section 3.2).
    /// </summary>
    /// <param name="output">Writes here instead of stdout (tests capture the final bytes).</param>
    public static LoggerConfiguration ConfigureZaghlol(this LoggerConfiguration configuration, string service, TextWriter? output = null)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentException.ThrowIfNullOrWhiteSpace(service);

        configuration
            .MinimumLevel.Information()
            .MinimumLevel.Override("Microsoft", LogEventLevel.Warning)
            .MinimumLevel.Override("Microsoft.Hosting.Lifetime", LogEventLevel.Information)
            .MinimumLevel.Override("System", LogEventLevel.Warning);
        foreach (var category in QuietCategories)
        {
            configuration.MinimumLevel.Override(category, LogEventLevel.Warning);
        }

        configuration
            .Enrich.FromLogContext()
            .Enrich.WithProperty("service", service);

        var formatter = new ZaghlolJsonFormatter();
        return output is null
            ? configuration.WriteTo.Console(formatter)
            : configuration.WriteTo.Sink(new TextWriterLogSink(formatter, output));
    }
}
