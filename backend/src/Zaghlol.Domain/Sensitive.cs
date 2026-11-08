using System.Text.Json;
using System.Text.Json.Serialization;

namespace Zaghlol.Domain;

/// <summary>
/// A request member that carries a secret (<c>orderId</c>, <c>seatKeys</c>, tokens, proofs, ...). <see cref="ToString"/> is
/// <c>***</c> and there is no public property, so record <c>ToString()</c>, string interpolation and Serilog <c>{@Dto}</c>
/// destructuring never show the value. Read it only at the point of use with <see cref="Reveal"/>.
/// </summary>
[JsonConverter(typeof(SensitiveJsonConverterFactory))]
public readonly record struct Sensitive<T>
{
    private readonly T value;

    public Sensitive(T value) => this.value = value;

    public T Reveal() => value;

    public override string ToString() => "***";
}

/// <summary>Reads and writes <see cref="Sensitive{T}"/> as the bare JSON value.</summary>
public sealed class SensitiveJsonConverterFactory : JsonConverterFactory
{
    public override bool CanConvert(Type typeToConvert)
    {
        ArgumentNullException.ThrowIfNull(typeToConvert);
        return typeToConvert.IsGenericType && typeToConvert.GetGenericTypeDefinition() == typeof(Sensitive<>);
    }

    public override JsonConverter? CreateConverter(Type typeToConvert, JsonSerializerOptions options)
    {
        ArgumentNullException.ThrowIfNull(typeToConvert);
        return (JsonConverter?)Activator.CreateInstance(typeof(SensitiveJsonConverter<>).MakeGenericType(typeToConvert.GetGenericArguments()[0]));
    }
}

public sealed class SensitiveJsonConverter<T> : JsonConverter<Sensitive<T>>
{
    public override Sensitive<T> Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        new(JsonSerializer.Deserialize<T>(ref reader, options)!);

    public override void Write(Utf8JsonWriter writer, Sensitive<T> value, JsonSerializerOptions options) =>
        JsonSerializer.Serialize(writer, value.Reveal(), options);
}
