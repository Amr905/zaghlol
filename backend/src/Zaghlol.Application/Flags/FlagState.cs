namespace Zaghlol.Application.Flags;

/// <summary>One flag as stored (OpenAPI <c>FlagState</c>). <see cref="Version"/> is 0 for a flag that was never set.</summary>
public sealed record FlagState(string Key, bool Value, FlagRules Rules, int Version, DateTimeOffset UpdatedAt)
{
    /// <summary>A known flag nobody has set yet: OFF, no rules, version 0 (FR-BE-05 "default OFF").</summary>
    public static FlagState Default(string key) => new(key, false, FlagRules.None, 0, DateTimeOffset.UnixEpoch);
}
