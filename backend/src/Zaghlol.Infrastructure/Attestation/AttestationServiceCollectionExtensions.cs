using System.Net.Http.Headers;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Http.Resilience;
using Polly;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Purchases.Attestation;
using Zaghlol.Infrastructure.AppStore;
using Zaghlol.Infrastructure.GooglePlay;
using Zaghlol.Infrastructure.Purchases;

namespace Zaghlol.Infrastructure.Attestation;

/// <summary>The <c>purchases.playintegrity</c> OAuth token, from the same <c>Purchases:Google</c> credential.</summary>
internal sealed class PlayIntegrityAccessTokenSource(GooglePlayOptions options) : GoogleAccessTokenSource(options, IntegrityScope)
{
    public const string IntegrityScope = "https://www.googleapis.com/auth/playintegrity";
}

/// <summary>Adds the Play Integrity bearer token to each attempt.</summary>
internal sealed class PlayIntegrityAuthenticationHandler(PlayIntegrityAccessTokenSource tokens) : DelegatingHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (await tokens.GetTokenAsync(cancellationToken) is { } token)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Reveal());
        }

        return await base.SendAsync(request, cancellationToken);
    }
}

public static class AttestationServiceCollectionExtensions
{
    public const string PlayIntegrityHttpClientName = "play-integrity";

    /// <summary>
    /// The attestation verifiers (T-181): <see cref="IPlayIntegrityVerifier"/> (typed client with its own resilience pipeline and
    /// OAuth scope, the <c>replay_guard</c> writer on the App login) and <see cref="IAppAttestVerifier"/> (pinned Apple App
    /// Attestation Root CA). Call after <c>AddZaghlolDatabase</c> (App), <c>AddZaghlolGooglePlay</c> and
    /// <c>AddZaghlolPurchaseVerification</c>. T-185 wires it into the API.
    /// </summary>
    public static IServiceCollection AddZaghlolAttestation(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton(provider => AttestationOptionsReader.ReadPlayIntegrity(
            provider.GetRequiredService<IConfiguration>(),
            provider.GetRequiredService<IHostEnvironment>(),
            provider.GetRequiredService<GooglePlayOptions>().Catalog.PackageName));
        services.TryAddSingleton(provider => AttestationOptionsReader.ReadAppAttest(
            provider.GetRequiredService<IConfiguration>(),
            provider.GetRequiredService<IHostEnvironment>(),
            provider.GetRequiredService<AppStoreCatalog>().BundleId));
        services.TryAddSingleton<PlayIntegrityAccessTokenSource>();
        services.TryAddTransient<PlayIntegrityAuthenticationHandler>();
        services.TryAddSingleton<IPlayIntegrityReplayGuard, NpgsqlPlayIntegrityReplayGuard>();
        services.TryAddTransient<IPlayIntegrityVerifier, PlayIntegrityVerifier>();
        services.TryAddSingleton<IAppAttestVerifier, AppAttestVerifier>();
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, AttestationStartupCheck>());

        var http = services.AddHttpClient<IPlayIntegrityDecoder, PlayIntegrityClient>(PlayIntegrityHttpClientName, (provider, client) =>
            {
                client.BaseAddress = provider.GetRequiredService<PlayIntegrityOptions>().BaseUrl;
                client.MaxResponseContentBufferSize = PlayIntegrityClient.MaxResponseBytes;
                client.Timeout = Timeout.InfiniteTimeSpan;
            })
            .RemoveAllLoggers();

        http.AddResilienceHandler(PlayIntegrityHttpClientName, static (pipeline, context) =>
            {
                var options = context.ServiceProvider.GetRequiredService<PlayIntegrityOptions>();
                pipeline
                    .AddTimeout(options.TotalTimeout)
                    .AddRetry(new HttpRetryStrategyOptions
                    {
                        MaxRetryAttempts = 1,
                        BackoffType = DelayBackoffType.Constant,
                        Delay = TimeSpan.FromMilliseconds(200),
                        UseJitter = true,
                    })
                    .AddTimeout(options.AttemptTimeout);
            });
        http.AddHttpMessageHandler<PlayIntegrityAuthenticationHandler>();
        return services;
    }
}

/// <summary>
/// Reads both option sets and loads the pinned root when the host starts, so a wrong <c>Attestation</c> configuration or root
/// resource stops it; in Production only the real verifiers may be registered.
/// </summary>
internal sealed class AttestationStartupCheck(IServiceProvider services, IHostEnvironment environment) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        AppAttestRootCertificate.Load();
        services.GetRequiredService<PlayIntegrityOptions>();
        services.GetRequiredService<AppAttestOptions>();
        if (environment.IsProduction()
            && (services.GetRequiredService<IAppAttestVerifier>() is not AppAttestVerifier
                || services.GetRequiredService<IPlayIntegrityVerifier>() is not PlayIntegrityVerifier))
        {
            throw new AttestationConfigurationException("Only the real attestation verifiers may be registered in Production.");
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
