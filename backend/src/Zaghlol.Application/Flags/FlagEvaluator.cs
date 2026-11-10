using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using Zaghlol.Domain;

namespace Zaghlol.Application.Flags;

/// <summary>The flags an install gets in a sync response (<c>flags</c>, backend-api §4.4).</summary>
/// <param name="Version">The sum of the flags' versions: it rises with every change to any flag.</param>
/// <param name="Values">One entry per known flag, in <see cref="FlagKeys.Known"/> order.</param>
public sealed record FlagSnapshot(int Version, IReadOnlyDictionary<string, bool> Values)
{
    /// <summary>Known flags whose stored rules failed the strict parse; each is OFF in <see cref="Values"/> (FU-056).</summary>
    public IReadOnlyList<string> InvalidRules { get; init; } = [];
}

/// <summary>
/// Pure targeting logic (FR-BE-05). A flag is ON for an install only if its value is ON and every present rule holds.
/// The rollout bucket is <c>SHA-256("zaghlol.flag.v1:" + key + ":" + installId)</c>, first four bytes big-endian, mod 100:
/// stable for an install and flag (no state, no clock), different per flag, and monotone in the percentage (raising it only
/// adds installs). The v1 prefix is part of the contract: changing it would reshuffle every rollout.
/// </summary>
public static class FlagEvaluator
{
    public const string BucketPrefix = "zaghlol.flag.v1:";

    /// <summary>The install's bucket for this flag, 0 to 99.</summary>
    public static int Bucket(string key, InstallId installId)
    {
        ArgumentNullException.ThrowIfNull(key);

        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(BucketPrefix + key + ":" + installId));
        return (int)(BinaryPrimitives.ReadUInt32BigEndian(hash) % 100);
    }

    public static bool IsEnabled(FlagState flag, string platform, string appVersion, InstallId installId)
    {
        ArgumentNullException.ThrowIfNull(flag);

        if (!flag.Value || flag.RulesInvalid)
        {
            return false;
        }

        var rules = flag.Rules;
        if (rules.Platforms is { } platforms && !platforms.Contains(platform, StringComparer.Ordinal))
        {
            return false;
        }

        if (rules.MinAppVersion is { } min)
        {
            // Both parse by construction; an install version that doesn't is treated as too old (fail closed).
            if (!AppVersion.TryParseStrict(min, out var minimum) || AppVersion.TryParseInstalled(appVersion) is not { } installed || installed.IsOlderThan(minimum.Value))
            {
                return false;
            }
        }

        return rules.RolloutPercent is not { } percent || Bucket(flag.Key, installId) < percent;
    }

    /// <summary>
    /// Every known flag for this install; a flag with no stored row is OFF. A flag whose stored rules are corrupt
    /// (<see cref="FlagState.RulesInvalid"/>) is OFF for everyone and listed in <see cref="FlagSnapshot.InvalidRules"/>, so the
    /// caller can count it (fail closed, FU-056).
    /// </summary>
    public static FlagSnapshot Snapshot(IEnumerable<FlagState> stored, string platform, string appVersion, InstallId installId)
    {
        ArgumentNullException.ThrowIfNull(stored);

        var byKey = stored.Where(f => FlagKeys.IsKnown(f.Key)).ToDictionary(f => f.Key, StringComparer.Ordinal);
        var values = new Dictionary<string, bool>(StringComparer.Ordinal);
        var invalid = new List<string>();
        var version = 0;
        foreach (var key in FlagKeys.Known)
        {
            var flag = byKey.GetValueOrDefault(key) ?? FlagState.Default(key);
            values[key] = IsEnabled(flag, platform, appVersion, installId);
            version += flag.Version;
            if (flag.RulesInvalid)
            {
                invalid.Add(key);
            }
        }

        return new FlagSnapshot(version, values) { InvalidRules = invalid };
    }
}
