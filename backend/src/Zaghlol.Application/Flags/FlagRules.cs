using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.Text;
using System.Text.Json;

namespace Zaghlol.Application.Flags;

/// <summary>
/// Targeting rules (<c>feature_flags.rules</c>, backend-api §4.8). All present conditions must hold for an install to get the
/// flag's value; an absent member does not restrict.
/// </summary>
/// <param name="Platforms"><c>android</c> and/or <c>ios</c>; when present, at least one, no duplicates.</param>
/// <param name="MinAppVersion"><c>major.minor.patch</c>; installs on an older version get <c>false</c>.</param>
/// <param name="RolloutPercent">0 to 100; the share of installs (by stable hash of the install ID) that get the value.</param>
public sealed record FlagRules(IReadOnlyList<string>? Platforms, string? MinAppVersion, int? RolloutPercent)
{
    public static FlagRules None { get; } = new(null, null, null);

    public bool IsEmpty => Platforms is null && MinAppVersion is null && RolloutPercent is null;
}

/// <summary>The field rules the JSON shape can't express (OpenAPI <c>FlagRules</c>).</summary>
public static class FlagRulesValidator
{
    /// <summary>The OpenAPI <c>FlagRules.minAppVersion</c> pattern, character for character (a contract test compares them).</summary>
    public const string MinAppVersionPattern = @"^\d{1,4}\.\d{1,4}\.\d{1,4}$";

    public static IReadOnlyList<string> Platforms { get; } = ["android", "ios"];

    public static bool IsValid(FlagRules rules)
    {
        ArgumentNullException.ThrowIfNull(rules);

        if (rules.Platforms is { } platforms
            && (platforms.Count == 0
                || platforms.Any(p => !Platforms.Contains(p, StringComparer.Ordinal))
                || platforms.Distinct(StringComparer.Ordinal).Count() != platforms.Count))
        {
            return false;
        }

        if (rules.MinAppVersion is { } min && !AppVersion.TryParseStrict(min, out _))
        {
            return false;
        }

        return rules.RolloutPercent is null or (>= 0 and <= 100);
    }
}

/// <summary>
/// The jsonb form kept in <c>feature_flags.rules</c>: <c>{"platforms":[..],"min_app_version":"..","rollout_percent":n}</c>,
/// members omitted when absent. Reading ignores members it doesn't know and treats a malformed value as no rule for that
/// member only where it can't be trusted to restrict; a stored value is always written by <see cref="Serialize"/>.
/// </summary>
public static class FlagRulesJson
{
    public static string Serialize(FlagRules rules)
    {
        ArgumentNullException.ThrowIfNull(rules);

        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            if (rules.Platforms is { } platforms)
            {
                writer.WriteStartArray("platforms");
                foreach (var platform in platforms)
                {
                    writer.WriteStringValue(platform);
                }

                writer.WriteEndArray();
            }

            if (rules.MinAppVersion is { } min)
            {
                writer.WriteString("min_app_version", min);
            }

            if (rules.RolloutPercent is { } percent)
            {
                writer.WriteNumber("rollout_percent", percent);
            }

            writer.WriteEndObject();
        }

        return Encoding.UTF8.GetString(stream.ToArray());
    }

    /// <summary>
    /// The strict reading used by the sync (FU-056): the stored text must be a JSON object whose members are only
    /// <c>platforms</c> (array of strings), <c>min_app_version</c> (string) and <c>rollout_percent</c> (32-bit integer), each at
    /// most once, and the result must pass <see cref="FlagRulesValidator.IsValid"/> (non-empty unique platforms, a
    /// <c>major.minor.patch</c> version, a percentage from 0 to 100). Anything else is a failure, never a partial rule set:
    /// the caller then treats the flag as OFF.
    /// </summary>
    public static bool TryParseStrict(string? json, [NotNullWhen(true)] out FlagRules? rules)
    {
        rules = null;
        if (json is null)
        {
            return false;
        }

        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(json);
        }
        catch (JsonException)
        {
            return false;
        }

        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return false;
            }

            IReadOnlyList<string>? platforms = null;
            string? min = null;
            int? percent = null;
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var member in root.EnumerateObject())
            {
                if (!seen.Add(member.Name))
                {
                    return false;
                }

                var value = member.Value;
                switch (member.Name)
                {
                    case "platforms":
                        if (value.ValueKind != JsonValueKind.Array)
                        {
                            return false;
                        }

                        var list = new List<string>();
                        foreach (var item in value.EnumerateArray())
                        {
                            if (item.ValueKind != JsonValueKind.String)
                            {
                                return false;
                            }

                            list.Add(item.GetString()!);
                        }

                        platforms = list;
                        break;
                    case "min_app_version":
                        if (value.ValueKind != JsonValueKind.String)
                        {
                            return false;
                        }

                        min = value.GetString();
                        break;
                    case "rollout_percent":
                        if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out var number))
                        {
                            return false;
                        }

                        percent = number;
                        break;
                    default:
                        return false;
                }
            }

            var parsed = new FlagRules(platforms, min, percent);
            if (!FlagRulesValidator.IsValid(parsed))
            {
                return false;
            }

            rules = parsed;
            return true;
        }
    }

    /// <summary>The lenient reading for admin read paths; the sync uses <see cref="TryParseStrict"/>.</summary>
    public static FlagRules Parse(string json)
    {
        ArgumentNullException.ThrowIfNull(json);

        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
        {
            return FlagRules.None;
        }

        IReadOnlyList<string>? platforms = null;
        if (root.TryGetProperty("platforms", out var p) && p.ValueKind == JsonValueKind.Array)
        {
            platforms = p.EnumerateArray()
                .Where(e => e.ValueKind == JsonValueKind.String)
                .Select(e => e.GetString()!)
                .ToList();
        }

        string? min = root.TryGetProperty("min_app_version", out var m) && m.ValueKind == JsonValueKind.String ? m.GetString() : null;
        int? percent = root.TryGetProperty("rollout_percent", out var r) && r.ValueKind == JsonValueKind.Number && r.TryGetInt32(out var value)
            ? value
            : null;
        return new FlagRules(platforms, min, percent);
    }

    /// <summary>For the audit row and the ops-channel message: a compact, human-readable form.</summary>
    public static string Describe(FlagRules rules)
    {
        ArgumentNullException.ThrowIfNull(rules);

        var parts = new List<string>();
        if (rules.Platforms is { } platforms)
        {
            parts.Add("platforms=" + string.Join('/', platforms));
        }

        if (rules.MinAppVersion is { } min)
        {
            parts.Add("minAppVersion=" + min);
        }

        if (rules.RolloutPercent is { } percent)
        {
            parts.Add("rolloutPercent=" + percent.ToString(CultureInfo.InvariantCulture));
        }

        return parts.Count == 0 ? "none" : string.Join(", ", parts);
    }
}
