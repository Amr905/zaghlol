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
    /// control and format characters (zero-width, bidi marks) and combining marks (<c>Mn</c>, <c>Me</c>: accents, Arabic
    /// harakat, variation selectors, the combining grapheme joiner) removed; fullwidth ASCII, the ideographic space and the small
    /// commercial at (U+FE6B) folded to ASCII; every digit <see cref="ContributionPrivacy.DigitValue"/> accepts (any Unicode
    /// decimal digit, plus superscript, subscript and circled digits) folded to its ASCII digit; whitespace runs collapsed to
    /// one space and trimmed; Latin letters lower-cased (Arabic is unchanged). The privacy filter then runs on exactly this
    /// text, which is what is stored, so the database CHECK sees the text the API filtered.
    /// </summary>
    /// <remarks>
    /// This is the compatibility folding the design note's NFKC step is for, done by hand: the host runs with invariant
    /// globalization (as <c>CatalogText</c> notes), so <c>string.Normalize</c> is not relied on; the digit and category lookups
    /// use CoreLib's own Unicode tables. Removing format characters and combining marks matters for the privacy filter: a
    /// zero-width space or a combining accent between digits must not break a phone number's digit run.
    /// </remarks>
    public static string? NormalizeText(string? text)
    {
        if (text is null)
        {
            return null;
        }

        var builder = new StringBuilder(text.Length);
        var pendingSpace = false;
        foreach (var raw in text.EnumerateRunes())
        {
            var rune = Fold(raw);
            if (Rune.IsWhiteSpace(rune))
            {
                pendingSpace = builder.Length > 0;
                continue;
            }

            if (Rune.GetUnicodeCategory(rune) is UnicodeCategory.Control or UnicodeCategory.Format
                or UnicodeCategory.NonSpacingMark or UnicodeCategory.EnclosingMark)
            {
                continue;
            }

            if (pendingSpace)
            {
                builder.Append(' ');
                pendingSpace = false;
            }

            if (rune.IsBmp && IsLatin((char)rune.Value))
            {
                builder.Append(char.ToLowerInvariant((char)rune.Value));
            }
            else
            {
                builder.Append(rune.ToString());
            }
        }

        return builder.Length < MinTextLength ? null : builder.ToString();
    }

    public static bool IsInstitutionCode(string? code) =>
        code is { Length: >= 2 and <= 32 } && code.All(c => c is (>= 'a' and <= 'z') or (>= '0' and <= '9') or '_');

    public static bool IsCountry(string? country) =>
        country is { Length: 2 } && country.All(c => c is >= 'A' and <= 'Z');

    // The NFKC compatibility mappings that matter for this text: fullwidth ASCII (U+FF01-FF5E, including the fullwidth "@"),
    // the ideographic space and the small commercial at (U+FE6B); and every digit to ASCII.
    private static Rune Fold(Rune rune)
    {
        if (ContributionPrivacy.DigitValue(rune) is { } digit)
        {
            return new Rune('0' + digit);
        }

        return rune.Value switch
        {
            >= 0xFF01 and <= 0xFF5E => new Rune(rune.Value - 0xFEE0),
            0x3000 => new Rune(' '),
            0xFE6B => new Rune('@'),
            _ => rune,
        };
    }

    private static bool IsLatin(char c) => c < 'ɐ' && char.IsLetter(c);
}
