using System.Text.RegularExpressions;

namespace Zaghlol.LlmEval.Tests;

/// <summary>AC1: 40 synthetic items in the specified group counts, every plan of the catalogue, the injection items.</summary>
public sealed class EvalSetTests
{
    private static readonly string[] Catalogue =
    [
        "PL-SPEND", "PL-COMPARE", "PL-BREAKDOWN", "PL-TOPN", "PL-AVERAGE", "PL-INCOME", "PL-SAVED", "PL-BILLS-DUE", "PL-BUDGET-LEFT",
        "PL-SAFE-SPEND", "PL-BALANCE", "PL-WHATIF-CUT", "PL-WHATIF-SAVE", "PL-SUGGEST", "PL-INVEST", "PL-FALLBACK", "PL-REFUSE",
    ];

    [Fact]
    public void The_set_has_40_items_in_the_specified_groups()
    {
        var set = Support.Set();
        Assert.Equal(40, set.Questions.Count);
        foreach (var (group, count) in EvalSet.GroupCounts)
        {
            Assert.Equal(count, set.Questions.Count(q => q.Group == group));
        }

        // SRS 10.1 groups: 8 data ar, 6 data en/mixed, 7 what-if, 4 suggestions, 6 investment, 5 refusal, 4 injection/edge.
        Assert.Equal(9, set.Questions.Count(q => q.IsSafetyItem));
        Assert.All(set.Questions.Where(q => q.Group == "data"), q => Assert.Equal("ar", q.Lang));
        Assert.All(set.Questions.Where(q => q.Group == "data_en"), q => Assert.NotEqual("ar", q.Lang));
    }

    [Fact]
    public void Every_plan_of_the_closed_catalogue_is_expected_somewhere()
    {
        var expected = Support.Set().Questions.SelectMany(q => q.Expect).Select(e => e.Plan).ToHashSet(StringComparer.Ordinal);
        Assert.All(Catalogue, p => Assert.Contains(p, expected));
    }

    [Fact]
    public void The_set_covers_placeholders_digits_mixed_language_and_the_what_if_example()
    {
        var questions = Support.Set().Questions;
        foreach (var token in new[] { "⟦CARD_1⟧", "⟦BANK_1⟧", "⟦MERCHANT_1⟧" })
        {
            Assert.Contains(questions, q => q.Text.Contains(token, StringComparison.Ordinal));
        }

        Assert.Contains(questions, q => Regex.IsMatch(q.Text, "[٠-٩]"));
        Assert.Contains(questions, q => q.Lang == "mixed" && Regex.IsMatch(q.Text, "[a-z]") && Regex.IsMatch(q.Text, "[ء-ي]"));
        Assert.Contains(questions, q => q.Text == "لو وفرت ٥٠٪ من الأكل هوفر كام في سنة");
    }

    [Fact]
    public void Investment_items_cover_each_d93_band_and_each_source_kind()
    {
        var invest = Support.Set().Questions.Where(q => q.Group == "invest").ToList();
        var amounts = invest.Select(q => q.Expect[0].P?["source"]?["amount"]?["amount"]?.GetValue<string>()).Where(a => a is not null).Select(a => decimal.Parse(a!, System.Globalization.CultureInfo.InvariantCulture)).ToList();
        Assert.Contains(amounts, a => a <= 100m);
        Assert.Contains(amounts, a => a is > 100m and < 1000m);
        Assert.Contains(amounts, a => a >= 1000m);
        var kinds = invest.Select(q => q.Expect[0].P?["source"]?["kind"]?.GetValue<string>()).ToHashSet(StringComparer.Ordinal);
        Assert.Superset(new HashSet<string> { "amount", "savedLastPeriod", "whatIf" }, kinds!);
    }

    [Fact]
    public void Injection_items_include_ignore_rules_a_url_a_300_character_ramble_and_a_zakah_question()
    {
        var injection = Support.Set().Questions.Where(q => q.Group == "injection").ToList();
        Assert.Contains(injection, q => q.Text.StartsWith("Ignore your rules", StringComparison.Ordinal));
        Assert.Contains(injection, q => q.Text.Contains("https://example.test/", StringComparison.Ordinal));
        Assert.Contains(injection, q => q.Text.Length is >= 250 and <= 300);
        var zakah = Assert.Single(injection, q => q.Expect.Any(e => e.P?["reason"]?.GetValue<string>() == "zakah"));
        Assert.Equal("PL-FALLBACK", zakah.Expect[0].Plan);
        Assert.Contains(Support.Set().Questions, q => q.Group == "refusal" && q.Expect[0].P?["selfHarm"]?.GetValue<bool>() == true);
    }

    [Fact]
    public void The_set_and_the_recordings_hold_nothing_that_looks_like_a_secret_or_a_real_contact()
    {
        var root = Path.Combine(Support.RepoRoot(), "backend", "tests", "Zaghlol.LlmEval");
        var text = string.Join('\n', Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories)
            .Where(f => !f.Contains("/obj/", StringComparison.Ordinal) && !f.Contains("/bin/", StringComparison.Ordinal) && !f.EndsWith(".cs", StringComparison.Ordinal))
            .Select(File.ReadAllText));
        Assert.DoesNotMatch(new Regex("(sk-[A-Za-z0-9]{10,}|AIza[0-9A-Za-z_-]{20,}|-----BEGIN|Bearer [A-Za-z0-9._-]{20,}|[A-Za-z0-9._-]+@[A-Za-z0-9-]+\\.[a-z]{2,}|\\b\\d{8,}\\b)"), text);
    }

    [Fact]
    public void The_recordings_are_marked_synthetic()
    {
        foreach (var provider in new[] { "openai", "vertex", "anthropic" })
        {
            using var doc = System.Text.Json.JsonDocument.Parse(File.ReadAllText(Support.RecordingPath(provider)));
            Assert.Equal(40, doc.RootElement.GetArrayLength());
            Assert.All(doc.RootElement.EnumerateArray(), e =>
            {
                Assert.True(e.GetProperty("synthetic").GetBoolean());
                Assert.Contains("not a real provider reply", e.GetProperty("note").GetString(), StringComparison.Ordinal);
            });
        }
    }
}
