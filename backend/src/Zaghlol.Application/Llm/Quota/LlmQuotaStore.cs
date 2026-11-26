using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Logging;
using Zaghlol.Domain;

namespace Zaghlol.Application.Llm.Quota;

/// <summary>
/// ask-llm §4.2 / llm-categorise §3 steps 4 and 8. Concurrent requests can overshoot a counter by the in-flight count (bounded by the
/// install burst of 3) because the pre-check and the commit are separate; the commit statement itself never takes a counter past its
/// limit (ask-llm §10 OQ 7, accepted).
/// </summary>
public sealed partial class LlmQuotaStore(
    ILlmQuotaRepository repository,
    ILlmQuotaLimits limits,
    ILlmQuotaTier tier,
    TimeProvider clock,
    ILogger<LlmQuotaStore> logger) : ILlmQuotaStore
{
    private static readonly bool CairoAvailable = CairoMonth.SelfCheck();

    public async Task<LlmQuotaCheck> PreCheckAsync(LlmFeature feature, InstallId install, Guid? account, string requestId, CancellationToken cancellationToken)
    {
        var now = clock.GetUtcNow();
        if (!CairoAvailable)
        {
            LogUnavailable(logger);
            return new LlmQuotaCheck(LlmQuotaCheckKind.Unavailable, 0, 0, 0, now);
        }

        var hash = Hash(requestId);
        var month = CairoMonth.MonthKey(now);
        var resets = CairoMonth.ResetsAt(now);
        var limit = await LimitAsync(feature, install, account, now, cancellationToken).ConfigureAwait(false);
        var rows = await ReadRowsAsync(feature, install, account, month, cancellationToken).ConfigureAwait(false);
        var used = rows.Select(r => r?.Used ?? 0).Max();
        var remaining = Math.Max(0, limit - used);
        if (rows.Any(r => r?.LastRequestHash is { } last && last.AsSpan().SequenceEqual(hash)))
        {
            return new LlmQuotaCheck(LlmQuotaCheckKind.Allowed, limit, used, remaining, resets, IsRetry: true);
        }

        return new LlmQuotaCheck(remaining > 0 ? LlmQuotaCheckKind.Allowed : LlmQuotaCheckKind.Exhausted, limit, used, remaining, resets);
    }

    public async Task<LlmQuotaCommit> CommitAsync(LlmFeature feature, InstallId install, Guid? account, string requestId, int n, CancellationToken cancellationToken)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(n, 1);
        var now = clock.GetUtcNow();
        if (!CairoAvailable)
        {
            LogUnavailable(logger);
            return new LlmQuotaCommit(LlmQuotaCheckKind.Unavailable, 0, 0, false);
        }

        var hash = Hash(requestId);
        var month = CairoMonth.MonthKey(now);
        var limit = await LimitAsync(feature, install, account, now, cancellationToken).ConfigureAwait(false);
        var rows = await ReadRowsAsync(feature, install, account, month, cancellationToken).ConfigureAwait(false);
        var used = rows.Select(r => r?.Used ?? 0).Max();
        if (rows.Any(r => r?.LastRequestHash is { } last && last.AsSpan().SequenceEqual(hash)))
        {
            return new LlmQuotaCommit(LlmQuotaCheckKind.Allowed, 0, Math.Max(0, limit - used), IsRetry: true);
        }

        // Categorise trims to the lower remaining of install and account (a counted n never exceeds it).
        var effective = Math.Min(n, Math.Max(0, limit - used));
        if (effective < 1)
        {
            return new LlmQuotaCommit(LlmQuotaCheckKind.Exhausted, 0, 0, false);
        }

        var applied = false;
        applied |= await repository.CommitAsync(feature, LlmQuotaSubjectKind.Install, install.Value, month, effective, limit, hash, now, cancellationToken).ConfigureAwait(false);
        if (account is { } accountId)
        {
            applied |= await repository.CommitAsync(feature, LlmQuotaSubjectKind.Account, accountId, month, effective, limit, hash, now, cancellationToken).ConfigureAwait(false);
        }

        return applied
            ? new LlmQuotaCommit(LlmQuotaCheckKind.Allowed, effective, Math.Max(0, limit - used - effective), false)
            : new LlmQuotaCommit(LlmQuotaCheckKind.Allowed, 0, Math.Max(0, limit - used), IsRetry: true);
    }

    internal static byte[] Hash(string requestId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(requestId);
        return SHA256.HashData(Encoding.UTF8.GetBytes(requestId));
    }

    private async Task<int> LimitAsync(LlmFeature feature, InstallId install, Guid? account, DateTimeOffset now, CancellationToken cancellationToken)
    {
        var gold = await tier.IsGoldAsync(install, account, now, cancellationToken).ConfigureAwait(false);
        return await limits.LimitAsync(feature, gold, cancellationToken).ConfigureAwait(false);
    }

    private async Task<LlmQuotaRow?[]> ReadRowsAsync(LlmFeature feature, InstallId install, Guid? account, int month, CancellationToken cancellationToken)
    {
        var installRow = await repository.ReadAsync(feature, LlmQuotaSubjectKind.Install, install.Value, month, cancellationToken).ConfigureAwait(false);
        if (account is not { } accountId)
        {
            return [installRow];
        }

        var accountRow = await repository.ReadAsync(feature, LlmQuotaSubjectKind.Account, accountId, month, cancellationToken).ConfigureAwait(false);
        return [installRow, accountRow];
    }

    [LoggerMessage(Level = LogLevel.Error, Message = "LLM quota unavailable: the Africa/Cairo time zone did not resolve; the LLM module is disabled.")]
    private static partial void LogUnavailable(ILogger logger);
}
