using Zaghlol.Application.Catalog;
using Zaghlol.Application.Sync;

namespace Zaghlol.Application.Llm.Categorise.Feedback;

/// <summary>One Right/Wrong verdict as received (OpenAPI <c>LlmCatFeedbackItem</c>, D-96). A merchant name: as sensitive as the cache key.</summary>
public sealed record SyncLlmCatFeedback(string MerchantNorm, string Verdict, string AiCategory, string UserCategory, string Source);

/// <summary>A <c>right</c> verdict ready to store: the category the AI gave and the user kept.</summary>
public sealed record PreparedConfirmation(string MerchantNorm, string CategoryCode, string Source);

/// <summary>A <c>wrong</c> verdict ready to store; <see cref="UserCategory"/> is a system code or the literal <c>custom</c> (never a custom name).</summary>
public sealed record PreparedCorrection(string MerchantNorm, string AiCategory, string UserCategory, string Source);

/// <summary>The rows to store and what was dropped on the way, per kind of row.</summary>
public sealed record PreparedFeedback(
    IReadOnlyList<PreparedConfirmation> Confirmations,
    IntakeCounts ConfirmationDrops,
    IReadOnlyList<PreparedCorrection> Corrections,
    IntakeCounts CorrectionDrops)
{
    public static PreparedFeedback Empty { get; } = new([], new IntakeCounts(0, 0, 0), [], new IntakeCounts(0, 0, 0));

    public bool IsEmpty => Confirmations.Count == 0 && Corrections.Count == 0;
}

/// <summary>
/// Feedback intake rules (llm-categorise §5, FR-LCAT-22/23). Per item, in order: the merchant name passes the same server filter as
/// <c>POST /v1/categorise</c> (<see cref="CategoriseNameFilter"/> on the <see cref="CatalogText.Normalize"/> key, which is the cache key);
/// the category codes are in the live system set (the user's may also be the literal <c>custom</c>) and agree with the verdict (right:
/// both equal; wrong: they differ); one row per merchant and verdict in the call (the first wins). An item that fails is dropped
/// on its own, counted by kind and never echoed. At most <see cref="MaxItems"/> items are looked at. Pure; no I/O.
/// </summary>
public static class CategoriseFeedbackIntake
{
    /// <summary>The user category of a corrected merchant whose new category is the user's own (its name is never sent).</summary>
    public const string Custom = "custom";

    public const string VerdictRight = "right";
    public const string VerdictWrong = "wrong";

    /// <summary>The per-sync cap (BR-SYNC-03), enforced here as well as by the API.</summary>
    public const int MaxItems = 50;

    public static PreparedFeedback Prepare(IReadOnlyList<SyncLlmCatFeedback> items, IReadOnlySet<string> systemCodes)
    {
        ArgumentNullException.ThrowIfNull(items);
        ArgumentNullException.ThrowIfNull(systemCodes);

        var confirmations = new List<PreparedConfirmation>();
        var corrections = new List<PreparedCorrection>();
        var seenRight = new HashSet<string>(StringComparer.Ordinal);
        var seenWrong = new HashSet<string>(StringComparer.Ordinal);
        int[] right = [0, 0, 0], wrong = [0, 0, 0]; // filtered, invalid code, duplicate

        foreach (var item in items.Take(MaxItems))
        {
            var isRight = item.Verdict == VerdictRight;
            if (!isRight && item.Verdict != VerdictWrong)
            {
                continue; // The API rejects any other verdict; a call that reaches here with one stores nothing.
            }

            var counts = isRight ? right : wrong;
            var key = CatalogText.Normalize(item.MerchantNorm);
            if (!CategoriseNameFilter.IsAcceptable(item.MerchantNorm, key))
            {
                counts[0]++;
            }
            else if (!CodesAgree(item, isRight, systemCodes))
            {
                counts[1]++;
            }
            else if (!(isRight ? seenRight : seenWrong).Add(key))
            {
                counts[2]++;
            }
            else if (isRight)
            {
                confirmations.Add(new PreparedConfirmation(key, item.AiCategory, item.Source));
            }
            else
            {
                corrections.Add(new PreparedCorrection(key, item.AiCategory, item.UserCategory, item.Source));
            }
        }

        return new PreparedFeedback(confirmations, new IntakeCounts(right[0], right[1], right[2]), corrections, new IntakeCounts(wrong[0], wrong[1], wrong[2]));
    }

    private static bool CodesAgree(SyncLlmCatFeedback item, bool isRight, IReadOnlySet<string> systemCodes)
    {
        // The AI's answer is always a system code (never `custom`, which is only ever a user's own category).
        if (item.AiCategory == Custom || !systemCodes.Contains(item.AiCategory))
        {
            return false;
        }

        return isRight
            ? string.Equals(item.UserCategory, item.AiCategory, StringComparison.Ordinal)
            : !string.Equals(item.UserCategory, item.AiCategory, StringComparison.Ordinal)
              && (item.UserCategory == Custom || systemCodes.Contains(item.UserCategory));
    }
}
