namespace Zaghlol.Application.Flags;

/// <summary>
/// The feature flags the backend knows (FR-BE-05). The set is closed: an admin call for any other key is <c>404</c>, so a typo
/// can't create a flag and the metric tag stays a fixed value set. Adding a flag is a code change.
/// </summary>
public static class FlagKeys
{
    public const string Zakah = "zakah";
    public const string SmartRoi = "smart_roi";
    public const string RoiNamedProducts = "roi_named_products";

    /// <summary>Master flag of the online helper (FR-LLM-60); OFF by default.</summary>
    public const string AskLlm = "ask_llm";

    /// <summary>Investment illustrations in the online helper; needs <see cref="AskLlm"/>; OFF by default.</summary>
    public const string AskLlmInvest = "ask_llm_invest";

    /// <summary>Automatic categories for unknown merchants (FR-LCAT-42); OFF by default.</summary>
    public const string LlmCategorise = "llm_categorise";

    /// <summary>The OpenAPI <c>FlagKey</c> pattern, character for character (a contract test compares them).</summary>
    public const string Pattern = "^[a-z][a-z0-9_]{1,63}$";

    public static IReadOnlyList<string> Known { get; } = [Zakah, SmartRoi, RoiNamedProducts, AskLlm, AskLlmInvest, LlmCategorise];

    public static bool IsKnown(string? key) => key is not null && Known.Contains(key, StringComparer.Ordinal);

    /// <summary>True when <paramref name="key"/> has the shape of a flag key (ASCII only; the regex alone would allow a trailing newline).</summary>
    public static bool HasValidShape(string? key) =>
        key is { Length: >= 2 and <= 64 }
        && key[0] is >= 'a' and <= 'z'
        && key.All(c => c is (>= 'a' and <= 'z') or (>= '0' and <= '9') or '_');
}
