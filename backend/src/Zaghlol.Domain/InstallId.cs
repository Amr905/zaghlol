using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Zaghlol.Domain;

/// <summary>
/// The anonymous install ID: a UUID v4 in lowercase 8-4-4-4-12 form (FU-013). It is the only shape the JSON converter,
/// the <c>Zaghlol-Install</c> header check and the log pseudonymizer accept, so free-form text never reaches them (F6).
/// </summary>
[JsonConverter(typeof(InstallIdJsonConverter))]
public readonly record struct InstallId
{
    public const int Length = 36;

    private InstallId(Guid value) => Value = value;

    public Guid Value { get; }

    /// <summary>True only for a lowercase UUID v4 (version nibble 4, variant 8, 9, a or b).</summary>
    public static bool TryParse([NotNullWhen(true)] string? text, out InstallId installId)
    {
        installId = default;
        if (text is null || text.Length != Length)
        {
            return false;
        }

        for (var i = 0; i < Length; i++)
        {
            var c = text[i];
            var valid = i is 8 or 13 or 18 or 23 ? c == '-' : c is (>= '0' and <= '9') or (>= 'a' and <= 'f');
            if (!valid)
            {
                return false;
            }
        }

        if (text[14] != '4' || text[19] is not ('8' or '9' or 'a' or 'b') || !Guid.TryParseExact(text, "D", out var value))
        {
            return false;
        }

        installId = new InstallId(value);
        return true;
    }

    /// <summary>Parses a value that must be valid (constants, database rows written by this service).</summary>
    public static InstallId Parse(string text) =>
        TryParse(text, out var installId) ? installId : throw new FormatException("Not a lowercase UUID v4 install ID.");

    /// <summary>An install ID read back from the database; it was validated when it was registered.</summary>
    public static InstallId FromGuid(Guid value) => Parse(value.ToString("D", CultureInfo.InvariantCulture));

    public override string ToString() => Value.ToString("D", CultureInfo.InvariantCulture);
}

/// <summary>Reads and writes <see cref="InstallId"/> as its string form; anything else is a <see cref="JsonException"/>.</summary>
public sealed class InstallIdJsonConverter : JsonConverter<InstallId>
{
    public override InstallId Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType != JsonTokenType.String || !InstallId.TryParse(reader.GetString(), out var installId))
        {
            throw new JsonException();
        }

        return installId;
    }

    public override void Write(Utf8JsonWriter writer, InstallId value, JsonSerializerOptions options)
    {
        ArgumentNullException.ThrowIfNull(writer);
        writer.WriteStringValue(value.ToString());
    }
}
