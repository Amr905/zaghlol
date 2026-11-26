using Zaghlol.Domain;

namespace Zaghlol.Application.Llm.Quota;

public enum LlmQuotaCheckKind
{
    /// <summary>Room left, or a retry of the request that already counted.</summary>
    Allowed,

    /// <summary>The install or the account counter is at its limit and this is not a retry.</summary>
    Exhausted,

    /// <summary>The Cairo time zone is not available: the LLM module is disabled (<c>LLM_SERVICE_PAUSED</c>).</summary>
    Unavailable,
}

/// <summary><c>Used</c> and <c>Remaining</c> are those of the more used of the two counters (the one that decides).</summary>
public sealed record LlmQuotaCheck(LlmQuotaCheckKind Kind, int Limit, int Used, int Remaining, DateTimeOffset ResetsAt, bool IsRetry = false);

/// <summary><c>Applied</c> is how many were added (0 for a retry or at the limit); <c>Remaining</c> is what is left after it.</summary>
public sealed record LlmQuotaCommit(LlmQuotaCheckKind Kind, int Applied, int Remaining, bool IsRetry);

/// <summary>
/// The per-month LLM quota (ask-llm §4.2, llm-categorise §3). The caller has already validated any account token; the account
/// counter is used only when <paramref name="account"/> is a validated account of this install.
/// </summary>
public interface ILlmQuotaStore
{
    /// <summary>The state before the provider call. A retry (same <paramref name="requestId"/>) passes even at the limit.</summary>
    Task<LlmQuotaCheck> PreCheckAsync(LlmFeature feature, InstallId install, Guid? account, string requestId, CancellationToken cancellationToken);

    /// <summary>
    /// Adds <paramref name="n"/> (trimmed to the lower remaining of install and account) once per <paramref name="requestId"/>.
    /// </summary>
    Task<LlmQuotaCommit> CommitAsync(LlmFeature feature, InstallId install, Guid? account, string requestId, int n, CancellationToken cancellationToken);
}

/// <summary>The month limit for a feature and tier (remote config with the PO defaults).</summary>
public interface ILlmQuotaLimits
{
    Task<int> LimitAsync(LlmFeature feature, bool gold, CancellationToken cancellationToken);
}

/// <summary>Whether the install gets the Gold limit: it holds an entitling Gold seat (an account-linked one only with <paramref name="account"/>).</summary>
public interface ILlmQuotaTier
{
    Task<bool> IsGoldAsync(InstallId install, Guid? account, DateTimeOffset now, CancellationToken cancellationToken);
}

public enum LlmQuotaSubjectKind
{
    Install,
    Account,
}

/// <summary>One counter row as read: <c>LastRequestHash</c> is SHA-256 of the last request id that counted.</summary>
public sealed record LlmQuotaRow(int Used, byte[]? LastRequestHash);

/// <summary>The counters table on the App login. Raw SQL; no row can hold question text.</summary>
public interface ILlmQuotaRepository
{
    Task<LlmQuotaRow?> ReadAsync(LlmFeature feature, LlmQuotaSubjectKind kind, Guid subject, int monthKey, CancellationToken cancellationToken);

    /// <summary>
    /// The single commit statement (insert-on-conflict-update). Returns true when it changed the row; false when the subject is at its
    /// limit or this request hash already counted.
    /// </summary>
    Task<bool> CommitAsync(LlmFeature feature, LlmQuotaSubjectKind kind, Guid subject, int monthKey, int n, int limit, byte[] requestHash, DateTimeOffset now, CancellationToken cancellationToken);
}

public static class LlmQuotaDefaults
{
    public const int AskFree = 5;
    public const int AskGold = 50;
    public const int CatFree = 15;
    public const int CatGold = 150;

    public static string Key(LlmFeature feature, bool gold) => (feature, gold) switch
    {
        (LlmFeature.Ask, false) => "ask.quota_free",
        (LlmFeature.Ask, true) => "ask.quota_gold",
        (LlmFeature.Categorise, false) => "cat.quota_free",
        _ => "cat.quota_gold",
    };

    public static int Default(LlmFeature feature, bool gold) => (feature, gold) switch
    {
        (LlmFeature.Ask, false) => AskFree,
        (LlmFeature.Ask, true) => AskGold,
        (LlmFeature.Categorise, false) => CatFree,
        _ => CatGold,
    };
}
