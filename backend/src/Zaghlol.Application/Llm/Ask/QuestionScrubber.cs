using System.Text;
using System.Text.RegularExpressions;

namespace Zaghlol.Application.Llm.Ask;

/// <summary>
/// Server-side scrub of the incoming question (ask-llm §1, FR-LLM-03): defence in depth behind the phone's own scrub and masker. It
/// replaces e-mail addresses, InstaPay addresses, phone numbers and runs of 8 or more digits (Arabic-Indic digits included) with the same
/// neutral tokens the phone uses, and leaves the phone's own tokens (<c>⟦PHONE⟧</c>, <c>⟦CARD_1⟧</c> ...) and everything else alone. Pure: no I/O and
/// nothing logged. It cannot find names; those are the phone masker's job (FR-LLM-18) and the validator rejects plans that name one.
/// </summary>
public static partial class QuestionScrubber
{
    public const string Phone = "⟦PHONE⟧";
    public const string Email = "⟦EMAIL⟧";
    public const string InstaPay = "⟦IPA⟧";
    public const string Number = "⟦NUMBER⟧";

    public static string Scrub(string text)
    {
        ArgumentNullException.ThrowIfNull(text);

        // Digit folding is one char to one char, so the indexes of the folded text are those of the original.
        var folded = FoldDigits(text);
        var spans = new List<(int Start, int End, string Token)>();

        foreach (Match match in Address().Matches(folded))
        {
            var domain = match.Value[(match.Value.IndexOf('@', StringComparison.Ordinal) + 1)..];
            spans.Add((match.Index, match.Index + match.Length, domain.Contains('.', StringComparison.Ordinal) ? Email : InstaPay));
        }

        foreach (Match match in SpacedInstaPay().Matches(folded))
        {
            spans.Add((match.Index, match.Index + match.Length, InstaPay));
        }

        foreach (Match match in SeparatedPhone().Matches(folded))
        {
            spans.Add((match.Index, match.Index + match.Length, Phone));
        }

        foreach (Match match in DigitRun().Matches(folded))
        {
            var digits = match.Value.Count(char.IsAsciiDigit);
            if (digits < 8 || spans.Any(s => s.Start < match.Index + match.Length && match.Index < s.End))
            {
                continue;
            }

            var phone = match.Value.StartsWith('+') || EgyptianMobile().IsMatch(DigitsOnly(match.Value)) || Landline().IsMatch(DigitsOnly(match.Value));
            spans.Add((match.Index, match.Index + match.Length, phone ? Phone : Number));
        }

        if (spans.Count == 0)
        {
            return text;
        }

        // Earlier additions win an overlap (addresses first), then left to right.
        var ordered = spans.OrderBy(s => s.Start).ThenByDescending(s => s.End).ToList();
        var output = new StringBuilder(text.Length);
        var cursor = 0;
        foreach (var (start, end, token) in ordered)
        {
            if (start < cursor)
            {
                continue;
            }

            output.Append(text, cursor, start - cursor).Append(token);
            cursor = end;
        }

        return output.Append(text, cursor, text.Length - cursor).ToString();
    }

    private static string FoldDigits(string text) => string.Create(text.Length, text, static (span, source) =>
    {
        for (var i = 0; i < source.Length; i++)
        {
            var c = source[i];
            span[i] = c switch
            {
                >= '٠' and <= '٩' => (char)('0' + (c - '٠')),
                >= '۰' and <= '۹' => (char)('0' + (c - '۰')),
                _ => c,
            };
        }
    });

    private static string DigitsOnly(string value) => new([.. value.Where(char.IsAsciiDigit)]);

    [GeneratedRegex(@"[\p{L}\p{N}._%+\-]+@[\p{L}\p{N}\-]+(?:\.[\p{L}\p{N}\-]+)*", RegexOptions.CultureInvariant, 250)]
    private static partial Regex Address();

    [GeneratedRegex(@"[\p{L}\p{N}._%+\-]+ ?@ ?instapay\b", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase, 250)]
    private static partial Regex SpacedInstaPay();

    [GeneratedRegex(@"(?<![0-9])(?:\+?20|0020|0)[ .\-]?1[0125](?:[ .\-]?[0-9]){8}(?![0-9])", RegexOptions.CultureInvariant, 250)]
    private static partial Regex SeparatedPhone();

    [GeneratedRegex(@"\+?[0-9]+(?:[ \-][0-9]{3,})*", RegexOptions.CultureInvariant, 250)]
    private static partial Regex DigitRun();

    [GeneratedRegex(@"^(?:0020|20)?0?1[0125][0-9]{8}\z", RegexOptions.CultureInvariant, 250)]
    private static partial Regex EgyptianMobile();

    [GeneratedRegex(@"^0[2-9][0-9]{7,8}\z", RegexOptions.CultureInvariant, 250)]
    private static partial Regex Landline();
}
