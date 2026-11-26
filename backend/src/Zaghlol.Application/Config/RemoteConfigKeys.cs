using System.Globalization;
using System.Text.RegularExpressions;

namespace Zaghlol.Application.Config;

/// <summary>How a <c>remote_config</c> value is typed. Every value is stored and sent as a canonical string (OpenAPI <c>ConfigBlock</c>).</summary>
public enum ConfigValueKind
{
    /// <summary>A whole number, canonical <c>-?[0-9]+</c>.</summary>
    WholeNumber,

    /// <summary>A non-negative decimal with at most two fraction digits, canonical <c>0.00</c> (never a JSON number, never a double).</summary>
    Amount,

    /// <summary>A short text matching the key's pattern.</summary>
    Text,
}

/// <summary>One member of the closed key set (ask-llm.md section 4.5; llm-categorise.md sections 3 and 6).</summary>
/// <param name="Default">The canonical value used when no row exists (or the stored row is invalid).</param>
/// <param name="SentToApp"><c>true</c> when the key is part of the signed <c>config</c> block of the sync; <c>false</c> for server-only keys.</param>
public sealed record ConfigKeyDefinition(
    string Key,
    ConfigValueKind Kind,
    string Default,
    bool SentToApp,
    decimal Min = 0,
    decimal Max = 0,
    IReadOnlyList<int>? Allowed = null,
    string? Pattern = null);

/// <summary>
/// The closed, typed, range-checked <c>remote_config</c> key set, like <c>FlagKeys</c>: an admin call for any other key is
/// <c>404</c>, a value of the wrong type or outside its range is <c>400</c>. Adding a key is a code change.
/// </summary>
public static partial class RemoteConfigKeys
{
    public const string LlmProvider = "llm.provider";
    public const string LlmSpendCapUsd = "llm.spend_cap_usd";
    public const string LlmProviderNameAr = "llm.provider_name.ar";
    public const string LlmProviderNameEn = "llm.provider_name.en";

    public const string AskQuotaFree = "ask.quota_free";
    public const string AskQuotaGold = "ask.quota_gold";
    public const string AskS1Pct = "ask.s1_pct";
    public const string AskS4SharePct = "ask.s4_share_pct";
    public const string AskS4SavingPct = "ask.s4_saving_pct";
    public const string AskCdExampleRateBp = "ask.cd_example_rate_bp";
    public const string AskInvestMinEgp = "ask.invest_min_egp";
    public const string AskInvestGoldMinCg = "ask.invest_gold_min_cg";
    public const string AskInvestGoldKarat = "ask.invest_gold_karat";

    public const string CatBatchMax = "cat.batch_max";
    public const string CatMinConfidence = "cat.min_confidence";
    public const string CatCacheMinConfidence = "cat.cache_min_confidence";
    public const string CatConfirmN = "cat.confirm_n";
    public const string CatQuotaFree = "cat.quota_free";
    public const string CatQuotaGold = "cat.quota_gold";

    /// <summary>The OpenAPI <c>ConfigKey</c> pattern, character for character (a contract test compares them).</summary>
    public const string Pattern = "^[a-z][a-z0-9_.]{1,63}$";

    /// <summary>Provider ids and display names carry no <c>@</c>, so the audit CHECKs can never reject a value.</summary>
    public const string ProviderIdPattern = "^[a-z0-9][a-z0-9-]{1,31}$";

    public const string ProviderNamePattern = @"^[\p{L}\p{N} ._-]{1,64}$";

