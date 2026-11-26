namespace Zaghlol.Application.Llm.Plans;

/// <summary>Bundled number words, matched after <see cref="PlanText.Fold"/> as whole words (ask-llm.md section 2.2).</summary>
internal sealed class NumberWords
{
    private readonly List<(string Word, decimal Value)> words;

    public NumberWords(IReadOnlyDictionary<string, decimal> source) =>
        words = source.Select(kv => (PlanText.Fold(kv.Key), kv.Value)).ToList();

    /// <summary>Values of every number word that occurs as a whole word in the folded text.</summary>
    public HashSet<decimal> ValuesIn(string foldedText)
    {
        var values = new HashSet<decimal>();
        foreach (var (word, value) in words)
        {
            if (PlanText.ContainsWord(foldedText, word))
            {
                values.Add(value);
            }
        }

        return values;
    }
}
