using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Zaghlol.Application.Accounts;

namespace Zaghlol.Infrastructure.Accounts;

public static class AccountsServiceCollectionExtensions
{
    /// <summary>The longest wait for Apple's token endpoint.</summary>
    public static readonly TimeSpan AppleTimeout = TimeSpan.FromSeconds(10);

    /// <summary>
    /// Accounts (T-135): <see cref="AccountsOptions"/> read and validated at startup, the account stores and transaction on the App
    /// login, the replay guard, the Apple token vault and client, <see cref="SignInService"/> and <see cref="AccountLifecycleService"/>.
    /// Call after <c>AddZaghlolKms</c>, <c>AddZaghlolSeatKeys</c>, <c>AddZaghlolSeats</c>, <c>AddZaghlolEntitlements</c> and
    /// <c>AddZaghlolDatabase</c>. The ID-token verifier (JWKS) is registered by the Api (<c>AddZaghlolIdTokenVerification</c>); tests
    /// replace <see cref="IIdTokenVerifier"/> and <see cref="IAppleAccountClient"/> with fakes (no network).
    /// </summary>
    public static IServiceCollection AddZaghlolAccounts(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton(provider => AccountsOptions.Read(
            provider.GetRequiredService<IConfiguration>(),
            provider.GetRequiredService<IHostEnvironment>()));
        services.TryAddSingleton<IAccountStore, NpgsqlAccountStore>();
        services.TryAddSingleton<IAccountTransactionFactory, AccountTransactionFactory>();
        services.TryAddSingleton<IIdTokenReplayGuard, NpgsqlIdTokenReplayGuard>();
        services.TryAddSingleton<IAppleTokenVault, AppleTokenVault>();
        services.TryAddSingleton<IAppleAccountClient, AppleAccountClient>();
        services.TryAddSingleton<SignInService>();
        services.TryAddSingleton<AccountLifecycleService>();
        services.AddHttpClient(AppleAccountClient.HttpClientName, client =>
            {
                client.Timeout = AppleTimeout;
                client.MaxResponseContentBufferSize = 64 * 1024;
            })
            .RemoveAllLoggers();
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, AccountsStartupCheck>());
        return services;
    }
}

/// <summary>Reads <see cref="AccountsOptions"/> at startup, so a misconfigured Production host stops instead of failing the first sign-in.</summary>
internal sealed class AccountsStartupCheck(IServiceProvider services) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        _ = services.GetRequiredService<AccountsOptions>();
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
