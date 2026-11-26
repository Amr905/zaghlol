namespace Zaghlol.Application.Llm.Categorise;

/// <summary>One published alias (<c>catalog_aliases</c>): <see cref="Match"/> is <c>exact</c>, <c>prefix</c> or <c>token</c> (the catalog's match modes).</summary>
public sealed record CatalogAliasEntry(int MerchantId, string Alias, string Match);

/// <summary>The published catalog as the categorise endpoint reads it: its version, the live top-level system category codes and the alias index.</summary>
public sealed record CategoriseCatalog(int Version, IReadOnlyList<string> Codes, CatalogAliasIndex Aliases);

/// <summary>The published catalog read model for <c>POST /v1/categorise</c> (rechecked by version, FR-CAT-06). Never sees a user's name beyond the lookup key.</summary>
public interface ICategoriseCatalog
{
    Task<CategoriseCatalog> GetAsync(CancellationToken cancellationToken);
}

/// <summary>
/// Alias lookup for FR-LCAT-10 with the FR-CAT-06 rules, in this order: (1) the key equals an alias; (2) whole-token <c>prefix</c> and <c>token</c> matches
/// (the longest alias wins, a <c>prefix</c> beats a <c>token</c> of the same length), (3) a conservative fuzzy step (edit distance 1, 6 or more letters,
/// the same digits). At each step merchants of more than one category mean no answer, never a guess. The phone stays the authority: a miss here only
/// costs a quota unit, a hit costs nothing.
/// </summary>
public sealed class CatalogAliasIndex
{
    public const int FuzzyMinLetters = 6;

    private readonly IReadOnlyList<(string Alias, string Match, string Category)> entries;
    private readonly Dictionary<string, HashSet<string>> byAlias;

    public CatalogAliasIndex(IEnumerable<CatalogAliasEntry> aliases, IReadOnlyDictionary<int, string> categoryByMerchant)
    {
        ArgumentNullException.ThrowIfNull(aliases);
        ArgumentNullException.ThrowIfNull(categoryByMerchant);
        entries = [.. aliases.Where(a => categoryByMerchant.ContainsKey(a.MerchantId)).Select(a => (a.Alias, a.Match, categoryByMerchant[a.MerchantId]))];
        byAlias = entries.GroupBy(e => e.Alias, StringComparer.Ordinal).ToDictionary(g => g.Key, g => g.Select(e => e.Category).ToHashSet(StringComparer.Ordinal), StringComparer.Ordinal);
    }

    public static CatalogAliasIndex Empty { get; } = new([], new Dictionary<int, string>());

    public int Count => entries.Count;

    /// <summary>The category code of the merchant the key names, or <c>null</c> (no match, or an ambiguous one).</summary>
    public string? Find(string key)
    {
        ArgumentNullException.ThrowIfNull(key);
        var words = Words(key);
        if (words.Length == 0)
        {
            return null;
        }

        if (byAlias.TryGetValue(words, out var exact))
        {
            return exact.Count == 1 ? exact.First() : null;
        }

        var tokens = words.Split(' ');
        var best = entries
            .Where(e => e.Match != "exact" && Matches(e.Alias, e.Match, tokens))
            .GroupBy(e => (e.Alias.Length, Tokens: e.Alias.Count(c => c == ' '), Prefix: e.Match == "prefix"))
            .OrderByDescending(g => g.Key.Length).ThenByDescending(g => g.Key.Tokens).ThenByDescending(g => g.Key.Prefix)
            .FirstOrDefault();
        if (best is not null)
        {
            var categories = best.Select(e => e.Category).ToHashSet(StringComparer.Ordinal);
            return categories.Count == 1 ? categories.First() : null;
        }

        return Fuzzy(words);
    }

    /// <summary>Lower-case words of letters and digits separated by single spaces (anything else is a space), as the phone's canonical key.</summary>
    internal static string Words(string key) =>
        string.Join(' ', new string([.. key.Select(c => char.IsLetterOrDigit(c) ? char.ToLowerInvariant(c) : ' ')]).Split(' ', StringSplitOptions.RemoveEmptyEntries));

    private static bool Matches(string alias, string mode, string[] tokens)
    {
        var aliasTokens = alias.Split(' ');
        if (aliasTokens.Length > tokens.Length)
        {
            return false;
        }

        var last = mode == "prefix" ? 0 : tokens.Length - aliasTokens.Length;
        for (var start = 0; start <= last; start++)
        {
            if (aliasTokens.SequenceEqual(tokens.Skip(start).Take(aliasTokens.Length), StringComparer.Ordinal))
            {
                return true;
            }
        }

        return false;
    }

    private string? Fuzzy(string words)
    {
        var compact = words.Replace(" ", string.Empty, StringComparison.Ordinal);
        if (compact.Count(char.IsLetter) < FuzzyMinLetters)
        {
            return null;
        }

        var digits = new string([.. compact.Where(char.IsDigit)]);
        var categories = new HashSet<string>(StringComparer.Ordinal);
        foreach (var (alias, _, category) in entries)
        {
            var other = alias.Replace(" ", string.Empty, StringComparison.Ordinal);
            if (Math.Abs(other.Length - compact.Length) <= 1 && new string([.. other.Where(char.IsDigit)]) == digits && WithinOneEdit(other, compact))
            {
                categories.Add(category);
            }
        }

        return categories.Count == 1 ? categories.First() : null;
    }

    private static bool WithinOneEdit(string a, string b)
    {
        if (a == b)
        {
            return true;
        }

        var i = 0;
        while (i < a.Length && i < b.Length && a[i] == b[i])
        {
            i++;
        }

        var j = 0;
        while (j < a.Length - i && j < b.Length - i && a[^(j + 1)] == b[^(j + 1)])
        {
            j++;
        }

        return Math.Max(a.Length, b.Length) - i - j <= 1;
    }
}
