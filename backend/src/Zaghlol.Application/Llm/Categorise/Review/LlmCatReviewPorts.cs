using System.Diagnostics.CodeAnalysis;

namespace Zaghlol.Application.Llm.Categorise.Review;

/// <summary>What an operator can do with a group of corrections (llm-categorise §6).</summary>
public enum CorrectionAction
{
    Promote,
    Reject,
    PromptIssue,
}

/// <summary>What an operator can do with an AI-confirmed merchant. Never automatic.</summary>
public enum ConfirmedAction
{
    Promote,
    Reject,
}

/// <summary>Wire words and parsing of the review enums (exact, case-sensitive; anything else is not a value).</summary>
public static class LlmCatReviewWire
{
    public const string Custom = "custom";
    public const int MaxLimit = 100;
    public const int DefaultLimit = 50;
    public const int MaxKeyLength = 64;
    public const int MinKeyLength = 2;

    /// <summary>The stored statuses of a correction, as the query filter and the answer name them.</summary>
    public static IReadOnlyList<string> CorrectionStatuses { get; } = ["open", "promoted", "rejected", "prompt_issue"];

    public static bool TryParse(string? text, out CorrectionAction action)
    {
        switch (text)
        {
            case "promote":
                action = CorrectionAction.Promote;
                return true;
            case "reject":
                action = CorrectionAction.Reject;
                return true;
            case "prompt_issue":
                action = CorrectionAction.PromptIssue;
                return true;
            default:
                action = default;
                return false;
        }
    }

    public static bool TryParse(string? text, out ConfirmedAction action)
    {
        switch (text)
        {
            case "promote":
                action = ConfirmedAction.Promote;
                return true;
            case "reject":
                action = ConfirmedAction.Reject;
                return true;
            default:
                action = default;
                return false;
        }
    }

    public static string Wire(CorrectionAction action) => action switch
    {
        CorrectionAction.Promote => "promoted",
        CorrectionAction.Reject => "rejected",
        _ => "prompt_issue",
    };

    public static string Wire(ConfirmedAction action) => action == ConfirmedAction.Promote ? "promoted" : "rejected";

    /// <summary>The merchant key of a body: 2..64 characters (what the intake stores), no control characters.</summary>
    public static bool IsValidMerchant([NotNullWhen(true)] string? merchantNorm) =>
        merchantNorm is { Length: >= MinKeyLength and <= MaxKeyLength } && merchantNorm.All(c => !char.IsControl(c));

    /// <summary>The page size of a query body: absent (the default) or 1..<see cref="MaxLimit"/>.</summary>
    public static bool IsPage(int? limit) => limit is null or (>= 1 and <= MaxLimit);

    /// <summary>The cursor is the decimal offset the previous page returned (never negative, bounded).</summary>
    public static bool TryParseCursor(string? cursor, out int offset)
    {
        offset = 0;
        return cursor is null
            || (cursor.Length is >= 1 and <= 9 && cursor.All(char.IsAsciiDigit) && int.TryParse(cursor, out offset));
    }
}

/// <summary>One group of corrections: counts and days only, never an install row or a hash.</summary>
public sealed record CorrectionGroupView(
    string MerchantNorm,
    string AiCategory,
    string UserCategory,
    int Votes,
    DateOnly FirstSeen,
    DateOnly LastSeen,
    string Status);

/// <summary>One AI-confirmed merchant and category.</summary>
public sealed record ConfirmedGroupView(string MerchantNorm, string Category, int Votes, DateOnly FirstSeen, DateOnly LastSeen);

public sealed record LlmCatPage<T>(IReadOnlyList<T> Items, string? NextCursor);

public enum LlmCatOutcome
{
    Ok,

    /// <summary>No group has the key.</summary>
    NotFound,

    /// <summary>Already decided, not (or no longer) confirmed enough, or the draft catalog refuses the change (409 ADMIN_CONFLICT).</summary>
    Conflict,
}

/// <param name="Rows">Rows whose status moved.</param>
/// <param name="MerchantId">The draft merchant a promote attached the name to.</param>
public sealed record LlmCatDecision(LlmCatOutcome Outcome, int Rows = 0, int? MerchantId = null);

/// <summary>
/// The operator side of the AI-category review on the Admin login. Resolutions run under the same per-merchant advisory lock as
/// the feedback intake, change only the review columns, edit only the <b>draft</b> catalog (never publish) and leave exactly one
/// audit row in their own transaction.
/// </summary>
public interface ILlmCatReviewStore
{
    Task<LlmCatPage<CorrectionGroupView>> QueryCorrectionsAsync(string? status, int limit, int offset, CancellationToken cancellationToken);

    Task<LlmCatDecision> ResolveCorrectionAsync(
        Guid operatorId,
        string merchantNorm,
        string aiCategory,
        string userCategory,
        CorrectionAction action,
        CancellationToken cancellationToken);

    /// <summary>Merchants with at least <paramref name="confirmN"/> distinct installs agreeing on a category and no open correction.</summary>
    Task<LlmCatPage<ConfirmedGroupView>> QueryConfirmedAsync(int confirmN, int limit, int offset, CancellationToken cancellationToken);

    Task<LlmCatDecision> ResolveConfirmedAsync(
        Guid operatorId,
        string merchantNorm,
        string category,
        ConfirmedAction action,
        int confirmN,
        CancellationToken cancellationToken);
}
