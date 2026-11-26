using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Config;
using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Llm.Keys;

namespace Zaghlol.Infrastructure.Llm;

public static class LlmServiceCollectionExtensions
{
    public const string HttpClientPrefix = "llm-";

    /// <summary>
    /// Registers the gateway core: one adapter (and one <see cref="HttpClient"/> and one <see cref="LlmCallGuard"/>) per configured
    /// provider under <c>Llm:Providers</c>, the registry, the startup check and the provider keys (<see cref="LlmApiKeyStore"/> from
    /// the KMS secret store, T-333) and the embedded prompt catalogue (T-349). Called by the API host.
    /// </summary>
    public static IServiceCollection AddZaghlolLlm(this IServiceCollection services, IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(services);
        var providers = LlmProviderOptions.ReadAll(configuration);

        services.TryAddSingleton(TimeProvider.System);
        var configured = new ConfiguredActiveLlmProviderId(configuration);
        services.TryAddSingleton(configured);

        // Remote config llm.provider when the host registered it (AddZaghlolRemoteConfig), else Llm:ActiveProvider.
        services.TryAddSingleton<IActiveLlmProviderId>(provider => provider.GetService<IRemoteConfigService>() is { } remote
            ? new RemoteConfigActiveLlmProviderId(remote, configured)
            : configured);
        services.TryAddSingleton<ILlmProviderRegistry, LlmProviderRegistry>();

        // The static system prompts are embedded in Zaghlol.Application (T-349); a host or a test may register its own catalogue first.
        services.TryAddSingleton<ILlmPromptCatalog, Zaghlol.Application.Llm.Prompts.EmbeddedLlmPromptCatalog>();
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, LlmStartupCheck>());

        // T-333: provider keys from the KMS secret store, loaded once at start; a host's own ILlmApiKeyProvider (tests) wins.
        services.TryAddSingleton<LlmApiKeyStore>();
        services.TryAddSingleton<ILlmApiKeyProvider>(provider => provider.GetRequiredService<LlmApiKeyStore>());
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, LlmKeyStartup>(provider => new LlmKeyStartup(
            provider,
            provider.GetRequiredService<LlmRegisteredProviders>(),
            provider.GetService<IConfiguration>() ?? configuration,
            provider.GetRequiredService<IHostEnvironment>(),
            provider.GetRequiredService<ILogger<LlmKeyStartup>>())));
        services.AddSingleton(new LlmRegisteredProviders(providers));
        services.TryAddSingleton<IKnownLlmProviderIds>(sp => new ConfiguredLlmProviderIds(providers, sp));
        services.TryAddSingleton<ILlmProviderIdentity>(new ConfiguredLlmProviderIdentity(configured, providers));

        foreach (var options in providers)
        {
            switch (options.Kind)
            {
                case LlmProviderKind.OpenAiResponses:
                    AddOpenAi(services, options);
                    break;
                case LlmProviderKind.VertexGemini:
                    AddVertex(services, options);
                    break;
                case LlmProviderKind.AnthropicMessages:
                    AddAnthropic(services, options);
                    break;
            }
        }

        return services;
    }

    private static void AddOpenAi(IServiceCollection services, LlmProviderOptions options)
    {
        var name = AddClient(services, options, OpenAiResponsesProvider.MaxResponseBytes);
        services.AddSingleton<ILlmProvider>(provider => new OpenAiResponsesProvider(
            provider.GetRequiredService<IHttpClientFactory>().CreateClient(name),
            options,
            provider.GetRequiredService<ILlmApiKeyProvider>(),
            provider.GetRequiredService<ILlmPromptCatalog>(),
            NewGuard(provider, options)));
    }

    private static void AddVertex(IServiceCollection services, LlmProviderOptions options)
    {
        var name = AddClient(services, options, VertexGeminiProvider.MaxResponseBytes);
        services.AddSingleton<ILlmProvider>(provider => new VertexGeminiProvider(
            provider.GetRequiredService<IHttpClientFactory>().CreateClient(name),
            options,
            provider.GetRequiredService<ILlmApiKeyProvider>(),
            provider.GetService<IVertexAccessTokenSource>() ?? new GoogleVertexAccessTokenSource(),
            provider.GetRequiredService<ILlmPromptCatalog>(),
            NewGuard(provider, options)));
    }

    private static void AddAnthropic(IServiceCollection services, LlmProviderOptions options)
    {
        var name = AddClient(services, options, AnthropicMessagesProvider.MaxResponseBytes);
        services.AddSingleton<ILlmProvider>(provider => new AnthropicMessagesProvider(
            provider.GetRequiredService<IHttpClientFactory>().CreateClient(name),
            options,
            provider.GetRequiredService<ILlmApiKeyProvider>(),
            provider.GetRequiredService<ILlmPromptCatalog>(),
            NewGuard(provider, options)));
    }

    private static string AddClient(IServiceCollection services, LlmProviderOptions options, int maxResponseBytes)
    {
        var name = HttpClientPrefix + options.Id;
        services.AddHttpClient(name, client =>
            {
                // The endpoint ends in a slash so a relative path keeps any path prefix of a gateway.
                var endpoint = options.Endpoint!.AbsoluteUri;
                client.BaseAddress = new Uri(endpoint.EndsWith('/') ? endpoint : endpoint + "/");
                client.MaxResponseContentBufferSize = maxResponseBytes;

                // The guard owns the timeouts.
                client.Timeout = Timeout.InfiniteTimeSpan;
            })
            .RemoveAllLoggers();
        return name;
    }

    private static LlmCallGuard NewGuard(IServiceProvider provider, LlmProviderOptions options) => new(
        options.Id,
        LlmGuardOptions.Default with { AttemptTimeout = options.AttemptTimeout },
        provider.GetRequiredService<TimeProvider>(),
        provider.GetRequiredService<ILoggerFactory>().CreateLogger("Zaghlol.Llm"));
}

