using System.Security.Cryptography;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>A foreign key to a new, valid parent row of <paramref name="Table"/> (created by that table's writer).</summary>
public sealed record Ref(string Table, string KeyColumn = "id");

/// <summary>Valid synthetic rows per table, and the least-privilege login that writes each table in production.</summary>
public static class Rows
{
    public static byte[] Bytes(int length = 32) => RandomNumberGenerator.GetBytes(length);

    /// <summary>Now, at the microsecond precision PostgreSQL stores.</summary>
    public static DateTimeOffset Now()
    {
        var ticks = DateTimeOffset.UtcNow.UtcTicks;
        return new DateTimeOffset(ticks - (ticks % 10), TimeSpan.Zero);
    }

    /// <summary>A whole UTC hour a day from now.</summary>
    public static DateTimeOffset WholeHour()
    {
        var ticks = DateTimeOffset.UtcNow.AddDays(1).UtcTicks;
        return new DateTimeOffset(ticks - (ticks % TimeSpan.TicksPerHour), TimeSpan.Zero);
    }

    public static Dictionary<string, object?> Install(Guid id) => new(StringComparer.Ordinal)
    {
        ["id"] = id,
        ["token_hash"] = Bytes(),
        ["platform"] = "android",
        ["app_version"] = "1.0.0",
    };

    public static Dictionary<string, object?> Base(string table) => table switch
    {
        "installs" => Install(Guid.CreateVersion7()),
        "accounts" => new(StringComparer.Ordinal)
        {
            ["id"] = Guid.CreateVersion7(),
            ["provider"] = "google",
            ["provider_subject"] = Guid.NewGuid().ToString("N"),
        },
        "purchases" => new(StringComparer.Ordinal)
        {
            ["id"] = Guid.CreateVersion7(),
            ["store"] = "google_play",
            ["product_id"] = "zaghlol_gold_monthly",
            ["plan"] = "monthly",
            ["store_key"] = Guid.NewGuid().ToString("N"),
            ["state"] = "active",
            ["environment"] = "production",
            ["last_verified_at"] = Now(),
        },
        "purchase_events" => new(StringComparer.Ordinal)
        {
            ["id"] = Guid.CreateVersion7(),
            ["purchase_id"] = new Ref("purchases"),
            ["to_state"] = "active",
            ["cause"] = "verify",
        },
        "store_notifications" => new(StringComparer.Ordinal)
        {
            ["id"] = Guid.CreateVersion7(),
            ["store"] = "google_play",
            ["external_id"] = Guid.NewGuid().ToString("N"),
            ["type"] = "SUBSCRIPTION_PURCHASED",
            ["payload_digest"] = Bytes(),
        },
        "purchase_seats" => new(StringComparer.Ordinal)
        {
            ["purchase_id"] = new Ref("purchases"),
            ["install_id"] = new Ref("installs"),
            ["proof"] = "basic",
        },
        "seat_claimants" => new(StringComparer.Ordinal)
        {
            ["purchase_id"] = new Ref("purchases"),
            ["install_id"] = new Ref("installs"),
            ["claimed_at"] = Now(),
            ["channel"] = "restore",
        },
        "app_attest_keys" => new(StringComparer.Ordinal)
        {
            ["key_id"] = Bytes(),
            ["install_id"] = new Ref("installs"),
            ["public_key"] = Bytes(65),
            ["sign_count"] = 0L,
            ["environment"] = "production",
        },
        "replay_guard" => new(StringComparer.Ordinal)
        {
            ["key_hash"] = Bytes(),
            ["kind"] = "signin_google",
            ["expires_at"] = Now().AddHours(1),
        },
        "idempotency_records" => new(StringComparer.Ordinal)
        {
            ["install_id"] = Guid.CreateVersion7(),
            ["operation_id"] = "verifyPurchase",
            ["idempotency_key"] = Ulid(),
            ["body_sha256"] = Bytes(),
            ["status"] = 200,
            ["response_body_enc"] = Bytes(48),
            ["expires_at"] = Now().AddHours(24),
        },
        "catalog_versions" => new(StringComparer.Ordinal)
        {
            ["version"] = RandomNumberGenerator.GetInt32(1, int.MaxValue),
            ["published_at"] = Now(),
            ["published_by"] = Guid.CreateVersion7(),
            ["full_snapshot_url"] = "https://cdn.example.invalid/catalog/1/full.json",
            ["full_snapshot_sha256"] = Bytes(),
        },
        "merchant_contributions" => new(StringComparer.Ordinal)
        {
            ["id"] = Guid.CreateVersion7(),
            ["merchant_norm"] = "carrefour maadi",
            ["institution_code"] = "cib",
            ["category_code"] = "groceries",
            ["install_hash"] = Bytes(),
        },
        "contribution_aggregates" => new(StringComparer.Ordinal)
        {
            ["merchant_norm"] = "m" + Guid.NewGuid().ToString("N")[..20],
            ["institution_code"] = "cib",
            ["distinct_installs"] = 1,
            ["top_category_code"] = "groceries",
            ["category_votes"] = new Jsonb("{\"groceries\": 1}"),
            ["status"] = "collecting",
        },
        "bank_requests" => new(StringComparer.Ordinal)
        {
            ["institution_name_norm"] = "bank of somewhere",
            ["country"] = "EG",
            ["channel"] = "sms",
            ["install_hash"] = Bytes(),
        },
        "daily_active_counts" => new(StringComparer.Ordinal)
        {
            ["day"] = DateOnly.FromDateTime(DateTime.UtcNow).AddDays(-RandomNumberGenerator.GetInt32(1, 100_000)),
            ["platform"] = "android",
            ["app_version"] = "1.4.0",
            ["installs"] = 1,
        },
        "catalog_categories" => new(StringComparer.Ordinal)
        {
            ["code"] = "c_" + Guid.NewGuid().ToString("N")[..12],
            ["name_ar"] = "بقالة",
            ["name_en"] = "Groceries",
            ["icon"] = "cart",
            ["color"] = "#0F7A55",
            ["bucket"] = "needs",
            ["sort"] = 1,
            ["version"] = 1,
        },
        "catalog_merchants" => new(StringComparer.Ordinal)
        {
            ["canonical"] = "m_" + Guid.NewGuid().ToString("N")[..12],
            ["category_code"] = new Ref("catalog_categories", "code"),
            ["version"] = 1,
        },
        "catalog_drafts" => new(StringComparer.Ordinal)
        {
            ["entity"] = "categories",
            ["entry_key"] = "c_" + Guid.NewGuid().ToString("N")[..12],
            ["body"] = new Jsonb("{}"),
            ["deleted"] = false,
            ["published"] = false,
            ["changed"] = true,
        },
        "price_quotes" => new(StringComparer.Ordinal)
        {
            ["symbol"] = "XAU21_G",
            ["currency"] = "EGP",
            ["price"] = 4217.5m,
            ["per_unit"] = "gram",
            ["as_of"] = Now(),
            ["source"] = "fake",
            ["is_override"] = false,
        },
        "operators" => new(StringComparer.Ordinal)
        {
            ["id"] = Guid.CreateVersion7(),
            ["oidc_subject"] = Guid.NewGuid().ToString("N"),
            ["display_name"] = "Support Operator",
            ["roles"] = new[] { "support" },
        },
        "audit_log" => new(StringComparer.Ordinal)
        {
            ["operator_id"] = new Ref("operators"),
            ["action"] = "support_lookup",
            ["target"] = Guid.CreateVersion7().ToString(),
            ["details"] = new Jsonb("{\"account_id\": null}"),
        },
        _ => throw new ArgumentOutOfRangeException(nameof(table), table, "no synthetic row for this table"),
    };

    /// <summary>The login that writes the table in production (see GrantMatrix).</summary>
    public static string Writer(ZaghlolTestDatabase database, string table) => table switch
    {
        "catalog_versions" or "catalog_categories" or "catalog_merchants" or "catalog_drafts" or "audit_log" => database.Admin,
        "contribution_aggregates" or "daily_active_counts" or "price_quotes" => database.Worker,
        "operators" => database.Migrator, // no runtime role writes operators yet (T-136)
        _ => database.Api,
    };

    /// <summary>Creates parents for <see cref="Ref"/> values (recursively) and returns the row with their keys.</summary>
    public static async Task<Dictionary<string, object?>> ResolveAsync(ZaghlolTestDatabase database, Dictionary<string, object?> row)
    {
        foreach (var (column, value) in row.ToList())
        {
            if (value is Ref reference)
            {
                var parent = await ResolveAsync(database, Base(reference.Table));
                await Db.InsertAsync(Writer(database, reference.Table), reference.Table, parent);
                row[column] = parent[reference.KeyColumn];
            }
        }

        return row;
    }

    /// <summary>Inserts a valid row of <paramref name="table"/> with <paramref name="overrides"/> applied.</summary>
    public static async Task<Dictionary<string, object?>> InsertAsync(
        ZaghlolTestDatabase database,
        string table,
        IReadOnlyDictionary<string, object?>? overrides = null)
    {
        var row = Base(table);
        foreach (var (column, value) in overrides ?? new Dictionary<string, object?>())
        {
            row[column] = value;
        }

        row = await ResolveAsync(database, row);
        await Db.InsertAsync(Writer(database, table), table, row);
        return row;
    }

    private static string Ulid()
    {
        const string alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
        return string.Concat(Enumerable.Range(0, 26).Select(_ => alphabet[RandomNumberGenerator.GetInt32(alphabet.Length)]));
    }
}
