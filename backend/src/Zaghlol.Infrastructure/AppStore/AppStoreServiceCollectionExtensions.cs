using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Http.Resilience;
using Polly;
using Zaghlol.Application.Purchases;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.AppStore;

public static class AppStoreServiceCollectionExtensions
{
    /// <summary>
    /// <c>Retry-After</c> values up to this are honoured inside the 20 s total; a longer one ends the call at once as
    /// <see cref="AppStoreCallOutcome.RateLimited"/> (or a 503 as <see cref="AppStoreCallOutcome.ServerError"/>) carrying Apple's
    /// value, so the caller defers instead of timing out (FU-092 item 3).
    /// </summary>
    public static readonly TimeSpan MaxInlineRetryAfter = TimeSpan.FromSeconds(5);

    /// <summary>
    /// The App Store services for the API (verify, support order lookup; <see cref="AppleBudgetPartition.Api"/>) and the ASSN V2 worker
    /// (<see cref="AppleBudgetPartition.Worker"/>, T-134): <see cref="AppStoreOptions"/> read and validated from <c>Purchases:Apple</c>
    /// when the host starts, the pinned-root <see cref="IAppleJwsVerifier"/>, the API token source, this process's partition of the
    /// Apple budget and the per-install verify limiter, and the two environment clients with the T-130 resilience pipeline, the
    /// per-attempt budget handler and the bearer token. Idempotent for one partition; asking for the other one throws. Call after
    /// <c>AddZaghlolTelemetry</c> (or <c>AddZaghlolApiTelemetry</c>).
    /// </summary>
    public static IServiceCollection AddZaghlolAppStore(this IServiceCollection services, AppleBudgetPartition partition = AppleBudgetPartition.Api)
    {
        ArgumentNullException.ThrowIfNull(services);

        if (services.FirstOrDefault(d => d.ServiceType == typeof(AppStoreRegistered))?.ImplementationInstance is AppStoreRegistered registered)
        {
            return registered.Partition == partition
                ? services
                : throw new InvalidOperationException("The App Store services are already registered for the other budget partition.");
        }

        services.AddSingleton(new AppStoreRegistered(partition));
        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton<ZaghlolMetrics>();
        services.TryAddSingleton<IAlertSignal, AlertSignal>();
        services.TryAddSingleton(provider => AppStoreOptions.Read(
            provider.GetRequiredService<IConfiguration>(),
            provider.GetRequiredService<IHostEnvironment>()));
        services.TryAddSingleton(provider => provider.GetRequiredService<AppStoreOptions>().Catalog);
        services.TryAddSingleton<IAppleJwsVerifier>(provider => new AppleJwsVerifier(provider.GetRequiredService<AppStoreOptions>().TrustAnchor()));
        services.TryAddSingleton<IAppStoreApiTokenSource, AppStoreApiTokenProvider>();
        services.TryAddSingleton(provider => new AppleCallBudget(provider.GetRequiredService<AppStoreOptions>().Budget, partition));
        services.TryAddSingleton<IAppleVerifyLimiter>(provider => new AppleVerifyLimiter(provider.GetRequiredService<AppStoreOptions>().Budget));
        services.TryAddTransient<AppleBudgetHandler>();
        services.TryAddTransient<AppStoreAuthenticationHandler>();
        services.TryAddTransient<IAppStoreServerApi, AppStoreServerApiClient>();
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, AppStoreStartupCheck>());

