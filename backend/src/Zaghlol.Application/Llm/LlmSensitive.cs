using System.Text.Json;
using System.Text.Json.Serialization;

namespace Zaghlol.Application.Llm;

/// <summary>
/// The wrapper for question text and model replies on the LLM path (and the type T-349 must use for the request members <c>q</c>,
/// <c>p</c> and <c>t</c>). <see cref="ToString"/> is <c>***</c>, there is no public property, and System.Text.Json writes the fixed
/// string <c>"***"</c> wherever the value sits (bare, nested in a DTO, in a collection) while still reading the bare JSON value.
/// <c>Zaghlol.Domain.Sensitive{T}</c> keeps writing the bare value because some responses (the install token) need that.
/// </summary>
[JsonConverter(typeof(LlmSensitiveJsonConverterFactory))]
public readonly record struct LlmSensitive<T>
{
    public const string Redaction = "***";

    private readonly T value;

    public LlmSensitive(T value) => this.value = value;

    public T Reveal() => value;

    public override string ToString() => Redaction;
}

/// <summary>Reads <see cref="LlmSensitive{T}"/> from the bare JSON value and always writes <c>"***"</c>.</summary>
public sealed class LlmSensitiveJsonConverterFactory : JsonConverterFactory
{
    public override bool CanConvert(Type typeToConvert)
    {
        ArgumentNullException.ThrowIfNull(typeToConvert);
        return typeToConvert.IsGenericType && typeToConvert.GetGenericTypeDefinition() == typeof(LlmSensitive<>);
    }

    public override JsonConverter? CreateConverter(Type typeToConvert, JsonSerializerOptions options)
    {
        ArgumentNullException.ThrowIfNull(typeToConvert);
        return (JsonConverter?)Activator.CreateInstance(typeof(LlmSensitiveJsonConverter<>).MakeGenericType(typeToConvert.GetGenericArguments()[0]));
    }
}

public sealed class LlmSensitiveJsonConverter<T> : JsonConverter<LlmSensitive<T>>
{
    public override LlmSensitive<T> Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        new(JsonSerializer.Deserialize<T>(ref reader, options)!);

    public override void Write(Utf8JsonWriter writer, LlmSensitive<T> value, JsonSerializerOptions options)
    {
        ArgumentNullException.ThrowIfNull(writer);
        writer.WriteStringValue(LlmSensitive<T>.Redaction);
    }
}
