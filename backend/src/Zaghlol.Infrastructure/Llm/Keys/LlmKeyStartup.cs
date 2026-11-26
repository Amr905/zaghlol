using System.Security.Cryptography;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Infrastructure.Llm.Keys;

/// <summary>
/// T-333: at start, refuses an LLM key in configuration, then loads every configured provider's key from the active KMS provider's
/// secret store into <see cref="LlmApiKeyStore"/> (skipped when the host registered another <see cref="ILlmApiKeyProvider"/>).
/// Absent key = that provider is paused and the rest of the backend starts; a present but unusable key refuses the start.
/// Logs name the provider id and the source only.
/// </summary>
internal sealed partial class LlmKeyStartup(
    IServiceProvider services,
    LlmRegisteredProviders registered,
    IConfiguration configuration,
    IHostEnvironment environment,
    ILogger<LlmKeyStartup> logger) : IHostedService
{
    public const string LocalNotAllowedMessage = "LLM keys from Kms:Provider = Local are allowed only in the Development and Testing environments.";

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        LlmKeyConfigurationScan.Check(configuration);

        if (services.GetService<ILlmApiKeyProvider>() is not LlmApiKeyStore store || store.IsLoaded)
        {
            return;
        }

        foreach (var provider in registered.Providers)
        {
            if (!LlmKeyFormats.ProviderId().IsMatch(provider.Id))
            {
                throw new LlmKeyConfigurationException("Llm:Providers ids must be 1 to 40 characters a-z, 0-9 and '-', starting with a letter or digit (they name the key file and KV path).");
            }

            _ = LlmKeyFormats.For(provider.Kind);
        }

        var source = SourceOf(services.GetService<KmsSettings>()?.Provider);
        var loaded = new Dictionary<string, LlmSensitive<string>>(StringComparer.Ordinal);
        foreach (var provider in registered.Providers)
        {
            var value = source switch
            {
                LlmKeySource.Local => ReadLocal(provider.Id),
                LlmKeySource.File => ReadFile(provider.Id),
                LlmKeySource.HostSecrets => ReadHostSecrets(provider.Id),
                LlmKeySource.OpenBao => await ReadOpenBaoAsync(provider.Id, cancellationToken).ConfigureAwait(false),
                _ => null,
            };

            if (value is null)
            {
                LogPaused(logger, provider.Id, source);
                continue;
            }

            var key = LlmKeyFormats.Check(value, LlmKeyFormats.For(provider.Kind), out var reason)
                ?? throw Refused(source, provider.Id, reason!);
            loaded[provider.Id] = new LlmSensitive<string>(key);
            LogLoaded(logger, provider.Id, source);
        }

        store.Set(loaded);
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    internal static LlmKeySource SourceOf(string? kmsProvider) => kmsProvider switch
    {
        KmsSettings.LocalProvider => LlmKeySource.Local,
        FileKms.ProviderName => LlmKeySource.File,
        HostSecretsKms.ProviderName => LlmKeySource.HostSecrets,
        OpenBaoKms.ProviderName => LlmKeySource.OpenBao,
        _ => LlmKeySource.None,
    };

    internal static string FileName(string providerId) => "llm_" + providerId + ".secret";

    internal static LlmKeyConfigurationException Refused(LlmKeySource source, string providerId, string reason) =>
        new($"The LLM key of provider '{providerId}' from {Where(source, providerId)} is refused: {reason}.");

    private static string Where(LlmKeySource source, string providerId) => source switch
    {
        LlmKeySource.Local => "Kms:Local:KeyDirectory/" + FileName(providerId),
        LlmKeySource.File => "the File KMS (Kms:File:KeyDirectory/" + FileName(providerId) + ")",
        LlmKeySource.HostSecrets => "HostSecrets (ZAGHLOL_KEYS__llm_" + providerId + ")",
        LlmKeySource.OpenBao => "OpenBao KV (zaghlol/llm/" + providerId + ")",
        _ => "no source",
    };

    private string? ReadLocal(string providerId)
    {
        if (!environment.IsDevelopment() && !environment.IsEnvironment("Testing"))
        {
            throw new LlmKeyConfigurationException(LocalNotAllowedMessage);
        }

        var directory = services.GetService<KmsSettings>()?.LocalKeyDirectory;
        if (string.IsNullOrWhiteSpace(directory))
        {
            return null;
        }

        var path = Path.Combine(directory, FileName(providerId));
        if (!File.Exists(path))
        {
            return null;
        }

        try
        {
            if (new FileInfo(path).Length > LlmKeyFormats.MaxSecretBytes)
            {
                throw Refused(LlmKeySource.Local, providerId, LlmKeyFormats.TooLargeReason);
            }

            var bytes = File.ReadAllBytes(path);
            try
            {
                return Decode(LlmKeySource.Local, providerId, bytes);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(bytes);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            throw Refused(LlmKeySource.Local, providerId, "the file can't be read");
        }
    }

    /// <summary>The T-200 checks: the directory again (canonical, 0700/0500, safe parents), then the file (regular, 0400/0600, owner, size).</summary>
    private string? ReadFile(string providerId)
    {
        var settings = services.GetRequiredService<KmsSettings>();
        if (!OperatingSystem.IsLinux())
        {
            throw new KmsConfigurationException(FileKms.NotLinuxMessage);
        }

        var euid = PosixFiles.EffectiveUid() ?? throw new KmsConfigurationException(FileKms.DirectoryUnreadableMessage);
        var directory = FileKms.CheckDirectory(settings.FileKeyDirectory, euid);
        var path = Path.Combine(directory, FileName(providerId));
        if (PosixFiles.LStat(path) is null)
        {
            return null;
        }

        byte[] buffer;
        int length;
        try
        {
            (buffer, length) = FileKms.ReadChecked(path, euid);
        }
        catch (KmsConfigurationException ex)
        {
            throw Refused(LlmKeySource.File, providerId, ex.Message switch
            {
                FileKms.TooLargeMessage => LlmKeyFormats.TooLargeReason,
                FileKms.EntryMessage => "the file must be a regular file (no symbolic link), mode 0400 or 0600, owned by the process user or root",
                _ => "the file can't be read or changed while it was read",
            });
        }

        try
        {
            return Decode(LlmKeySource.File, providerId, buffer.AsSpan(0, length));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(buffer);
        }
    }

    /// <summary>The T-205 rules: the custody flag, no key in a configuration file, the <c>host-key-v1</c> wrapper (member <c>secret</c>).</summary>
    private string? ReadHostSecrets(string providerId)
    {
        HostSecretsKms.CheckCustody(configuration, environment);
        HostSecretsKms.CheckNoKeysInFiles(configuration, environment);

        var name = "llm_" + providerId;
        var section = configuration.GetSection(HostSecretsKms.SettingsSection);
        if (section[name] is null && (!name.Contains('-', StringComparison.Ordinal) || section[name.Replace('-', '_')] is null))
        {
            return null;
        }

        byte[] text;
        try
        {
            text = HostSecretsKms.ReadValue(section, name, HostSecretsKms.KeyKind.Secret);
        }
        catch (KmsConfigurationException ex)
        {
            throw Refused(LlmKeySource.HostSecrets, providerId, ex.Message switch
            {
                HostSecretsKms.MissingMessage => LlmKeyFormats.EmptyReason,
                HostSecretsKms.DuplicateMessage => "the key is set twice (once with '-' and once with '_')",
                _ => "the value is not the unpadded base64url of {\"zaghlol\":\"host-key-v1\",\"name\":\"llm_<id>\",\"secret\":\"...\"} or is larger than 16 KiB",
            });
        }

        try
        {
            return Decode(LlmKeySource.HostSecrets, providerId, text);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(text);
        }
    }

    /// <summary>KV v2 through the KMS's own AppRole session. Not found, refused by the policy or unreachable = absent (paused).</summary>
    private async Task<string?> ReadOpenBaoAsync(string providerId, CancellationToken cancellationToken)
    {
        if (services.GetService<IKmsBackend>() is not OpenBaoKms openBao)
        {
            return null;
        }

        (OpenBaoKms.KvSecretStatus Status, string? Secret) answer;
        try
        {
            answer = await KmsCall.RunAsync(
                services.GetService<KmsCallPolicy>() ?? new KmsCallPolicy(),
                services.GetService<TimeProvider>() ?? TimeProvider.System,
                "llm_key",
                ct => new ValueTask<(OpenBaoKms.KvSecretStatus, string?)>(openBao.ReadKvSecretAsync("llm/" + providerId, ct)),
                cancellationToken).ConfigureAwait(false);
        }
        catch (KmsUnavailableException)
        {
            LogUnreadable(logger, providerId);
            return null;
        }

        return answer.Status switch
        {
            OpenBaoKms.KvSecretStatus.Found => answer.Secret,
            OpenBaoKms.KvSecretStatus.NotFound => null,
            _ => throw Refused(LlmKeySource.OpenBao, providerId, "its data must be exactly {\"secret\": \"<text>\"}"),
        };
    }

    private static string Decode(LlmKeySource source, string providerId, ReadOnlySpan<byte> utf8) =>
        LlmKeyFormats.Decode(utf8, out var reason) ?? throw Refused(source, providerId, reason!);

    [LoggerMessage(EventId = 1, Level = LogLevel.Information, Message = "LLM key for provider {ProviderId} loaded from {Source}")]
    private static partial void LogLoaded(ILogger logger, string providerId, LlmKeySource source);

    [LoggerMessage(EventId = 2, Level = LogLevel.Warning, Message = "No LLM key for provider {ProviderId} in {Source}: the provider is paused (LLM_SERVICE_PAUSED); the rest of the backend runs")]
    private static partial void LogPaused(ILogger logger, string providerId, LlmKeySource source);

    [LoggerMessage(EventId = 3, Level = LogLevel.Warning, Message = "The LLM key for provider {ProviderId} could not be read from OpenBao KV (unreachable or not allowed by the zaghlol-api policy)")]
    private static partial void LogUnreadable(ILogger logger, string providerId);
}

/// <summary>
/// AC2: an LLM key in configuration (JSON files, environment variables, command line, any other provider) refuses the start. Any
/// setting under <c>Llm</c> with a segment such as <c>ApiKey</c>, <c>Secret</c>, <c>Token</c>, <c>Password</c>, <c>Credentials</c> or
/// <c>ServiceAccount…</c> counts, set or empty. The message names the setting's shape, never its value.
/// </summary>
internal static class LlmKeyConfigurationScan
{
    public const string Message = "An LLM provider key setting (Llm:...:ApiKey, Key, Secret, Token, Password, Credentials or ServiceAccount...) was found in configuration (appsettings*.json, environment variables or the command line); LLM keys come only from the KMS secret store (ask-llm.md §3).";

    private static readonly HashSet<string> Forbidden = new(StringComparer.Ordinal)
    {
        "apikey", "key", "keys", "secret", "secrets", "clientsecret", "token", "accesstoken", "bearer", "bearertoken",
        "credential", "credentials", "password", "privatekey", "authorization",
    };

    // FU-418 (B93-m2): names such as AuthToken, ApiSecret or DbPassword. A plain "key" suffix is not a rule (Llm:Attestation:DevProofKey is T-336's
    // and is refused outside Development and Testing by its own guard).
    private static readonly string[] SecretSuffixes = ["secret", "token", "password", "credential", "credentials"];

    public static void Check(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        foreach (var (path, _) in configuration.GetSection(LlmProviderOptions.SectionName).AsEnumerable())
        {
            var segments = path.Split(ConfigurationPath.KeyDelimiter);
            for (var i = 1; i < segments.Length; i++)
            {
                // Llm:Providers:<id>: the id itself is a name, not a setting.
                if (i == 2 && segments[1].Equals("Providers", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                if (IsKeyName(segments[i]))
                {
                    throw new LlmKeyConfigurationException(Message);
                }
            }
        }
    }

    internal static bool IsKeyName(string segment)
    {
        var normal = new string([.. segment.Where(char.IsAsciiLetterOrDigit).Select(char.ToLowerInvariant)]);
        return Forbidden.Contains(normal) || normal.StartsWith("serviceaccount", StringComparison.Ordinal) || normal.EndsWith("apikey", StringComparison.Ordinal)
            || SecretSuffixes.Any(suffix => normal.EndsWith(suffix, StringComparison.Ordinal));
    }
}
