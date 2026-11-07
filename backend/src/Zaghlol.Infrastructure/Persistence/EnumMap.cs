using System.Collections.Frozen;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace Zaghlol.Infrastructure.Persistence;

/// <summary>
/// An explicit, total mapping between a C# enum and the text values allowed by its column's <c>IN (...)</c> CHECK.
/// Every enum member must be mapped exactly once, and no two members may share a value.
/// </summary>
public sealed class EnumMap<TEnum>
    where TEnum : struct, Enum
{
    private readonly FrozenDictionary<TEnum, string> toDb;
    private readonly FrozenDictionary<string, TEnum> fromDb;

    public EnumMap(params (TEnum Value, string Db)[] pairs)
    {
        ArgumentNullException.ThrowIfNull(pairs);

        toDb = pairs.ToFrozenDictionary(p => p.Value, p => p.Db);
        fromDb = pairs.ToFrozenDictionary(p => p.Db, p => p.Value, StringComparer.Ordinal);

        var members = Enum.GetValues<TEnum>();
        if (toDb.Count != pairs.Length || fromDb.Count != pairs.Length || members.Length != pairs.Length
            || members.Any(m => !toDb.ContainsKey(m)))
        {
            throw new ArgumentException($"{typeof(TEnum).Name} must map every member to a distinct value exactly once.", nameof(pairs));
        }

        Converter = new ValueConverter<TEnum, string>(v => ToDb(v), s => FromDb(s));
    }

    /// <summary>The DB values, in declaration order of the enum.</summary>
    public IReadOnlyList<string> DbValues => [.. Enum.GetValues<TEnum>().Select(m => toDb[m])];

    public ValueConverter<TEnum, string> Converter { get; }

    public string ToDb(TEnum value) =>
        toDb.TryGetValue(value, out var db) ? db : throw new ArgumentOutOfRangeException(nameof(value), value, "Unmapped enum value.");

    public TEnum FromDb(string value) =>
        fromDb.TryGetValue(value, out var member)
            ? member
            : throw new InvalidOperationException($"Unexpected {typeof(TEnum).Name} value in the database.");
}
