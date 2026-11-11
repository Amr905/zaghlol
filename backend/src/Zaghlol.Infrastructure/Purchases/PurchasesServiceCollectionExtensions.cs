using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Http.Resilience;
using Microsoft.Extensions.Logging;
using Polly;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.AppStore;
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

    public void EnvironmentSeen(string store, PurchaseEnvironment environment) =>
        metrics.PurchaseEnvironment(store, PurchaseTags.EnvironmentName(environment));

    public void AppleJwsChecked(JwsSource source, AppleJwsFailure? failure) =>
        metrics.AppleJws(PurchaseTags.JwsSourceName(source), PurchaseTags.JwsOutcome(failure));
}

public static class PurchasesServiceCollectionExtensions
{
    public const string PlayHttpClientName = "google-play";

    /// <summary>
    /// <c>Retry-After</c> values up to this are honoured inside the 20 s total; a longer one ends the call at once as
    /// <see cref="PlayCallOutcome.RateLimited"/> (or a 503 as <see cref="PlayCallOutcome.ServerError"/>) carrying Play's value, so the
    /// caller defers instead of timing out (T-133 §5, as FU-092 item 3 for Apple).
    /// </summary>
    public static readonly TimeSpan MaxInlineRetryAfter = TimeSpan.FromSeconds(5);

    /// <summary>
    /// The Play client and what it needs, for the API (<see cref="PlayBudgetPartition.Api"/>) and the worker
    /// (<see cref="PlayBudgetPartition.Worker"/>, T-133): <see cref="GooglePlayOptions"/> read and validated from <c>Purchases:Google</c>
    /// when the host starts, this process's partition of the Play budget, the access-token source and the typed client with the
    /// resilience pipeline (T-130 design note §2), the per-attempt budget handler and the bearer token. Idempotent for one partition;
    /// asking for the other one throws. Call after <c>AddZaghlolTelemetry</c> (or <c>AddZaghlolApiTelemetry</c>).
    /// </summary>
    public static IServiceCollection AddZaghlolGooglePlay(this IServiceCollection services, PlayBudgetPartition partition = PlayBudgetPartition.Api)
    {
        ArgumentNullException.ThrowIfNull(services);

        if (services.FirstOrDefault(d => d.ServiceType == typeof(GooglePlayRegistered))?.ImplementationInstance is GooglePlayRegistered registered)
        {
            return registered.Partition == partition
                ? services
                : throw new InvalidOperationException("The Google Play services are already registered for the other budget partition.");
        }

        services.AddSingleton(new GooglePlayRegistered(partition));
        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton<ZaghlolMetrics>();
        services.TryAddSingleton<IAlertSignal, AlertSignal>();
        services.TryAddSingleton(provider => GooglePlayOptions.Read(
            provider.GetRequiredService<IConfiguration>(),
            provider.GetRequiredService<IHostEnvironment>()));
        services.TryAddSingleton(provider => provider.GetRequiredService<GooglePlayOptions>().Catalog);
        services.TryAddSingleton(provider => new PlayCallBudget(provider.GetRequiredService<GooglePlayOptions>().Budget, partition));
        services.TryAddSingleton<IStoreCallBudget>(provider => provider.GetRequiredService<PlayCallBudget>());
        services.TryAddSingleton<IPlayAccessTokenSource, GoogleAccessTokenSource>();
        services.TryAddTransient<PlayBudgetHandler>();
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

        // Outer to inner: resilience (total timeout, retry, circuit breaker, attempt timeout), then one budget permit and the bearer
        // token per attempt.
        http.AddResilienceHandler("google-play", static (pipeline, context) =>
            {
                var options = context.ServiceProvider.GetRequiredService<GooglePlayOptions>().Resilience;
                var clock = context.ServiceProvider.GetRequiredService<TimeProvider>();
                pipeline
                    .AddTimeout(options.TotalTimeout)
                    .AddRetry(new HttpRetryStrategyOptions
                    {
                        // The default transient set (408, 429, 5xx, HttpRequestException, an attempt timeout; never another 4xx, and
                        // never our own budget refusal), minus a 429 or 503 asking for more than MaxInlineRetryAfter.
                        ShouldHandle = args => ValueTask.FromResult(ShouldRetry(args.Outcome, clock)),
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
        http.AddHttpMessageHandler<PlayBudgetHandler>();
        http.AddHttpMessageHandler<PlayAuthenticationHandler>();
        return services;
    }

    /// <summary>The retry predicate of the Play pipeline.</summary>
    internal static bool ShouldRetry(Outcome<HttpResponseMessage> outcome, TimeProvider clock) =>
        HttpClientResiliencePredicates.IsTransient(outcome)
        && !(outcome.Result is { } response
             && (int)response.StatusCode is 429 or 503
             && PlayDeveloperApiClient.RetryAfter(response, clock) > MaxInlineRetryAfter);

    /// <summary>
    /// The verify side on the App login (T-130, T-131): the purchase writer, the Google and App Store <see cref="IStoreVerification"/>s,
    /// both support order lookups, the <see cref="NullVerifyGrant"/> placeholder (T-132 replaces it) and the Production startup
    /// check. Call after <c>AddZaghlolDatabase</c> with the App role and <see cref="AddZaghlolGooglePlay"/>; it adds
    /// <see cref="AppStoreServiceCollectionExtensions.AddZaghlolAppStore"/> itself.
    /// </summary>
    public static IServiceCollection AddZaghlolPurchaseVerification(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.AddZaghlolAppStore();
        services.TryAddSingleton<IPurchaseWriter, PurchaseWriter>();
        // Transient: they hold the typed store HttpClients, whose handlers the factory rotates (a singleton would pin one forever).
        services.TryAddEnumerable(ServiceDescriptor.Transient<IStoreVerification, PlayVerification>());
        services.TryAddEnumerable(ServiceDescriptor.Transient<IStoreVerification, AppStoreVerification>());
        services.TryAddTransient<IAppStoreOrderLookup, AppStoreOrderLookup>();
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

        services.AddZaghlolGooglePlay(PlayBudgetPartition.Worker);
        services.TryAddSingleton<IPlayAckSweepStore, PlayAckSweepStore>();
        services.TryAddTransient<PlayAckSweepJob>();
        return services;
    }
}

/// <summary>Marks <see cref="PurchasesServiceCollectionExtensions.AddZaghlolGooglePlay"/> as done (and for which partition).</summary>
internal sealed record GooglePlayRegistered(PlayBudgetPartition Partition);

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
