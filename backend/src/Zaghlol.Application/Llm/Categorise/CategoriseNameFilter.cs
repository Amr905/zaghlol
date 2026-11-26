using System.Text.RegularExpressions;
using Zaghlol.Application.Contributions;

namespace Zaghlol.Application.Llm.Categorise;

/// <summary>
/// The server-side privacy re-check of a merchant name (llm-categorise §2, §3 step 1), run although the phone filters first. A name that fails is
/// <c>rejected</c>: never sent to a provider, never cached, never counted. It is <see cref="ContributionPrivacy"/> (64 units, no <c>@</c>, no run of
/// six digits) plus the stricter rules of this feature: a run of <see cref="MaxAdjacentDigits"/> or more digits in any script (a phone, a card or an
/// account tail), <c>+digit</c>, an IBAN shape, a URL or a domain. Any other identifier shape the phone's list names is a refusal, never a guess.
/// </summary>
public static partial class CategoriseNameFilter
{
    /// <summary>A name with this many digits in a row (after folding every script to ASCII) is refused; the phone's rule is 6 across separators.</summary>
    public const int MaxAdjacentDigits = 4;

    public static bool IsAcceptable(string raw, string key)
    {
        ArgumentNullException.ThrowIfNull(raw);
        ArgumentNullException.ThrowIfNull(key);

        if (key.Length is < CategoriseRequestParser.MinMerchantChars or > ContributionPrivacy.MaxLength
            || !ContributionPrivacy.IsAcceptable(raw) || !ContributionPrivacy.IsAcceptable(key))
        {
            return false;
        }

        var folded = ContributionPrivacy.Fold(raw).ToLowerInvariant();
        return !HasDigitRun(folded) && !Shapes().IsMatch(folded);
    }

    private static bool HasDigitRun(string folded)
    {
        var run = 0;
        foreach (var c in folded)
        {
            run = c is >= '0' and <= '9' ? run + 1 : 0;
            if (run >= MaxAdjacentDigits)
            {
                return true;
            }
        }

        return false;
    }

    // +digit (a phone), an IBAN (2 letters, 2 digits, 10 or more letters/digits), a URL or a domain.
    [GeneratedRegex(@"\+\s*[0-9]|(?<![a-z0-9])[a-z]{2}[0-9]{2}[a-z0-9]{10,}|://|www\.|[a-z0-9-]+\.(com|net|org|eg|io|app|co|me|info|biz)(?![a-z0-9])", RegexOptions.CultureInvariant, 250)]
    private static partial Regex Shapes();
}
