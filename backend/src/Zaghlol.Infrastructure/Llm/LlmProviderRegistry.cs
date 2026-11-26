using Microsoft.Extensions.Configuration;
using Zaghlol.Application.Llm;

namespace Zaghlol.Infrastructure.Llm;

/// <summary>The active provider id from <c>Llm:ActiveProvider</c> (T-334 replaces this with remote config <c>llm.provider</c>).</summary>
public sealed class ConfiguredActiveLlmProviderId(IConfiguration configuration) : IActiveLlmProviderId
{
    public string Current => configuration[LlmProviderOptions.ActiveKey] ?? string.Empty;
}

/// <summary>Resolves providers by id; the active id is read on every call so a switch needs no restart. An unknown id fails closed.</summary>
public sealed class LlmProviderRegistry(IEnumerable<ILlmProvider> providers, IActiveLlmProviderId active) : ILlmProviderRegistry
{
    private readonly Dictionary<string, ILlmProvider> byId = providers.ToDictionary(p => p.Id, StringComparer.Ordinal);

    public string ActiveId => active.Current;

    public ILlmProvider Active => Resolve(active.Current);

    public ILlmProvider Resolve(string id) =>
        byId.TryGetValue(id, out var provider)
            ? provider
            : throw new LlmConfigurationException("The active LLM provider is not configured.");
}
