using Microsoft.Extensions.Configuration;
using Zaghlol.Application.Config;
using Zaghlol.Application.Llm;

namespace Zaghlol.Infrastructure.Llm;

/// <summary>The active provider id from <c>Llm:ActiveProvider</c>: the fallback while remote config has no <c>llm.provider</c>.</summary>
public sealed class ConfiguredActiveLlmProviderId(IConfiguration configuration) : IActiveLlmProviderId
{
    public string Current => configuration[LlmProviderOptions.ActiveKey] ?? string.Empty;

    public ValueTask<string> CurrentAsync(CancellationToken cancellationToken) => ValueTask.FromResult(Current);
}

/// <summary>
/// The active provider id from remote config <c>llm.provider</c>, read on every call so a switch needs no restart and no deploy;
/// <c>Llm:ActiveProvider</c> applies while the key was never set.
/// </summary>
public sealed class RemoteConfigActiveLlmProviderId(IRemoteConfigService remote, ConfiguredActiveLlmProviderId fallback) : IActiveLlmProviderId
{
    public async ValueTask<string> CurrentAsync(CancellationToken cancellationToken)
    {
        var stored = (await remote.GetAsync(cancellationToken)).Get(RemoteConfigKeys.LlmProvider);
        return stored.Length > 0 ? stored : fallback.Current;
    }
}

/// <summary>Resolves providers by id; the active id is read on every call so a switch needs no restart. An unknown id fails closed.</summary>
public sealed class LlmProviderRegistry(IEnumerable<ILlmProvider> providers, IActiveLlmProviderId active) : ILlmProviderRegistry
{
    private readonly Dictionary<string, ILlmProvider> byId = providers.ToDictionary(p => p.Id, StringComparer.Ordinal);

    public ValueTask<string> ActiveIdAsync(CancellationToken cancellationToken) => active.CurrentAsync(cancellationToken);

    public async ValueTask<ILlmProvider> ActiveAsync(CancellationToken cancellationToken) =>
        Resolve(await active.CurrentAsync(cancellationToken));

    public ILlmProvider Resolve(string id) =>
        byId.TryGetValue(id, out var provider)
            ? provider
            : throw new LlmConfigurationException("The active LLM provider is not configured.");
}
