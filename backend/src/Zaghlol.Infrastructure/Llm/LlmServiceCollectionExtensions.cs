using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Llm;

namespace Zaghlol.Infrastructure.Llm;

public static class LlmServiceCollectionExtensions
{
    public const string HttpClientPrefix = "llm-";

    /// <summary>
    /// Registers the gateway core: one adapter (and one <see cref="HttpClient"/> and one <see cref="LlmCallGuard"/>) per configured
    /// provider under <c>Llm:Providers</c>, the registry and the startup check. The host must also register
    /// <see cref="ILlmApiKeyProvider"/> (T-333) and <see cref="ILlmPromptCatalog"/> (T-339). Not called by the API host yet.
    /// </summary>
    public static IServiceCollection AddZaghlolLlm(this IServiceCollection services, IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(services);
        var providers = LlmProviderOptions.ReadAll(configuration);

        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton<IActiveLlmProviderId>(new ConfiguredActiveLlmProviderId(configuration));
        services.TryAddSingleton<ILlmProviderRegistry, LlmProviderRegistry>();
        services.TryAddEnumerable(ServiceDescriptor.Singleton<IHostedService, LlmStartupCheck>());
        services.AddSingleton(new LlmRegisteredProviders(providers));

        foreach (var options in providers)
        {
            switch (options.Kind)
            {
                case LlmProviderKind.OpenAiResponses:
                    AddOpenAi(services, options);
                    break;
                case LlmProviderKind.Fake:
                    services.AddSingleton<ILlmProvider>(_ => options.FixturePath is { Length: > 0 } path
                        ? FakeLlmProvider.FromFixture(options.Id, path)
                        : new FakeLlmProvider(options.Id, []));
                    break;
            }
        }

        return services;
    }

    private static void AddOpenAi(IServiceCollection services, LlmProviderOptions options)
    {
        var name = HttpClientPrefix + options.Id;
        services.AddHttpClient(name, client =>
            {
                // The endpoint ends in a slash so the relative "v1/responses" keeps any path prefix of a gateway.
                var endpoint = options.Endpoint!.AbsoluteUri;
                client.BaseAddress = new Uri(endpoint.EndsWith('/') ? endpoint : endpoint + "/");
                client.MaxResponseContentBufferSize = OpenAiResponsesProvider.MaxResponseBytes;

                // The guard owns the timeouts.
                client.Timeout = Timeout.InfiniteTimeSpan;
            })
            .RemoveAllLoggers();

        services.AddSingleton<ILlmProvider>(provider => new OpenAiResponsesProvider(
            provider.GetRequiredService<IHttpClientFactory>().CreateClient(name),
            options,
            provider.GetRequiredService<ILlmApiKeyProvider>(),
            provider.GetRequiredService<ILlmPromptCatalog>(),
            new LlmCallGuard(
                options.Id,
                LlmGuardOptions.Default with { AttemptTimeout = options.AttemptTimeout },
                provider.GetRequiredService<TimeProvider>(),
                provider.GetRequiredService<ILoggerFactory>().CreateLogger("Zaghlol.Llm"))));
    }
}

/// <summary>The provider options read at registration (for the startup check).</summary>
internal sealed record LlmRegisteredProviders(IReadOnlyList<LlmProviderOptions> Providers);

/// <summary>
/// Fails the start when the fake provider is configured outside Development and Testing, when the active provider is not one of the
/// configured ones, or (outside Development and Testing) when an endpoint isn't https. The fake can never serve users.
/// </summary>
internal sealed class LlmStartupCheck(LlmRegisteredProviders registered, IActiveLlmProviderId active, IHostEnvironment environment) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        var relaxed = environment.IsDevelopment() || environment.IsEnvironment("Testing");
        foreach (var p in registered.Providers)
        {
            if (!relaxed && p.Kind == LlmProviderKind.Fake)
            {
                throw new LlmConfigurationException("The fake LLM provider may only be configured in Development and Testing.");
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
