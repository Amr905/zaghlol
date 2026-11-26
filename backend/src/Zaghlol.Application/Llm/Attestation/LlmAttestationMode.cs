using Zaghlol.Domain;

namespace Zaghlol.Application.Llm.Attestation;

/// <summary>How the LLM endpoints treat device attestation (ask-llm.md §5 stage table, T-336).</summary>
public enum LlmAttestationMode
{
    /// <summary>Production behaviour: a missing or invalid proof is <c>422 DEVICE_ATTESTATION_FAILED</c>.</summary>
    Enforce,

    /// <summary>Staging only: real proofs are verified and failures counted by reason, but nothing is refused.</summary>
    ReportOnly,

    /// <summary>Development and Testing only: only <c>{"type":"dev","proof":HMAC(testKey, bodyHash)}</c> passes.</summary>
    Fake,
}

/// <summary>
/// The resolved attestation mode of this process and, in <see cref="LlmAttestationMode.Fake"/> only, the dev proof key. Built once
/// at startup from <c>Llm:Attestation:*</c> by <see cref="Resolve"/>; nothing else (no remote config, flag or header) can change it.
/// </summary>
public sealed class LlmAttestationSettings
{
    public const string Section = "Llm:Attestation";
    public const string ModeKey = Section + ":Mode";
    public const string DevProofKeyKey = Section + ":DevProofKey";
    public const int MinDevProofKeyBytes = 32;

    private readonly byte[]? devProofKey;

    private LlmAttestationSettings(LlmAttestationMode mode, byte[]? devProofKey)
    {
        Mode = mode;
        this.devProofKey = devProofKey;
    }

    public LlmAttestationMode Mode { get; }

    /// <summary>True only in <see cref="LlmAttestationMode.Fake"/>, where the key is required.</summary>
    public bool HasDevProofKey => devProofKey is not null;

    /// <summary>
    /// The mode guard. <paramref name="environmentName"/> is the host environment. Production is always
    /// <see cref="LlmAttestationMode.Enforce"/>; <see cref="LlmAttestationMode.Fake"/> outside Development/Testing,
    /// <see cref="LlmAttestationMode.ReportOnly"/> outside Staging, an unknown mode or a dev key outside Development/Testing throw.
    /// Messages name the key, never a value.
    /// </summary>
    public static LlmAttestationSettings Resolve(string? configuredMode, string? devProofKeyBase64, string environmentName)
    {
        ArgumentNullException.ThrowIfNull(environmentName);
        var relaxed = Is(environmentName, "Development") || Is(environmentName, "Testing");
        var staging = Is(environmentName, "Staging");
        var hasKey = !string.IsNullOrWhiteSpace(devProofKeyBase64);

        var mode = configuredMode?.Trim() switch
        {
            null or "" => LlmAttestationMode.Enforce,
            "Enforce" => LlmAttestationMode.Enforce,
            "ReportOnly" => LlmAttestationMode.ReportOnly,
            "Fake" => LlmAttestationMode.Fake,
            _ => throw new LlmAttestationConfigurationException($"{ModeKey} must be Enforce, ReportOnly or Fake."),
        };

        if (mode == LlmAttestationMode.Fake && !relaxed)
        {
            throw new LlmAttestationConfigurationException($"{ModeKey} Fake is allowed only in Development and Testing.");
        }

        if (mode == LlmAttestationMode.ReportOnly && !staging)
        {
            throw new LlmAttestationConfigurationException($"{ModeKey} ReportOnly is allowed only in Staging.");
        }

        if (hasKey && !relaxed)
        {
            throw new LlmAttestationConfigurationException($"{DevProofKeyKey} is allowed only in Development and Testing.");
        }

        // Defence in depth: whatever passed above, Production enforces and holds no dev key.
        if (Is(environmentName, "Production"))
        {
            return new LlmAttestationSettings(LlmAttestationMode.Enforce, null);
        }

        if (mode != LlmAttestationMode.Fake)
        {
            return new LlmAttestationSettings(mode, null);
        }

        if (!hasKey)
        {
            throw new LlmAttestationConfigurationException($"{ModeKey} Fake needs {DevProofKeyKey}.");
        }

        byte[] key;
        try
        {
            key = Convert.FromBase64String(devProofKeyBase64!.Trim());
        }
        catch (FormatException e)
        {
            throw new LlmAttestationConfigurationException($"{DevProofKeyKey} must be base64.", e);
        }

        if (key.Length < MinDevProofKeyBytes)
        {
            throw new LlmAttestationConfigurationException($"{DevProofKeyKey} must hold at least {MinDevProofKeyBytes} bytes.");
        }

        return new LlmAttestationSettings(mode, key);
    }

    /// <summary>A copy of the dev key, or <c>null</c> outside <see cref="LlmAttestationMode.Fake"/>.</summary>
    internal byte[]? DevProofKey() => devProofKey is null ? null : (byte[])devProofKey.Clone();

    public override string ToString() => $"LlmAttestationSettings({Mode})";

    private static bool Is(string environmentName, string name) => string.Equals(environmentName, name, StringComparison.OrdinalIgnoreCase);
}

/// <summary>Invalid <c>Llm:Attestation</c> configuration: stops the host.</summary>
public sealed class LlmAttestationConfigurationException : SafeException
{
    public LlmAttestationConfigurationException()
        : base("LLM attestation is not configured correctly.")
    {
    }

    public LlmAttestationConfigurationException(string message)
        : base(message)
    {
    }

    public LlmAttestationConfigurationException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
