using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Http.Resilience;
using Microsoft.Extensions.Logging;
using Polly;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.GooglePlay;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.Purchases;

/// <summary>Purchase metrics and the 48 h alert over <see cref="ZaghlolMetrics"/> and <see cref="IAlertSignal"/>.</summary>
internal sealed class PurchaseTelemetry(ZaghlolMetrics metrics, IAlertSignal alerts) : IPurchaseTelemetry
{
    public void Verified(string store, string outcome, string code) => metrics.PurchaseVerified(store, outcome, code);

    public void Acknowledged(string channel, string outcome) => metrics.PurchaseAck(channel, outcome);

    public void TimeToAck(TimeSpan sincePurchase) => metrics.PurchaseAcknowledged(sincePurchase < TimeSpan.Zero ? TimeSpan.Zero : sincePurchase);

    public void SetUnacked(long lessThan48h, long atLeast48h, TimeSpan oldestAge) => metrics.SetUnacked(lessThan48h, atLeast48h, oldestAge);

    public void UnackedOver48h(Guid purchaseId) => alerts.Raise(AuditAlertRule.PurchaseUnacked48h, purchaseId: purchaseId);

    public void OwnershipChecked(string path, OwnershipOutcome outcome) => metrics.OwnershipCheck(path, outcome switch
    {
        OwnershipOutcome.Pass => "pass",
        OwnershipOutcome.Fail => "fail",
        _ => "unavailable",
    });
}

public static class PurchasesServiceCollectionExtensions
{
    public const string PlayHttpClientName = "google-play";

    /// <summary>
    /// The Play client and what it needs, for the API and the workers (T-130): <see cref="GooglePlayOptions"/> read and
    /// validated from <c>Purchases:Google</c> when the host starts, the shared <see cref="IStoreCallBudget"/>, the access-token
    /// source and the typed client with the resilience pipeline (T-130 design note §2). Call after <c>AddZaghlolTelemetry</c> (or
    /// <c>AddZaghlolApiTelemetry</c>).
    /// </summary>
    public static IServiceCollection AddZaghlolGooglePlay(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton<ZaghlolMetrics>();
        services.TryAddSingleton<IAlertSignal, AlertSignal>();
        services.TryAddSingleton(provider => GooglePlayOptions.Read(
            provider.GetRequiredService<IConfiguration>(),
            provider.GetRequiredService<IHostEnvironment>()));
        services.TryAddSingleton(provider => provider.GetRequiredService<GooglePlayOptions>().Catalog);
        services.TryAddSingleton<IStoreCallBudget>(provider => new StoreCallBudget(provider.GetRequiredService<GooglePlayOptions>().Budget));
        services.TryAddSingleton<IPlayAccessTokenSource, GoogleAccessTokenSource>();
        services.TryAddTransient<PlayAuthenticationHandler>();
        services.TryAddSingleton<IPurchaseTelemetry, PurchaseTelemetry>();
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, GooglePlayOptionsStartupCheck>());

        var http = services.AddHttpClient<IPlayDeveloperApi, PlayDeveloperApiClient>(PlayHttpClientName, (provider, client) =>
            {
                client.BaseAddress = provider.GetRequiredService<GooglePlayOptions>().BaseUrl;
                client.MaxResponseContentBufferSize = PlayDeveloperApiClient.MaxResponseBytes;

                // The resilience pipeline owns timeouts.
                client.Timeout = Timeout.InfiniteTimeSpan;
            })
            .RemoveAllLoggers();

