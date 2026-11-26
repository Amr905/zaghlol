using System.Collections.Frozen;
using Zaghlol.Application.Llm;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.Llm.Keys;

/// <summary>Where the LLM provider keys come from: the active KMS provider's secret store (<c>Kms:Provider</c>, T-333).</summary>
public enum LlmKeySource
{
    /// <summary>No KMS provider configured (or one without a secret store): every provider is paused.</summary>
    None,

    /// <summary><c>&lt;Kms:Local:KeyDirectory&gt;/llm_&lt;id&gt;.secret</c>, Development and Testing only.</summary>
    Local,

    /// <summary><c>&lt;Kms:File:KeyDirectory&gt;/llm_&lt;id&gt;.secret</c> behind the T-200 owner and mode checks.</summary>
    File,

    /// <summary><c>ZAGHLOL_KEYS__llm_&lt;id&gt;</c>, the T-205 <c>host-key-v1</c> wrapper with a <c>secret</c> member.</summary>
    HostSecrets,

    /// <summary>OpenBao KV v2 <c>zaghlol/llm/&lt;id&gt;</c>, member <c>secret</c>.</summary>
    OpenBao,
}

/// <summary>An LLM provider key is present but unusable; the process refuses to start. The message names the source and the provider id, never the value.</summary>
public sealed class LlmKeyConfigurationException : SafeException
{
    public const string DefaultMessage = "An LLM provider key is unusable.";

    public LlmKeyConfigurationException()
        : base(DefaultMessage)
    {
    }

    public LlmKeyConfigurationException(string message)
        : base(message)
    {
    }

    public LlmKeyConfigurationException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>
/// The provider keys, loaded once at start by <see cref="LlmKeyStartup"/> (T-333) and kept as <see cref="LlmSensitive{T}"/>: printed
/// or serialised they read <c>***</c>. A provider without a key is paused (<see cref="LlmServicePausedException"/>); so is every
/// provider before the load ran. Rotation is a new value in the store plus a restart.
/// </summary>
public sealed class LlmApiKeyStore : ILlmApiKeyProvider
{
    private FrozenDictionary<string, LlmSensitive<string>> keys = FrozenDictionary<string, LlmSensitive<string>>.Empty;
    private int loaded;

    /// <summary>True once <see cref="LlmKeyStartup"/> has set the keys.</summary>
    public bool IsLoaded => Volatile.Read(ref loaded) == 1;

    public bool HasKey(string providerId) => providerId is not null && Volatile.Read(ref keys).ContainsKey(providerId);

    public ValueTask<LlmSensitive<string>> GetKeyAsync(string providerId, CancellationToken cancellationToken) =>
        providerId is not null && Volatile.Read(ref keys).TryGetValue(providerId, out var key)
            ? ValueTask.FromResult(key)
            : ValueTask.FromException<LlmSensitive<string>>(new LlmServicePausedException());

    public override string ToString() => nameof(LlmApiKeyStore);

    /// <summary>Sets the keys once; a second call is refused (no reload at run time: rotation = restart).</summary>
    internal void Set(IReadOnlyDictionary<string, LlmSensitive<string>> values)
    {
        ArgumentNullException.ThrowIfNull(values);
        if (Interlocked.CompareExchange(ref loaded, 1, 0) != 0)
        {
            throw new InvalidOperationException("The LLM keys are loaded once, at start.");
        }

        Volatile.Write(ref keys, values.ToFrozenDictionary(StringComparer.Ordinal));
    }
}
