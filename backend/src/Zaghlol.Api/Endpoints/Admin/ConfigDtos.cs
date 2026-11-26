namespace Zaghlol.Api.Endpoints.Admin;

/// <summary>
/// <c>ConfigUpdateRequest</c>: the value as its canonical string (integers <c>-?[0-9]+</c>, decimals with two fraction digits,
/// text). A JSON number or any other type is <c>400 VALIDATION_FAILED</c>.
/// </summary>
public sealed class ConfigUpdateRequest
{
    public required string Value { get; init; }
}

/// <summary><c>ConfigState</c>: <c>isDefault</c> is true while no row exists (or the stored one no longer validates); <c>version</c> is 0 then.</summary>
public sealed class ConfigStateDto
{
    public required string Key { get; init; }

    public required string Value { get; init; }

    public required bool IsDefault { get; init; }

    public required long Version { get; init; }

    public required DateTimeOffset UpdatedAt { get; init; }
}

/// <summary><c>ConfigList</c>: every key of the closed set, in catalogue order.</summary>
public sealed class ConfigListDto
{
    public required IReadOnlyList<ConfigStateDto> Items { get; init; }
}
