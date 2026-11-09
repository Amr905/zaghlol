using System.Text.Json.Serialization;

namespace Zaghlol.Api.Endpoints.Admin;

/// <summary>
/// <c>FlagRules</c> (backend-api §4.8): closed (any other member is <c>400 UNKNOWN_FIELD</c>), every member optional. Members
/// that are absent are omitted when written.
/// </summary>
public sealed class FlagRulesDto
{
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public IReadOnlyList<string>? Platforms { get; init; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? MinAppVersion { get; init; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public int? RolloutPercent { get; init; }
}

/// <summary><c>FlagUpdateRequest</c>: <c>rules</c> replaces the stored rules as a whole when present and keeps them when absent.</summary>
public sealed class FlagUpdateRequest
{
    public required bool Value { get; init; }

    public FlagRulesDto? Rules { get; init; }
}

/// <summary><c>FlagState</c>.</summary>
public sealed class FlagStateDto
{
    public required string Key { get; init; }

    public required bool Value { get; init; }

    public required FlagRulesDto Rules { get; init; }

    public required int Version { get; init; }

    public required DateTimeOffset UpdatedAt { get; init; }
}
