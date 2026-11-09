using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.Text.RegularExpressions;

namespace Zaghlol.Application.Flags;

/// <summary>A <c>major.minor.patch</c> app version. Ordering ignores any <c>-pre</c> or <c>+build</c> suffix.</summary>
public readonly partial record struct AppVersion(int Major, int Minor, int Patch)
{
    /// <summary>Strict form (<c>FlagRules.minAppVersion</c>): exactly three ASCII numeric parts.</summary>
    public static bool TryParseStrict(string? text, [NotNullWhen(true)] out AppVersion? version)
    {
        version = null;
        if (text is null || text.Length > 14 || !text.All(c => c is >= '0' and <= '9' or '.') || !Strict().IsMatch(text))
        {
            return false;
        }

        version = ParseParts(text);
        return true;
    }

    /// <summary>
    /// An install's <c>appVersion</c> (it may carry a suffix, validated at registration). Anything unparseable gives
    /// <c>null</c>, which a version rule treats as "too old".
    /// </summary>
    public static AppVersion? TryParseInstalled(string? text)
    {
        if (text is null)
        {
            return null;
        }

        var core = text.Split('-', '+')[0];
        return TryParseStrict(core, out var version) ? version : null;
    }

    /// <summary>True when this version is strictly lower than <paramref name="other"/>.</summary>
    public bool IsOlderThan(AppVersion other) =>
        Major != other.Major ? Major < other.Major : Minor != other.Minor ? Minor < other.Minor : Patch < other.Patch;

    private static AppVersion ParseParts(string text)
    {
        var parts = text.Split('.');
        return new AppVersion(
            int.Parse(parts[0], CultureInfo.InvariantCulture),
            int.Parse(parts[1], CultureInfo.InvariantCulture),
            int.Parse(parts[2], CultureInfo.InvariantCulture));
    }

    [GeneratedRegex(FlagRulesValidator.MinAppVersionPattern, RegexOptions.CultureInvariant)]
    private static partial Regex Strict();
}