        AddClient(services, AppStoreServerApiClient.ProductionClient, static options => options.ProductionUrl);
        AddClient(services, AppStoreServerApiClient.SandboxClient, static options => options.SandboxUrl);
        return services;
    }

    private static void AddClient(IServiceCollection services, string name, Func<AppStoreOptions, Uri> baseUrl)
    {
        var http = services.AddHttpClient(name, (provider, client) =>
            {
                client.BaseAddress = baseUrl(provider.GetRequiredService<AppStoreOptions>());
                client.MaxResponseContentBufferSize = AppStoreServerApiClient.MaxResponseBytes;

                // The resilience pipeline owns timeouts.
                client.Timeout = Timeout.InfiniteTimeSpan;
            })
            .RemoveAllLoggers();

        // Outer to inner: resilience (total timeout, retry, circuit breaker, attempt timeout), then one budget permit and a bearer
        // token per attempt. Each environment has its own pipeline, so a sandbox outage never opens the production circuit.
        http.AddResilienceHandler(name, static (pipeline, context) =>
            {
                var options = context.ServiceProvider.GetRequiredService<AppStoreOptions>().Resilience;
                pipeline
                    .AddTimeout(options.TotalTimeout)
                    .AddRetry(new HttpRetryStrategyOptions
                    {
                        // The default transient set (408, 429, 5xx, HttpRequestException, an attempt timeout; never another 4xx, and
                        // never our own budget refusal), minus a 429 or 503 asking for more than MaxInlineRetryAfter (FU-092 item 3).
                        ShouldHandle = static args => ValueTask.FromResult(ShouldRetry(args.Outcome)),
                        MaxRetryAttempts = options.MaxRetries,
                        BackoffType = DelayBackoffType.Exponential,
                        UseJitter = true,
                        Delay = options.RetryBaseDelay,
                        ShouldRetryAfterHeader = true,
                    })
                    .AddCircuitBreaker(new HttpCircuitBreakerStrategyOptions
                    {
                        FailureRatio = options.FailureRatio,
                        MinimumThroughput = options.MinimumThroughput,
                        SamplingDuration = options.SamplingDuration,
                        BreakDuration = options.BreakDuration,
                    })
                    .AddTimeout(options.AttemptTimeout);
            });
        http.AddHttpMessageHandler<AppleBudgetHandler>();
        http.AddHttpMessageHandler<AppStoreAuthenticationHandler>();
    }

    /// <summary>The retry predicate of the App Store pipeline.</summary>
    internal static bool ShouldRetry(Outcome<HttpResponseMessage> outcome) =>
        HttpClientResiliencePredicates.IsTransient(outcome)
        && !(outcome.Result is { } response
             && (int)response.StatusCode is 429 or 503
             && RetryAfter(response) > MaxInlineRetryAfter);

    private static TimeSpan? RetryAfter(HttpResponseMessage response) =>
        response.Headers.RetryAfter?.Delta
        ?? (response.Headers.RetryAfter?.Date is { } date ? date - DateTimeOffset.UtcNow : null);

    /// <summary>Marks <see cref="AddZaghlolAppStore"/> as done (and for which partition), so a second call doesn't stack a second pipeline.</summary>
    private sealed record AppStoreRegistered(AppleBudgetPartition Partition);
}

/// <summary>
/// Builds <see cref="AppStoreOptions"/> and loads the pinned Apple root when the host starts, so a missing or invalid
/// <c>Purchases:Apple</c> or a wrong root resource stops it at once (outside Development and Testing for the configuration; always
/// for the root). In Production it also refuses any <see cref="IAppStoreServerApi"/> or <see cref="IAppleJwsVerifier"/> other than
/// the real ones (a test fake can never serve users) and a missing API key.
/// </summary>
internal sealed class AppStoreStartupCheck(IServiceProvider services, IHostEnvironment environment) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        var options = services.GetRequiredService<AppStoreOptions>();
        AppleRootCertificate.Load();
        if (environment.IsProduction())
        {
            if (!options.HasCredential || options.TestRoot is not null)
            {
                throw new AppStoreConfigurationException("Purchases:Apple needs the In-App Purchase key and the pinned Apple root in Production.");
            }

            if (services.GetRequiredService<IAppStoreServerApi>() is not AppStoreServerApiClient
                || services.GetRequiredService<IAppleJwsVerifier>() is not AppleJwsVerifier)
            {
                throw new AppStoreConfigurationException("Only the App Store Server API client and the Apple JWS verifier may be registered in Production.");
            }
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
