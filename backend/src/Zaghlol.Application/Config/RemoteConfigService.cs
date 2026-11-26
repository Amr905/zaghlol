using System.Globalization;

using Zaghlol.Application.Llm;

namespace Zaghlol.Application.Config;

/// <summary>One stored <c>remote_config</c> row. <see cref="Version"/> counts the changes of this key.</summary>
public sealed record RemoteConfigRow(string Key, string Value, long Version, DateTimeOffset UpdatedAt);

/// <summary>One key as the admin API shows it: the effective value, whether it is the default, and the row version (0 when never set).</summary>
public sealed record RemoteConfigState(string Key, string Value, bool IsDefault, long Version, DateTimeOffset UpdatedAt);

/// <summary>Reads and writes <c>remote_config</c> with the admin login (never the app login).</summary>
public interface IRemoteConfigAdminStore
{
    Task<IReadOnlyList<RemoteConfigRow>> ListAsync(CancellationToken cancellationToken);

    /// <summary>
    /// One transaction: upsert the row, increment its <c>version</c> by exactly one, and insert exactly one <c>audit_log</c> row
    /// naming the operator.
    /// </summary>
    Task<RemoteConfigRow> UpsertAsync(string key, string value, Guid operatorId, DateTimeOffset now, CancellationToken cancellationToken);
}

/// <summary>Reads every stored row with the app login (sync block, provider id, later quotas and the spend cap).</summary>
public interface IRemoteConfigReader
{
    Task<IReadOnlyList<RemoteConfigRow>> ListAsync(CancellationToken cancellationToken);
}

/// <summary>The effective values for one request: stored rows over defaults. A stored value that no longer validates falls back to its default.</summary>
public sealed class RemoteConfigSnapshot
{
    private readonly Dictionary<string, string> values;
    private readonly Dictionary<string, long> versions;

    internal RemoteConfigSnapshot(Dictionary<string, string> values, Dictionary<string, long> versions)
    {
        this.values = values;
        this.versions = versions;
    }

    /// <summary>The effective canonical value of a known key.</summary>
    public string Get(string key) =>
        values.TryGetValue(key, out var value) ? value : throw new ArgumentException("Not a config key.", nameof(key));

    public int GetInt(string key) => int.Parse(Get(key), NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture);

    public decimal GetDecimal(string key) => decimal.Parse(Get(key), NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture);

    /// <summary>
    /// The version of the app-visible part: the sum of the row versions of the app-visible keys. Every change of such a key adds
    /// exactly one, so the number rises on every change and never moves for a server-only key; 0 while nothing is set.
    /// </summary>
    public int AppVersion
    {
        get
        {
            var sum = RemoteConfigKeys.All.Where(d => d.SentToApp).Sum(d => versions.GetValueOrDefault(d.Key));
            return (int)Math.Min(sum, int.MaxValue);
        }
    }

    /// <summary>The block the app receives: app-visible keys except the provider names, and the names when both are set.</summary>
    public SyncConfigBlock ToAppBlock()
    {
        var map = RemoteConfigKeys.All
            .Where(d => d.SentToApp && !RemoteConfigKeys.IsProviderName(d.Key))
            .ToDictionary(d => d.Key, d => Get(d.Key), StringComparer.Ordinal);
        var ar = Get(RemoteConfigKeys.LlmProviderNameAr);
        var en = Get(RemoteConfigKeys.LlmProviderNameEn);
        return new SyncConfigBlock(AppVersion, map, ar.Length > 0 && en.Length > 0 ? new ProviderName(ar, en) : null);
    }
}

/// <summary>The <c>llm.providerName</c> of the consent sheet, per language.</summary>
public sealed record ProviderName(string Ar, string En);

/// <summary>The <c>config</c> block of the sync (OpenAPI <c>ConfigBlock</c>).</summary>
public sealed record SyncConfigBlock(int Version, IReadOnlyDictionary<string, string> Values, ProviderName? ProviderName);

