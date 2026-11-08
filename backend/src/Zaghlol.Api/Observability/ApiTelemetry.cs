using OpenTelemetry.Metrics;
using OpenTelemetry.Trace;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Api.Observability;

internal static class ApiTelemetry
{
    public const string ServiceName = "zaghlol-api";

    /// <summary>The probe path; its spans are not recorded.</summary>
    public const string HealthPath = "/v1/health";

    /// <summary>
    /// ASP.NET Core spans and metrics over <see cref="TelemetryServiceCollectionExtensions.AddZaghlolTelemetry"/>. The
    /// instrumentation captures no headers and records no exceptions; <see cref="RedactingActivityProcessor"/> removes the
    /// raw path and query from what it does record.
    /// </summary>
    public static IServiceCollection AddZaghlolApiTelemetry(this IServiceCollection services, IConfiguration configuration, IHostEnvironment environment) =>
        services.AddZaghlolTelemetry(
            configuration,
            environment,
            ServiceName,
            tracing => tracing.AddAspNetCoreInstrumentation(options =>
            {
                options.RecordException = false;
                options.Filter = context => !context.Request.Path.Equals(HealthPath, StringComparison.Ordinal);
            }),
            metrics => metrics.AddAspNetCoreInstrumentation());
}
