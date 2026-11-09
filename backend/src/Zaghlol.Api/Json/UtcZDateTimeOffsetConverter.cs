using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Zaghlol.Api.Json;

/// <summary>
/// The global timestamp converter (backend-api §1, <c>UtcTimestamp</c>): writes <c>yyyy-MM-ddTHH:mm:ssZ</c> and refuses to
/// write a value with a non-zero offset; reads only RFC 3339 instants that end in <c>Z</c> (no <c>+00:00</c>, no offsets).
/// </summary>
public sealed class UtcZDateTimeOffsetConverter : JsonConverter<DateTimeOffset>
{
    public const string WriteFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'";

    private static readonly string[] ReadFormats = [WriteFormat, "yyyy'-'MM'-'dd'T'HH':'mm':'ss'.'FFFFFFF'Z'"];

    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType != JsonTokenType.String
            || reader.GetString() is not { } text
            || !DateTimeOffset.TryParseExact(
                text,
                ReadFormats,
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                out var value))
        {
            throw new JsonException();
        }

        return value;
    }

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options)
    {
        ArgumentNullException.ThrowIfNull(writer);
        if (value.Offset != TimeSpan.Zero)
        {
            throw new JsonException("Timestamps are written in UTC only.");
        }

        writer.WriteStringValue(value.ToString(WriteFormat, CultureInfo.InvariantCulture));
    }
}
