using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Endpoints.V1;
using Zaghlol.Api.Json;
using Zaghlol.Api.Observability;
using Zaghlol.Api.Problems;
using Zaghlol.Api.RateLimiting;
using Zaghlol.Api.Signing;
using Zaghlol.Application.Sync;
using Zaghlol.Infrastructure.Installs;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Sync;

namespace Zaghlol.Api;

/// <summary>The HTTP pipeline, shared by <c>Program</c> and the test hosts so all run the same order.</summary>
internal static class ApiPipeline
{
    /// <summary>
    /// RFC 9457 problem details, the global exception handler, the install-token scheme, the rate limiters, the
    /// forwarded-headers rule and the global UTC-<c>Z</c> timestamp converter.
    /// </summary>
    public static IServiceCollection AddZaghlolHttp(this IServiceCollection services)
    {
        services.AddProblemDetails(options => options.CustomizeProblemDetails = ProblemDetailsCustomizer.Customize);
        services.AddExceptionHandler<GlobalExceptionHandler>();
        services.AddInstallTokenAuthentication();
        services.AddOperatorAuthentication();
        services.AddZaghlolRateLimits();
        services.ConfigureHttpJsonOptions(options => options.SerializerOptions.Converters.Add(new UtcZDateTimeOffsetConverter()));
        return services;
    }

    /// <summary>
    /// The install endpoints' services: the stores (App login only, FU-021), token rotation, and the F7 startup check of the
    /// log pseudonym. Call after <c>AddZaghlolDatabase</c> with the App role and <c>AddZaghlolLogPseudonymizer</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolInstalls(this IServiceCollection services)
    {
        services.AddZaghlolInstallStores();
        services.AddSingleton<IInstallTokenRotator, InstallTokenRotator>();
        services.AddHostedService<InstallHashStartupCheck>();
        return services;
    }

    /// <summary>
    /// The sync's services (T-128): the service and its ports (<c>AddZaghlolSyncServices</c>) and the telemetry adapter. Call after
    /// <c>AddZaghlolDatabase</c> with the App role, <c>AddZaghlolKms</c>, <c>AddZaghlolCatalog</c>, <c>AddZaghlolFlagReader</c> and
    /// <c>AddZaghlolPrices</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolSync(this IServiceCollection services)
    {
        services.AddZaghlolSyncServices();
        services.TryAddSingleton<ZaghlolMetrics>();
        services.TryAddSingleton<ISyncTelemetry, SyncTelemetry>();
        return services;
    }

    /// <summary>
    /// Request log → exception handler → status pages → forwarded headers → routing → rate limit per client network →
    /// authentication → authorization → rate limit per install token → (response compression, if ever enabled) → response
    /// signing → endpoints. The request log is outermost so it sees the final status. The network limiter runs before
    /// authentication, so failed-token floods count. Compression stays outside signing, so signing sees uncompressed bytes.
    /// There is no HTTP logging middleware (headers, bodies and query strings are never logged).
    /// </summary>
    public static WebApplication UseZaghlolPipeline(this WebApplication app)
    {
        var limiters = app.Services.GetRequiredService<ZaghlolRateLimiters>();

        app.UseMiddleware<RequestLogMiddleware>();
        app.UseExceptionHandler();
        app.UseStatusCodePages();
        app.UseForwardedHeaders();
        app.UseRouting();
        app.UseRateLimiter(limiters.PerNetwork);
        app.UseAuthentication();
        app.UseAuthorization();
        app.UseRateLimiter(limiters.PerToken);
        app.UseMiddleware<ResponseSigningMiddleware>();
        return app;
    }
}
