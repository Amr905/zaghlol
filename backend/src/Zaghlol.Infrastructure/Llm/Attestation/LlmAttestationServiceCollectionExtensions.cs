using System.Diagnostics.Metrics;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Attestation;
using Zaghlol.Application.Purchases.Attestation;
using Zaghlol.Infrastructure.GooglePlay;
using Zaghlol.Infrastructure.Observability;

// In the Attestation namespace so the API host (which already imports it) needs no new using.
namespace Zaghlol.Infrastructure.Attestation;

public static class LlmAttestationServiceCollectionExtensions
{
    /// <summary>
    /// LLM attestation (T-336): <see cref="LlmAttestationSettings"/> resolved once from <c>Llm:Attestation:*</c> and the host
    /// environment (the mode guard), <see cref="ILlmAttestationVerifier"/> over the existing Play Integrity and App Attest
    /// verifiers, readiness, the metric and a startup check. Call after <c>AddZaghlolAttestation</c> and <c>AddZaghlolSeats</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolLlmAttestation(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(provider =>
        {
            var configuration = provider.GetRequiredService<IConfiguration>();
            return LlmAttestationSettings.Resolve(
                configuration[LlmAttestationSettings.ModeKey],
                configuration[LlmAttestationSettings.DevProofKeyKey],
                provider.GetRequiredService<IHostEnvironment>().EnvironmentName);
        });
        services.TryAddSingleton<ILlmAttestationReadiness, StoreLlmAttestationReadiness>();
        services.TryAddSingleton<ILlmAttestationTelemetry, LlmAttestationMetrics>();
        services.TryAddTransient<ILlmAttestationVerifier, LlmAttestationVerifier>();
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, LlmAttestationStartupCheck>());
        return services;
    }
}

/// <summary>
/// A platform is configured when its store verifier has real settings: Play = a credential source other than <c>None</c> and a
/// package name; App Attest = a real Team ID (not the Development/Testing placeholder) and a bundle ID.
/// </summary>
internal sealed class StoreLlmAttestationReadiness(GooglePlayOptions play, AppAttestOptions appAttest) : ILlmAttestationReadiness
{
    public const string PlaceholderTeamId = "TESTTEAM00";

    public bool IsConfigured(LlmAttestPlatform platform) => platform switch
    {
        LlmAttestPlatform.Android => play.CredentialSource != PlayCredentialSource.None && play.Catalog.PackageName.Length > 0,
        LlmAttestPlatform.Ios => !appAttest.AppId.StartsWith(PlaceholderTeamId + ".", StringComparison.Ordinal) && !appAttest.AppId.EndsWith('.'),
        _ => false,
    };
}

/// <summary><c>zaghlol.llm.attestation</c> on the Zaghlol meter; every tag comes from a fixed set.</summary>
internal sealed class LlmAttestationMetrics : ILlmAttestationTelemetry, IDisposable
{
    public const string InstrumentName = "zaghlol.llm.attestation";

    private readonly Meter meter = new(ZaghlolMetrics.MeterName);
    private readonly Counter<long> decisions;

    public LlmAttestationMetrics()
    {
        decisions = meter.CreateCounter<long>(InstrumentName, description: "LLM attestation decisions by feature, mode, platform, verdict and reason code.");
    }

    public void Decided(LlmFeature feature, LlmAttestationMode mode, LlmAttestPlatform platform, LlmAttestationVerdict verdict, string reason)
    {
        var fixedReason = LlmAttestationReasons.All.Contains(reason, StringComparer.Ordinal) ? reason : "other";
        decisions.Add(
            1,
            new KeyValuePair<string, object?>("feature", LlmAttestationVerifier.FeatureTag(feature)),
            new KeyValuePair<string, object?>("mode", LlmAttestationVerifier.ModeTag(mode)),
            new KeyValuePair<string, object?>("platform", platform == LlmAttestPlatform.Android ? "android" : "ios"),
            new KeyValuePair<string, object?>("verdict", LlmAttestationVerifier.VerdictTag(verdict)),
            new KeyValuePair<string, object?>("reason", fixedReason));
    }

    public void Dispose() => meter.Dispose();
}

/// <summary>
/// Resolves the settings when the host starts, so a forbidden mode or dev key stops it (ask-llm §5). In Production it also
/// refuses anything but the real verifier in <see cref="LlmAttestationMode.Enforce"/> without a dev key.
/// </summary>
internal sealed class LlmAttestationStartupCheck(IServiceProvider services, IHostEnvironment environment) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        var settings = services.GetRequiredService<LlmAttestationSettings>();
        if (environment.IsProduction())
        {
            using var scope = services.CreateScope();
            if (settings.Mode != LlmAttestationMode.Enforce
                || settings.HasDevProofKey
                || scope.ServiceProvider.GetRequiredService<ILlmAttestationVerifier>() is not LlmAttestationVerifier { Mode: LlmAttestationMode.Enforce }
                || services.GetRequiredService<IPlayIntegrityVerifier>() is not PlayIntegrityVerifier
                || services.GetRequiredService<IAppAttestVerifier>() is not AppAttestVerifier)
            {
                throw new LlmAttestationConfigurationException("Production must enforce LLM attestation with the real verifiers.");
            }
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
