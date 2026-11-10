using System.Globalization;
using System.Text;
using Zaghlol.Application.Contributions;

namespace Zaghlol.Application.Sync;

/// <summary>Counts of one kind of intake item by result (metric <c>zaghlol.sync.intake</c>).</summary>
public sealed record IntakeCounts(int Filtered, int InvalidCode, int Duplicate);

/// <summary>The items to insert and what was dropped on the way.</summary>
public sealed record PreparedIntake(
    IReadOnlyList<PreparedContribution> Contributions,
    IntakeCounts ContributionDrops,
    IReadOnlyList<PreparedBankRequest> BankRequests,
    IntakeCounts BankRequestDrops)
{
    public bool IsEmpty => Contributions.Count == 0 && BankRequests.Count == 0;
}

/// <summary>
/// BR-SYNC-04 intake validation (T-128 design note §4). Per item: normalize, privacy filter, code checks, in-request dedupe.
/// A violation drops the item silently: it is counted, never echoed and never logged. Pure; no I/O.
/// </summary>
public static class SyncIntake
{
    /// <summary>Shortest acceptable normalized free text.</summary>
    public const int MinTextLength = 2;

    /// <summary>The OpenAPI <c>InstitutionCode</c> pattern, character for character (a contract test compares them).</summary>
    public const string InstitutionCodePattern = "^[a-z0-9_]{2,32}$";

    /// <summary>The OpenAPI <c>BankRequestInput.country</c> pattern.</summary>
    public const string CountryPattern = "^[A-Z]{2}$";

    /// <summary>The OpenAPI <c>BankRequestInput.channel</c> enum.</summary>
    public static IReadOnlyList<string> Channels { get; } = ["sms", "notification"];

    public static PreparedIntake Prepare(
        IReadOnlyList<SyncContribution> contributions,
        IReadOnlyList<SyncBankRequest> bankRequests,
        IReadOnlySet<string> categoryCodes)
    {
        ArgumentNullException.ThrowIfNull(contributions);
        ArgumentNullException.ThrowIfNull(bankRequests);
        ArgumentNullException.ThrowIfNull(categoryCodes);

        var preparedContributions = new List<PreparedContribution>();
        var contributionKeys = new HashSet<(string, string)>();
        int filtered = 0, invalid = 0, duplicate = 0;
        foreach (var item in contributions)
        {
            var merchant = NormalizeText(item.MerchantNorm);
            if (merchant is null || !ContributionPrivacy.IsAcceptable(merchant))
            {
                filtered++;
            }
            else if (!IsInstitutionCode(item.InstitutionCode) || !categoryCodes.Contains(item.CategoryCode))
            {
                invalid++;
            }
            else if (!contributionKeys.Add((merchant, item.InstitutionCode)))
            {
                duplicate++;
            }
            else
            {
                preparedContributions.Add(new PreparedContribution(merchant, item.InstitutionCode, item.CategoryCode));
            }
        }

        var contributionDrops = new IntakeCounts(filtered, invalid, duplicate);

        var preparedBanks = new List<PreparedBankRequest>();
        var bankKeys = new HashSet<(string, string, string)>();
        filtered = invalid = duplicate = 0;
        foreach (var item in bankRequests)
        {
            var name = NormalizeText(item.InstitutionName);
            if (name is null || !ContributionPrivacy.IsAcceptable(name))
            {
                filtered++;
            }
            else if (!IsCountry(item.Country) || !Channels.Contains(item.Channel, StringComparer.Ordinal))
            {
                invalid++;
            }
            else if (!bankKeys.Add((name, item.Country, item.Channel)))
            {
                duplicate++;
            }
            else
            {
                preparedBanks.Add(new PreparedBankRequest(name, item.Country, item.Channel));
            }
        }

        return new PreparedIntake(preparedContributions, contributionDrops, preparedBanks, new IntakeCounts(filtered, invalid, duplicate));
    }

    /// <summary>
    /// The stored form of a free-text field, or <c>null</c> when it is empty or shorter than <see cref="MinTextLength"/>:
    /// control and format characters (zero-width, bidi marks) removed, fullwidth ASCII and the ideographic space folded to
    /// ASCII, whitespace runs collapsed to one space and trimmed, Latin letters lower-cased (Arabic is unchanged). Digits are
    /// not folded here: the privacy filter folds them itself, so the database CHECK sees the same text the API filtered.
    /// </summary>
    /// <remarks>
    /// This is the compatibility folding the design note's NFKC step is for, done by hand: the host runs with invariant
    /// globalization (as <c>CatalogText</c> notes), so <c>string.Normalize</c> is not relied on. Removing format characters
    /// matters for the privacy filter: a zero-width space between digits would otherwise break a phone number's digit run.
    /// </remarks>
    public static string? NormalizeText(string? text)
    {
        if (text is null)
        {
            return null;
        }

        var builder = new StringBuilder(text.Length);
        var pendingSpace = false;
        foreach (var raw in text)
        {
            var c = Fold(raw);
            var category = char.GetUnicodeCategory(c);
            if (char.IsWhiteSpace(c))
            {
                pendingSpace = builder.Length > 0;
                continue;
            }

            if (category is UnicodeCategory.Control or UnicodeCategory.Format)
            {
                continue;
            }

            if (pendingSpace)
            {
                builder.Append(' ');
                pendingSpace = false;
            }

            builder.Append(IsLatin(c) ? char.ToLowerInvariant(c) : c);
        }

        return builder.Length < MinTextLength ? null : builder.ToString();
    }

    public static bool IsInstitutionCode(string? code) =>
        code is { Length: >= 2 and <= 32 } && code.All(c => c is (>= 'a' and <= 'z') or (>= '0' and <= '9') or '_');

    public static bool IsCountry(string? country) =>
        country is { Length: 2 } && country.All(c => c is >= 'A' and <= 'Z');

    // Fullwidth ASCII (U+FF01-FF5E) and the ideographic space: the NFKC compatibility mappings that matter for this text.
    private static char Fold(char c) => c switch
    {
        >= '！' and <= '～' => (char)(c - 0xFEE0),
        '　' => ' ',
        _ => c,
    };

    private static bool IsLatin(char c) => c < 'ɐ' && char.IsLetter(c);
}
