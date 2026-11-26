using System.Globalization;
using System.Text.Json.Nodes;

namespace Zaghlol.LlmEval;

/// <summary>
/// The "exact plan + params" rule (T-350 design note). The plan id must be equal. The expected <c>p</c> is a <b>subset</b> of the reply's
/// <c>p</c>: every key the set names must be present and match, recursively; keys the set leaves out are free (limit, instruments the
/// question did not name, a currency the user never typed). Integers compare as integers, decimal strings as numbers (<c>500</c> =
/// <c>500.00</c>), other strings exactly, and <c>{"$set":[...]}</c> is an order-insensitive set. No synonyms and no partial credit.
/// </summary>
public static class PlanMatcher
{
    public static bool Matches(ExpectedPlan expected, string actualPlan, JsonNode? actualP)
    {
        ArgumentNullException.ThrowIfNull(expected);
        return string.Equals(expected.Plan, actualPlan, StringComparison.Ordinal) && (expected.P is null || Subset(expected.P, actualP));
    }

    public static bool Subset(JsonNode? expected, JsonNode? actual)
    {
        switch (expected)
        {
            case null:
                return actual is null;
            case JsonObject eo when eo.Count == 1 && eo.ContainsKey("$set"):
                return actual is JsonArray aa && SameSet((JsonArray)eo["$set"]!, aa);
            case JsonObject eo:
                return actual is JsonObject ao && eo.All(kv => ao.TryGetPropertyValue(kv.Key, out var v) && Subset(kv.Value, v));
            case JsonArray ea:
                return actual is JsonArray aa2 && ea.Count == aa2.Count && ea.Zip(aa2).All(p => Subset(p.First, p.Second));
            case JsonValue ev:
                return actual is JsonValue av && ScalarEqual(ev, av);
            default:
                return false;
        }
    }

    private static bool SameSet(JsonArray expected, JsonArray actual)
    {
        var e = expected.Select(n => n?.ToString()).Order(StringComparer.Ordinal).ToList();
        var a = actual.Select(n => n?.ToString()).Order(StringComparer.Ordinal).ToList();
        return e.SequenceEqual(a, StringComparer.Ordinal);
    }

    private static bool ScalarEqual(JsonValue expected, JsonValue actual)
    {
        if (expected.TryGetValue<string>(out var es))
        {
            if (!actual.TryGetValue<string>(out var s))
            {
                return false;
            }

            return decimal.TryParse(es, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var ed)
                && decimal.TryParse(s, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var ad)
                ? ed == ad
                : string.Equals(es, s, StringComparison.Ordinal);
        }

        if (expected.TryGetValue<bool>(out var eb))
        {
            return actual.TryGetValue<bool>(out var ab) && eb == ab;
        }

        return expected.TryGetValue<long>(out var el) && actual.TryGetValue<long>(out var al) && el == al;
    }
}
