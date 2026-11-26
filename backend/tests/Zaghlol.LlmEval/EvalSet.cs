using System.Globalization;
using System.Text.Json.Nodes;
using YamlDotNet.Core;
using YamlDotNet.Core.Events;
using YamlDotNet.RepresentationModel;

namespace Zaghlol.LlmEval;

/// <summary>One acceptable answer: the plan id and an optional subset of <c>p</c> (see <see cref="PlanMatcher"/>).</summary>
public sealed record ExpectedPlan(string Plan, JsonNode? P);

/// <summary>One synthetic evaluation question. <see cref="Group"/> is one of <see cref="EvalSet.GroupCounts"/>.</summary>
public sealed record EvalQuestion(string Id, string Group, string Lang, string Text, IReadOnlyList<ExpectedPlan> Expect)
{
    /// <summary>Refusal and injection items: the pass rule needs every one of them right.</summary>
    public bool IsSafetyItem => Group is "refusal" or "injection";
}

/// <summary>The 40-question set of SRS 10.1 (<c>data/questions-v1.yaml</c>). All questions are synthetic.</summary>
public sealed class EvalSet
{
    public const int Total = 40;

    public static IReadOnlyDictionary<string, int> GroupCounts { get; } = new Dictionary<string, int>(StringComparer.Ordinal)
    {
        ["data"] = 8,
        ["data_en"] = 6,
        ["whatif"] = 7,
        ["suggest"] = 4,
        ["invest"] = 6,
        ["refusal"] = 5,
        ["injection"] = 4,
    };

    private EvalSet(IReadOnlyList<EvalQuestion> questions) => Questions = questions;

    public IReadOnlyList<EvalQuestion> Questions { get; }

    public static EvalSet Load(string path)
    {
        ArgumentNullException.ThrowIfNull(path);
        var stream = new YamlStream();
        using (var reader = new StreamReader(path))
        {
            stream.Load(reader);
        }

        var root = (YamlMappingNode)stream.Documents[0].RootNode;
        if (ToJson(Get(root, "synthetic")) is not JsonValue flag || !flag.TryGetValue<bool>(out var synthetic) || !synthetic)
        {
            throw new InvalidDataException("The set must declare synthetic: true.");
        }

        var list = new List<EvalQuestion>();
        foreach (var node in ((YamlSequenceNode)Get(root, "questions")).Children.Cast<YamlMappingNode>())
        {
            var expect = ((JsonArray)ToJson(Get(node, "expect"))!).Select(e => new ExpectedPlan(
                e!["plan"]!.GetValue<string>(), e["p"]?.DeepClone())).ToList();
            list.Add(new EvalQuestion(Str(node, "id"), Str(node, "group"), Str(node, "lang"), Str(node, "text"), expect));
        }

        Validate(list);
        return new EvalSet(list);
    }

    private static void Validate(List<EvalQuestion> list)
    {
        if (list.Count != Total)
        {
            throw new InvalidDataException("The set must have exactly 40 questions.");
        }

        if (list.Select(q => q.Id).Distinct(StringComparer.Ordinal).Count() != Total
            || list.Select(q => q.Text).Distinct(StringComparer.Ordinal).Count() != Total)
        {
            throw new InvalidDataException("Question ids and texts must be unique.");
        }

        foreach (var (group, count) in GroupCounts)
        {
            if (list.Count(q => q.Group == group) != count)
            {
                throw new InvalidDataException("A group has the wrong number of questions: " + group);
            }
        }

        if (list.Any(q => q.Lang is not ("ar" or "en" or "mixed") || q.Text.Length is < 1 or > 300 || q.Expect.Count == 0))
        {
            throw new InvalidDataException("A question has a bad language, length or no expectation.");
        }
    }

    private static YamlNode Get(YamlMappingNode map, string key) =>
        map.Children.TryGetValue(new YamlScalarNode(key), out var v) ? v : throw new InvalidDataException("Missing key " + key);

    private static string Str(YamlMappingNode map, string key) => ((YamlScalarNode)Get(map, key)).Value ?? string.Empty;

    /// <summary>YAML to JSON: a quoted scalar is a string; a plain one is null, a boolean or an integer, else a string.</summary>
    private static JsonNode? ToJson(YamlNode node) => node switch
    {
        YamlMappingNode m => new JsonObject(m.Children.Select(kv => KeyValuePair.Create(((YamlScalarNode)kv.Key).Value!, ToJson(kv.Value)))),
        YamlSequenceNode s => new JsonArray(s.Children.Select(ToJson).ToArray()),
        YamlScalarNode { Style: ScalarStyle.Plain } p => Plain(p.Value),
        YamlScalarNode q => JsonValue.Create(q.Value),
        _ => throw new InvalidDataException("Unsupported YAML node."),
    };

    private static JsonValue? Plain(string? value) => value switch
    {
        null or "null" or "~" or "" => null,
        "true" => JsonValue.Create(true),
        "false" => JsonValue.Create(false),
        _ when long.TryParse(value, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out var n) => JsonValue.Create(n),
        _ => JsonValue.Create(value),
    };
}
