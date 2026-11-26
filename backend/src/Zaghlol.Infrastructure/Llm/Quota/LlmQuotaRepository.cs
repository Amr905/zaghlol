using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Quota;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Llm.Quota;

internal sealed class LlmQuotaRepository([FromKeyedServices(DatabaseRole.App)] NpgsqlDataSource source) : ILlmQuotaRepository
{
    private const string ReadSql = """
        SELECT used, last_request_hash, updated_at FROM zaghlol.llm_quota_counters
        WHERE feature = @f AND subject_kind = @k AND subject_id = @s AND month_key = @m
        """;

    // One statement per subject. LEAST caps the row at the limit; the WHERE makes a same-request-id twin inside the retry window a no-op; an older match is a replay and counts (B92-M1).
    internal const string CommitSql = """
        INSERT INTO zaghlol.llm_quota_counters AS c (feature, subject_kind, subject_id, month_key, used, last_request_hash, updated_at)
        VALUES (@f, @k, @s, @m, LEAST(@n, @limit), @h, @now)
        ON CONFLICT (feature, subject_kind, subject_id, month_key) DO UPDATE
          SET used = c.used + LEAST(@n, @limit - c.used), last_request_hash = @h, updated_at = @now
          WHERE c.used < @limit AND (c.last_request_hash IS DISTINCT FROM @h OR c.updated_at <= @cutoff)
        """;

    public async Task<LlmQuotaRow?> ReadAsync(LlmFeature feature, LlmQuotaSubjectKind kind, Guid subject, int monthKey, CancellationToken cancellationToken)
    {
        await using var command = source.CreateCommand(ReadSql);
        AddKey(command, feature, kind, subject, monthKey);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
        return await reader.ReadAsync(cancellationToken).ConfigureAwait(false)
            ? new LlmQuotaRow(reader.GetInt32(0), reader.IsDBNull(1) ? null : (byte[])reader[1], reader.GetFieldValue<DateTimeOffset>(2))
            : null;
    }

    public async Task<bool> CommitAsync(LlmFeature feature, LlmQuotaSubjectKind kind, Guid subject, int monthKey, int n, int limit, byte[] requestHash, DateTimeOffset now, DateTimeOffset retryCutoff, CancellationToken cancellationToken)
    {
        await using var command = source.CreateCommand(CommitSql);
        AddKey(command, feature, kind, subject, monthKey);
        command.Parameters.Add(new("n", NpgsqlDbType.Integer) { Value = n });
        command.Parameters.Add(new("limit", NpgsqlDbType.Integer) { Value = limit });
        command.Parameters.Add(new("h", NpgsqlDbType.Bytea) { Value = requestHash });
        command.Parameters.Add(new("now", NpgsqlDbType.TimestampTz) { Value = now.ToUniversalTime() });
        command.Parameters.Add(new("cutoff", NpgsqlDbType.TimestampTz) { Value = retryCutoff.ToUniversalTime() });
        return await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false) > 0;
    }

    internal static string FeatureText(LlmFeature feature) => feature == LlmFeature.Ask ? "ask" : "cat";

    private static void AddKey(NpgsqlCommand command, LlmFeature feature, LlmQuotaSubjectKind kind, Guid subject, int monthKey)
    {
        command.Parameters.Add(new("f", NpgsqlDbType.Text) { Value = FeatureText(feature) });
        command.Parameters.Add(new("k", NpgsqlDbType.Text) { Value = kind == LlmQuotaSubjectKind.Install ? "install" : "account" });
        command.Parameters.Add(new("s", NpgsqlDbType.Uuid) { Value = subject });
        command.Parameters.Add(new("m", NpgsqlDbType.Integer) { Value = monthKey });
    }
}

/// <summary>
/// Limits through <see cref="Zaghlol.Application.Config.IRemoteConfigService"/>, which canonicalises and range-checks every stored value
/// (B92-m4: one key catalogue, not a second parse); nothing is cached, so a change applies to the next request.
/// </summary>
internal sealed class RemoteConfigQuotaLimits(Zaghlol.Application.Config.IRemoteConfigService config) : ILlmQuotaLimits
{
    public async Task<int> LimitAsync(LlmFeature feature, bool gold, CancellationToken cancellationToken) =>
        (await config.GetAsync(cancellationToken).ConfigureAwait(false)).GetInt(LlmQuotaDefaults.Key(feature, gold));
}

/// <summary>Gold limit only for an entitling seat: the same rules that sign the entitlement, never a client claim (CLAUDE.md 2a).</summary>
internal sealed class EntitlementQuotaTier(Zaghlol.Application.Entitlements.IEntitlementStore store) : ILlmQuotaTier
{
    public async Task<bool> IsGoldAsync(Zaghlol.Domain.InstallId install, Guid? account, DateTimeOffset now, CancellationToken cancellationToken)
    {
        var facts = await store.ReadFactsAsync(install, now, cancellationToken).ConfigureAwait(false);
        var claims = Zaghlol.Application.Entitlements.EntitlementRules.Build(install, facts, account, now);
        return claims.Status is "active" or "grace";
    }
}

public static class LlmQuotaServiceCollectionExtensions
{
    /// <summary>
    /// The quota store (T-335). Call after <c>AddZaghlolDatabase</c> with the App role and <c>AddZaghlolEntitlements</c>.
    /// </summary>
    public static IServiceCollection AddZaghlolLlmQuota(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);
        services.TryAddSingleton(TimeProvider.System);
        services.AddSingleton<ILlmQuotaRepository, LlmQuotaRepository>();
        services.AddSingleton<ILlmQuotaLimits, RemoteConfigQuotaLimits>();
        services.AddSingleton<ILlmQuotaTier, EntitlementQuotaTier>();
        services.AddSingleton<ILlmQuotaStore, LlmQuotaStore>();
        return services;
    }
}