/// <summary>Per-request access to the effective config; nothing is cached, so a change applies to the next request.</summary>
public interface IRemoteConfigService
{
    Task<RemoteConfigSnapshot> GetAsync(CancellationToken cancellationToken);
}

public sealed class RemoteConfigService(IRemoteConfigReader reader) : IRemoteConfigService
{
    public async Task<RemoteConfigSnapshot> GetAsync(CancellationToken cancellationToken)
    {
        var rows = await reader.ListAsync(cancellationToken);
        return Build(rows);
    }

    internal static RemoteConfigSnapshot Build(IEnumerable<RemoteConfigRow> rows)
    {
        var values = RemoteConfigKeys.All.ToDictionary(d => d.Key, d => d.Default, StringComparer.Ordinal);
        var versions = new Dictionary<string, long>(StringComparer.Ordinal);
        foreach (var row in rows)
        {
            if (RemoteConfigKeys.Find(row.Key) is not { } definition)
            {
                continue;
            }

            versions[row.Key] = row.Version;
            if (RemoteConfigKeys.TryCanonicalize(definition, row.Value, out var canonical))
            {
                values[row.Key] = canonical;
            }
        }

        return new RemoteConfigSnapshot(values, versions);
    }
}

/// <summary>What a config change did.</summary>
public enum ConfigSetStatus
{
    Ok,
    UnknownKey,
    InvalidValue,
}

public sealed record ConfigSetResult(ConfigSetStatus Status, RemoteConfigState? State = null);

/// <summary>The admin use cases for <c>/admin/v1/config</c>.</summary>
public sealed class RemoteConfigAdminService(IRemoteConfigAdminStore store, TimeProvider clock, IKnownLlmProviderIds? knownProviders = null)
{
    public async Task<IReadOnlyList<RemoteConfigState>> ListAsync(CancellationToken cancellationToken)
    {
        var rows = (await store.ListAsync(cancellationToken)).ToDictionary(r => r.Key, StringComparer.Ordinal);
        return RemoteConfigKeys.All.Select(d => ToState(d, rows.GetValueOrDefault(d.Key))).ToList();
    }

    /// <summary>The key's state, or <c>null</c> for a key outside the closed set.</summary>
    public async Task<RemoteConfigState?> GetAsync(string key, CancellationToken cancellationToken)
    {
        if (RemoteConfigKeys.Find(key) is not { } definition)
        {
            return null;
        }

        var row = (await store.ListAsync(cancellationToken)).FirstOrDefault(r => r.Key == key);
        return ToState(definition, row);
    }

    public async Task<ConfigSetResult> SetAsync(string key, string? value, Guid operatorId, CancellationToken cancellationToken)
    {
        if (RemoteConfigKeys.Find(key) is not { } definition)
        {
            return new ConfigSetResult(ConfigSetStatus.UnknownKey);
        }

        if (!RemoteConfigKeys.TryCanonicalize(definition, value, out var canonical))
        {
            return new ConfigSetResult(ConfigSetStatus.InvalidValue);
        }

        // FU-411: a provider id the host has no adapter for would make every LLM call fail closed with no hint.
        if (key == RemoteConfigKeys.LlmProvider && canonical.Length > 0 && knownProviders is { } known && !known.IsKnown(canonical))
        {
            return new ConfigSetResult(ConfigSetStatus.InvalidValue);
        }

        var row = await store.UpsertAsync(key, canonical, operatorId, clock.GetUtcNow(), cancellationToken);
        return new ConfigSetResult(ConfigSetStatus.Ok, ToState(definition, row));
    }

    private static RemoteConfigState ToState(ConfigKeyDefinition definition, RemoteConfigRow? row) =>
        row is not null && RemoteConfigKeys.TryCanonicalize(definition, row.Value, out var canonical)
            ? new RemoteConfigState(definition.Key, canonical, false, row.Version, row.UpdatedAt)
            : new RemoteConfigState(definition.Key, definition.Default, true, row?.Version ?? 0, row?.UpdatedAt ?? DateTimeOffset.UnixEpoch);
}
