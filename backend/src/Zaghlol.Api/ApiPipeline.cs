using Serilog;
using Zaghlol.Api.Problems;
using Zaghlol.Api.Signing;

namespace Zaghlol.Api;

/// <summary>The HTTP pipeline, shared by <c>Program</c> and the signing test host so both run the same order.</summary>
internal static class ApiPipeline
{
    /// <summary>RFC 9457 problem details and the global exception handler.</summary>
    public static IServiceCollection AddZaghlolHttp(this IServiceCollection services)
    {
        services.AddProblemDetails(options => options.CustomizeProblemDetails = ProblemDetailsCustomizer.Customize);
        services.AddExceptionHandler<GlobalExceptionHandler>();
        return services;
    }

    /// <summary>
    /// Exception handler → status pages → request logging → (response compression, if ever enabled) → routing →
    /// (auth) → response signing → endpoints. Compression stays outside signing, so signing sees uncompressed bytes.
    /// </summary>
    public static WebApplication UseZaghlolPipeline(this WebApplication app)
    {
        app.UseExceptionHandler();
        app.UseStatusCodePages();
        app.UseSerilogRequestLogging();
        app.UseRouting();
        app.UseMiddleware<ResponseSigningMiddleware>();
        return app;
    }
}