    public static IReadOnlyList<ConfigKeyDefinition> All { get; } =
    [
        new(LlmProvider, ConfigValueKind.Text, string.Empty, false, Pattern: ProviderIdPattern),
        new(LlmSpendCapUsd, ConfigValueKind.Amount, "10.00", false, 0, 100000),
        new(LlmProviderNameAr, ConfigValueKind.Text, string.Empty, true, Pattern: ProviderNamePattern),
        new(LlmProviderNameEn, ConfigValueKind.Text, string.Empty, true, Pattern: ProviderNamePattern),
        new(AskQuotaFree, ConfigValueKind.WholeNumber, "5", true, 0, 100000),
        new(AskQuotaGold, ConfigValueKind.WholeNumber, "50", true, 0, 100000),
        new(AskS1Pct, ConfigValueKind.WholeNumber, "15", true, 1, 1000),
        new(AskS4SharePct, ConfigValueKind.WholeNumber, "20", true, 1, 100),
        new(AskS4SavingPct, ConfigValueKind.WholeNumber, "25", true, 1, 100),
        new(AskCdExampleRateBp, ConfigValueKind.WholeNumber, "2000", true, 0, 10000),
        new(AskInvestMinEgp, ConfigValueKind.Amount, "100.00", true, 0, 1000000),
        new(AskInvestGoldMinCg, ConfigValueKind.WholeNumber, "25", true, 1, 100000),
        new(AskInvestGoldKarat, ConfigValueKind.WholeNumber, "21", true, Allowed: [18, 21, 22, 24]),
        new(CatBatchMax, ConfigValueKind.WholeNumber, "20", true, 1, 20),
        new(CatMinConfidence, ConfigValueKind.WholeNumber, "60", true, 0, 100),
        new(CatCacheMinConfidence, ConfigValueKind.WholeNumber, "80", false, 0, 100),
        new(CatConfirmN, ConfigValueKind.WholeNumber, "3", false, 1, 100),
        new(CatQuotaFree, ConfigValueKind.WholeNumber, "15", true, 0, 100000),
        new(CatQuotaGold, ConfigValueKind.WholeNumber, "150", true, 0, 100000),
    ];

    /// <summary>The two provider display-name keys: sent as <c>providerName {ar, en}</c>, not inside <c>values</c>.</summary>
    public static bool IsProviderName(string key) => key is LlmProviderNameAr or LlmProviderNameEn;

    public static ConfigKeyDefinition? Find(string? key) =>
        key is null ? null : All.FirstOrDefault(d => string.Equals(d.Key, key, StringComparison.Ordinal));

    /// <summary>True when <paramref name="key"/> has the shape of a config key (ASCII only; the regex alone would allow a trailing newline).</summary>
    public static bool HasValidShape(string? key) =>
        key is { Length: >= 2 and <= 64 }
        && key[0] is >= 'a' and <= 'z'
        && key.All(c => c is (>= 'a' and <= 'z') or (>= '0' and <= '9') or '_' or '.');

    /// <summary>
    /// Checks <paramref name="raw"/> against the key's type and range and returns the canonical string. <c>false</c> for the wrong
    /// type, an out-of-range value, a non-ASCII digit or surrounding whitespace.
    /// </summary>
    public static bool TryCanonicalize(ConfigKeyDefinition definition, string? raw, out string canonical)
    {
        ArgumentNullException.ThrowIfNull(definition);
        canonical = string.Empty;
        if (raw is null)
        {
            return false;
        }

        switch (definition.Kind)
        {
            case ConfigValueKind.WholeNumber:
                if (!IntText().IsMatch(raw)
                    || !int.TryParse(raw, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var number)
                    || (definition.Allowed is { } allowed ? !allowed.Contains(number) : number < definition.Min || number > definition.Max))
                {
                    return false;
                }

                canonical = number.ToString(CultureInfo.InvariantCulture);
                return true;

            case ConfigValueKind.Amount:
                if (!DecimalText().IsMatch(raw)
                    || !decimal.TryParse(raw, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var amount)
                    || amount < definition.Min
                    || amount > definition.Max)
                {
                    return false;
                }

                canonical = amount.ToString("0.00", CultureInfo.InvariantCulture);
                return true;

            default:
                if (definition.Pattern is not { } pattern || raw.Length > 64 || !Regex.IsMatch(raw, pattern, RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(250)) || raw.EndsWith('\n'))
                {
                    return false;
                }

                canonical = raw;
                return true;
        }
    }

    [GeneratedRegex(@"^-?[0-9]{1,9}\z", RegexOptions.CultureInvariant, 250)]
    private static partial Regex IntText();

    [GeneratedRegex(@"^[0-9]{1,9}(\.[0-9]{1,2})?\z", RegexOptions.CultureInvariant, 250)]
    private static partial Regex DecimalText();
}
