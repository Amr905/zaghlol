using Zaghlol.Application.Llm.Spend;

namespace Zaghlol.LlmEval.Tests;

internal static class Support
{
    /// <summary>Illustrative prices of the recorded run (USD per million tokens). Synthetic: not any provider's price list.</summary>
    public static readonly IReadOnlyDictionary<string, LlmPrices> RecordedPrices = new Dictionary<string, LlmPrices>(StringComparer.Ordinal)
    {
        ["openai"] = new(0.40m, 0.10m, 1.60m),
        ["vertex"] = new(0.30m, 0.03m, 2.50m),
        ["anthropic"] = new(1.00m, 0.10m, 5.00m),
    };

    public static string DataPath(string name) => Path.Combine(AppContext.BaseDirectory, "data", name);

    public static string RecordingPath(string provider) => Path.Combine(AppContext.BaseDirectory, "recordings", provider + ".json");

    public static EvalSet Set() => EvalSet.Load(DataPath("questions-v1.yaml"));

    public static string RepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "CLAUDE.md")))
        {
            dir = dir.Parent;
        }

        return dir?.FullName ?? throw new InvalidOperationException("Repository root not found.");
    }
}
