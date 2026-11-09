using System.Buffers;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Zaghlol.Application.Catalog;

/// <summary>
/// The non-key fields of one catalog entry, as the draft keeps them in its <c>body</c> column. Which members are set depends on
/// the entity: categories <c>nameAr, nameEn, icon, color, bucket, sort</c>; merchants <c>canonical, nameAr, category</c>; aliases
/// <c>match</c>; keywords <c>category, weight</c>.
/// </summary>
public sealed record CatalogFields
{
    private static readonly JsonSerializerOptions StorageOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public string? NameAr { get; init; }

    public string? NameEn { get; init; }

    public string? Icon { get; init; }

    public string? Color { get; init; }

    public string? Bucket { get; init; }

    public int? Sort { get; init; }

    public string? Canonical { get; init; }

    public string? Category { get; init; }

    public string? Match { get; init; }

    public int? Weight { get; init; }

    public static CatalogFields FromJson(string json) =>
        JsonSerializer.Deserialize<CatalogFields>(json, StorageOptions) ?? new CatalogFields();

    public string ToJson() => JsonSerializer.Serialize(this, StorageOptions);
}

/// <summary>One catalog change: an upsert of <see cref="Fields"/> under <see cref="Key"/>, or a tombstone (<see cref="Delete"/>).</summary>
public sealed record CatalogOp(CatalogEntryKey Key, bool Delete, CatalogFields Fields);

/// <summary>
/// The wire form of <see cref="CatalogOp"/> (OpenAPI <c>CatalogOp</c>) and of the full snapshot. Written by hand with fixed
/// member order so the same ops always give the same bytes (the signature covers them). Deletes carry the key only.
/// </summary>
public static class CatalogJson
{
    private static readonly JsonWriterOptions WriterOptions = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    public static void WriteOp(Utf8JsonWriter writer, CatalogOp op)
    {
        ArgumentNullException.ThrowIfNull(writer);
        ArgumentNullException.ThrowIfNull(op);

        var key = op.Key;
        var fields = op.Fields;
        writer.WriteStartObject();
        switch (key.Entity)
        {
            case CatalogEntity.Categories:
                Head(writer, "category", op.Delete);
                writer.WriteString("code", key.Code);
                if (!op.Delete)
                {
                    writer.WriteString("nameAr", fields.NameAr ?? string.Empty);
                    writer.WriteString("nameEn", fields.NameEn ?? string.Empty);
                    writer.WriteString("icon", fields.Icon ?? string.Empty);
                    writer.WriteString("color", fields.Color ?? "#000000");
                    writer.WriteString("bucket", fields.Bucket ?? string.Empty);
                    writer.WriteNumber("sort", fields.Sort ?? 0);
                }

                break;
            case CatalogEntity.Merchants:
                Head(writer, "merchant", op.Delete);
                writer.WriteNumber("id", key.MerchantId);
                if (!op.Delete)
                {
                    writer.WriteString("canonical", fields.Canonical ?? string.Empty);
                    writer.WriteString("nameAr", fields.NameAr ?? string.Empty);
                    writer.WriteString("category", fields.Category ?? string.Empty);
                }

                break;
            case CatalogEntity.Aliases:
                Head(writer, "alias", op.Delete);
                writer.WriteNumber("merchantId", key.MerchantId);
                writer.WriteString("alias", key.Text);
                if (!op.Delete)
                {
                    writer.WriteString("match", fields.Match ?? "exact");
                }

                break;
            default:
                Head(writer, "keyword", op.Delete);
                writer.WriteString("keyword", key.Text);
                writer.WriteString("lang", key.Lang);
                if (!op.Delete)
                {
                    writer.WriteString("category", fields.Category ?? string.Empty);
                    writer.WriteNumber("weight", fields.Weight ?? 0);
                }

                break;
        }

        writer.WriteEndObject();
    }

    /// <summary><c>{"version":N,"ops":[...]}</c> (OpenAPI <c>CatalogSnapshot</c>).</summary>
    public static byte[] Snapshot(int version, IEnumerable<CatalogOp> ops)
    {
        ArgumentNullException.ThrowIfNull(ops);

        var buffer = new ArrayBufferWriter<byte>(64 * 1024);
        using (var writer = new Utf8JsonWriter(buffer, WriterOptions))
        {
            writer.WriteStartObject();
            writer.WriteNumber("version", version);
            writer.WriteStartArray("ops");
            foreach (var op in ops)
            {
                WriteOp(writer, op);
            }

            writer.WriteEndArray();
            writer.WriteEndObject();
        }

        return buffer.WrittenSpan.ToArray();
    }

    /// <summary>One op as a JSON document.</summary>
    public static byte[] OfOp(CatalogOp op)
    {
        var buffer = new ArrayBufferWriter<byte>(256);
        using (var writer = new Utf8JsonWriter(buffer, WriterOptions))
        {
            WriteOp(writer, op);
        }

        return buffer.WrittenSpan.ToArray();
    }

    /// <summary><c>{"items":[...],"nextCursor":...}</c> (OpenAPI <c>CatalogDraftPage</c>).</summary>
    public static byte[] Page(IEnumerable<CatalogOp> items, string? nextCursor)
    {
        ArgumentNullException.ThrowIfNull(items);

        var buffer = new ArrayBufferWriter<byte>(4096);
        using (var writer = new Utf8JsonWriter(buffer, WriterOptions))
        {
            writer.WriteStartObject();
            writer.WriteStartArray("items");
            foreach (var item in items)
            {
                WriteOp(writer, item);
            }

            writer.WriteEndArray();
            writer.WriteString("nextCursor", nextCursor);
            writer.WriteEndObject();
        }

        return buffer.WrittenSpan.ToArray();
    }

    private static void Head(Utf8JsonWriter writer, string type, bool delete)
    {
        writer.WriteString("t", type);
        writer.WriteString("op", delete ? "delete" : "upsert");
    }
}

/// <summary>
/// The order in which a delta lists its ops (backend-api §5.2): upserts parents first (categories, merchants, aliases,
/// keywords), then tombstones children first (keywords, aliases, merchants, categories). A merchant's alias tombstones
/// therefore always come before the merchant's own, and a merchant moved off a deleted category is upserted before that
/// category is removed. Within a group the order is by key, so the output is deterministic.
/// </summary>
public static class CatalogDeltaOrder
{
    public static IReadOnlyList<CatalogOp> Order(IEnumerable<CatalogOp> ops)
    {
        ArgumentNullException.ThrowIfNull(ops);

        var all = ops.ToList();
        var upserts = all.Where(o => !o.Delete)
            .OrderBy(o => UpsertRank(o.Key.Entity))
            .ThenBy(o => o.Key.MerchantId)
            .ThenBy(o => o.Key.StorageKey, StringComparer.Ordinal);
        var deletes = all.Where(o => o.Delete)
            .OrderBy(o => DeleteRank(o.Key.Entity))
            .ThenBy(o => o.Key.MerchantId)
            .ThenBy(o => o.Key.StorageKey, StringComparer.Ordinal);
        return [.. upserts, .. deletes];
    }

    // The enum is declared parents first, so its value is the upsert rank.
    private static int UpsertRank(CatalogEntity entity) => (int)entity;

    private static int DeleteRank(CatalogEntity entity) => (int)CatalogEntity.Keywords - (int)entity;
}
