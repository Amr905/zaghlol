namespace Zaghlol.Application.Llm.Categorise;

/// <summary>One cached answer (llm-categorise §4): the category code and the model's confidence.</summary>
public sealed record CachedAnswer(string Category, int Confidence);

/// <summary>One answer to store. <see cref="Key"/> is the normalised merchant name; the row has no install, account, IP or app version.</summary>
public sealed record CacheWrite(string Key, string Category, int Confidence, string ProviderId, string PromptVersion);

/// <summary>
/// The shared answer cache <c>llm_cat_answer_cache</c> (FR-LCAT-12; one row per merchant_norm, 90 days). The only place a merchant name is stored.
/// The implementation never lets a database error's text out (a PostgreSQL detail can quote a row): a failure is a miss or a skipped write.
/// </summary>
public interface ICategoriseAnswerCache
{
    /// <summary>The unexpired answers for <paramref name="keys"/>; each returned row gets <c>hits + 1</c>.</summary>
    Task<IReadOnlyDictionary<string, CachedAnswer>> GetAsync(IReadOnlyList<string> keys, DateTimeOffset now, CancellationToken cancellationToken);

    /// <summary>Upserts the answers (expiry <see cref="CategoriseCacheDefaults.Lifetime"/> after <paramref name="now"/>).</summary>
    Task PutAsync(IReadOnlyList<CacheWrite> rows, DateTimeOffset now, CancellationToken cancellationToken);
}

public static class CategoriseCacheDefaults
{
    public static readonly TimeSpan Lifetime = TimeSpan.FromDays(90);
}