        // Outer to inner: resilience (total timeout, retry, circuit breaker, attempt timeout), then the bearer token per attempt.
        http.AddResilienceHandler("google-play", static (pipeline, context) =>
            {
                var options = context.ServiceProvider.GetRequiredService<GooglePlayOptions>().Resilience;
                pipeline
                    .AddTimeout(options.TotalTimeout)
                    .AddRetry(new HttpRetryStrategyOptions
                    {
                        // Defaults handle 408, 429, 5xx, HttpRequestException and an attempt timeout; never another 4xx.
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
        http.AddHttpMessageHandler<PlayAuthenticationHandler>();
        return services;
    }

    /// <summary>
    /// The verify side on the App login (T-130): the purchase writer, the Google <see cref="IStoreVerification"/>, the support
    /// order lookup, the <see cref="NullVerifyGrant"/> placeholder (T-132 replaces it) and the Production startup check. Call
    /// after <c>AddZaghlolDatabase</c> with the App role and <see cref="AddZaghlolGooglePlay"/>.
    /// </summary>
    public static IServiceCollection AddZaghlolPurchaseVerification(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton<IPurchaseWriter, PurchaseWriter>();
        // Transient: they hold the typed Play HttpClient, whose handler the factory rotates (a singleton would pin one forever).
        services.TryAddEnumerable(ServiceDescriptor.Transient<IStoreVerification, PlayVerification>());
        services.TryAddSingleton<IVerifyGrant, NullVerifyGrant>();
        services.TryAddTransient<IPlayOrderLookup>(provider => new PlayOrderLookup(
            provider.GetRequiredService<IPlayDeveloperApi>(),
            provider.GetRequiredService<GooglePlayOptions>().OrderLookup,
            provider.GetRequiredService<IPurchaseTelemetry>(),
            provider.GetRequiredService<TimeProvider>()));
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, PurchasesStartupCheck>());
        return services;
    }

    /// <summary>The acknowledge sweeper's store (Worker login) and job. Call after <c>AddZaghlolDatabase</c> with the Worker role.</summary>
    public static IServiceCollection AddZaghlolPlayAckSweeper(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.AddZaghlolGooglePlay();
        services.TryAddSingleton<IPlayAckSweepStore, PlayAckSweepStore>();
        services.TryAddTransient<PlayAckSweepJob>();
        return services;
    }
}

/// <summary>
/// Builds <see cref="GooglePlayOptions"/> when the host starts, so a missing or invalid <c>Purchases:Google</c> stops it at once
/// (outside Development and Testing) instead of at the first purchase; and refuses any <see cref="IPlayDeveloperApi"/> other
/// than the real client in Production (a test fake can never serve users).
/// </summary>
internal sealed class GooglePlayOptionsStartupCheck(IServiceProvider services, IHostEnvironment environment) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        var options = services.GetRequiredService<GooglePlayOptions>();
        if (environment.IsProduction())
        {
            if (options.CredentialSource == PlayCredentialSource.None)
            {
                throw new PlayConfigurationException("Purchases:Google needs a credential in Production.");
            }

            if (services.GetRequiredService<IPlayDeveloperApi>() is not PlayDeveloperApiClient)
            {
                throw new PlayConfigurationException("Only the Google Play Developer API client may be registered in Production.");
            }
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}

/// <summary>
/// T-130 design note §0: Production refuses to start while verify would answer without an entitlement (<see cref="NullVerifyGrant"/>
/// still registered, T-132) or without an App Store verifier (T-131), so verify can't ship half-done. Nothing is echoed.
/// </summary>
internal sealed partial class PurchasesStartupCheck(
    IVerifyGrant grant,
    IEnumerable<IStoreVerification> verifiers,
    IHostEnvironment environment,
    ILogger<PurchasesStartupCheck> logger) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        if (!environment.IsProduction())
        {
            if (grant is NullVerifyGrant)
            {
                LogPlaceholder(logger);
            }

            return Task.CompletedTask;
        }

        if (grant is NullVerifyGrant)
        {
            throw new PurchasesConfigurationException("Verify has no entitlement composer (NullVerifyGrant is registered): T-132 must ship first.");
        }

        if (!verifiers.Any(v => v.Store == PurchaseStore.AppStore) || !verifiers.Any(v => v.Store == PurchaseStore.GooglePlay))
        {
            throw new PurchasesConfigurationException("Verify needs both a Google Play and an App Store verifier in Production.");
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    [LoggerMessage(Level = LogLevel.Warning, Message = "Purchase verify runs with the NullVerifyGrant placeholder: no entitlement is issued")]
    private static partial void LogPlaceholder(ILogger logger);
}

/// <summary>The purchase services are incomplete for Production. Constant message.</summary>
public sealed class PurchasesConfigurationException : SafeException
{
    public PurchasesConfigurationException()
        : base("The purchase services are not complete.")
    {
    }

    public PurchasesConfigurationException(string message)
        : base(message)
    {
    }

    public PurchasesConfigurationException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