/// <summary>The provider ids that have an adapter in this host (FU-411: the admin API refuses an unknown <c>llm.provider</c>).</summary>
internal sealed class ConfiguredLlmProviderIds(IReadOnlyList<LlmProviderOptions> providers, IServiceProvider services) : IKnownLlmProviderIds
{
    public bool IsKnown(string providerId) =>
        providers.Any(p => string.Equals(p.Id, providerId, StringComparison.Ordinal)
            && p.DisplayNameAr is { Length: > 0 } && p.DisplayNameEn is { Length: > 0 })
        && (services.GetService<ILlmApiKeyProvider>()?.HasKey(providerId) ?? true);
}

/// <summary>The provider options read at registration (for the startup check).</summary>
internal sealed record LlmRegisteredProviders(IReadOnlyList<LlmProviderOptions> Providers);

/// <summary>
/// Fails the start when the active provider is not one of the
/// configured ones, or (outside Development and Testing) when an endpoint isn't https. The fake can never serve users.
/// </summary>
internal sealed class LlmStartupCheck(LlmRegisteredProviders registered, ConfiguredActiveLlmProviderId active, IHostEnvironment environment) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        var relaxed = environment.IsDevelopment() || environment.IsEnvironment("Testing");
        foreach (var p in registered.Providers)
        {
            if (string.IsNullOrEmpty(p.DisplayNameAr) || string.IsNullOrEmpty(p.DisplayNameEn))
            {
                throw new LlmConfigurationException($"Llm:Providers:{p.Id}:DisplayNameAr and :DisplayNameEn are required.");
            }

            if (!relaxed && p.Endpoint is { } endpoint && endpoint.Scheme != "https")
            {
                throw new LlmConfigurationException("LLM provider endpoints must be https outside Development and Testing.");
            }
        }

        if (registered.Providers.Count > 0 && !registered.Providers.Any(p => string.Equals(p.Id, active.Current, StringComparison.Ordinal)))
        {
            throw new LlmConfigurationException("Llm:ActiveProvider must name a configured provider.");
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
