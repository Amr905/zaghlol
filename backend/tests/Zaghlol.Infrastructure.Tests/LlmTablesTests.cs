using Npgsql;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>T-273: the six LLM-helper tables (column lists, privacy inventory, merchant_norm backstop, range checks).</summary>
[Collection(SchemaGroup.Name)]
public class LlmTablesTests(SchemaFixture fixture)
{
    private static readonly string[] Tables =
        ["llm_quota_counters", "llm_spend_daily", "remote_config", "llm_cat_answer_cache", "llm_cat_confirmations", "llm_cat_corrections"];

    /// <summary>AC 2: the exact column lists of ask-llm §4.5 and llm-categorise §4, in order, with type and nullability.</summary>
    public static TheoryData<string, string> ExpectedColumns => new()
    {
        { "llm_quota_counters", "feature:text:N,subject_kind:text:N,subject_id:uuid:N,month_key:integer:N,used:integer:N,last_request_hash:bytea:Y,updated_at:timestamp with time zone:N" },
        { "llm_spend_daily", "day:date:N,feature:text:N,provider_id:text:N,model:text:N,calls:integer:N,input_tokens:bigint:N,cached_tokens:bigint:N,output_tokens:bigint:N,cost_usd:numeric(14,6):N" },
        { "remote_config", "key:text:N,value:text:N,version:bigint:N,updated_by:uuid:Y,updated_at:timestamp with time zone:N" },
        { "llm_cat_answer_cache", "merchant_norm:text:N,category_code:text:N,confidence:smallint:N,provider_id:text:N,prompt_version:text:N,created_at:timestamp with time zone:N,expires_at:timestamp with time zone:N,hits:integer:N" },
        { "llm_cat_confirmations", "id:uuid:N,merchant_norm:text:N,category_code:text:N,source:text:N,install_hash:bytea:N,created_at:timestamp with time zone:N,status:text:N" },
        { "llm_cat_corrections", "id:uuid:N,merchant_norm:text:N,ai_category:text:N,user_category:text:N,source:text:N,install_hash:bytea:N,created_at:timestamp with time zone:N,status:text:N,operator_id:uuid:Y,resolved_at:timestamp with time zone:Y" },
    };

    [Theory]
    [MemberData(nameof(ExpectedColumns))]
    public async Task ColumnListsMatchTheSpecExactly(string table, string expected)
    {
        var rows = await Db.QueryAsync(
            fixture.Database.Superuser,
            """
            SELECT a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || CASE WHEN a.attnotnull THEN 'N' ELSE 'Y' END
            FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'zaghlol' AND c.relname = $1 AND a.attnum > 0 AND NOT a.attisdropped
            ORDER BY a.attnum
            """,
            table);

        Assert.Equal(expected, string.Join(",", rows.Select(r => (string)r[0]!)));
    }

    [Fact]
    public async Task NoFloatingTypeAnywhereAndCostIsNumeric()
    {
        var floating = await Db.QueryAsync(
            fixture.Database.Superuser,
            """
            SELECT table_name || '.' || column_name FROM information_schema.columns
            WHERE table_schema = 'zaghlol' AND table_name = ANY($1) AND data_type IN ('double precision', 'real', 'money')
            """,
            Tables);

        Assert.Empty(floating);
    }

    /// <summary>
    /// AC 4, negative proof 1: every text, bytea and uuid column of the six tables is listed with what it can hold. A new such
    /// column fails here until someone states why it can't hold a question, an install or account id, an IP or an app version.
    /// </summary>
    [Fact]
    public async Task EveryTextByteaOrUuidColumnIsOnTheReviewedList()
    {
        var actual = (await Db.QueryAsync(
                fixture.Database.Superuser,
                """
                SELECT table_name || '.' || column_name FROM information_schema.columns
                WHERE table_schema = 'zaghlol' AND table_name = ANY($1) AND data_type IN ('text', 'character varying', 'bytea', 'uuid')
                """,
                Tables))
            .Select(r => (string)r[0]!)
            .Order(StringComparer.Ordinal)
            .ToList();

        string[] reviewed =
        [
            "llm_quota_counters.feature",            // 'ask' | 'cat'
            "llm_quota_counters.subject_kind",       // 'install' | 'account'
            "llm_quota_counters.subject_id",         // the one allowed subject id (quota is per subject)
            "llm_quota_counters.last_request_hash",  // SHA-256 of the request ULID, never the question
            "llm_spend_daily.feature",               // 'ask' | 'cat'
            "llm_spend_daily.provider_id",           // configured provider slug
            "llm_spend_daily.model",                 // configured model name
            "remote_config.key",                     // closed key set
            "remote_config.value",                   // typed, range-checked operator setting
            "remote_config.updated_by",              // operator id
            "llm_cat_answer_cache.merchant_norm",    // normalized merchant, backstop CHECK
            "llm_cat_answer_cache.category_code",    // category slug
            "llm_cat_answer_cache.provider_id",
            "llm_cat_answer_cache.prompt_version",
            "llm_cat_confirmations.id",              // row id (random)
            "llm_cat_confirmations.merchant_norm",
            "llm_cat_confirmations.category_code",
            "llm_cat_confirmations.source",
            "llm_cat_confirmations.install_hash",    // peppered HMAC, not joinable to installs
            "llm_cat_confirmations.status",
            "llm_cat_corrections.id",
            "llm_cat_corrections.merchant_norm",
            "llm_cat_corrections.ai_category",
            "llm_cat_corrections.user_category",
            "llm_cat_corrections.source",
            "llm_cat_corrections.install_hash",
            "llm_cat_corrections.status",
            "llm_cat_corrections.operator_id",       // the reviewing operator
        ];

        Assert.Equal(reviewed.Order(StringComparer.Ordinal), actual);

        // And by name: nothing named like a question, an install or account id, an IP or an app version, but subject_id.
        var named = (await Db.QueryAsync(
                fixture.Database.Superuser,
                """
                SELECT table_name || '.' || column_name FROM information_schema.columns
                WHERE table_schema = 'zaghlol' AND table_name = ANY($1)
                  AND (column_name ~ '(question|prompt_text|(^|_)q$|install_id|account_id|client|(^|_)ip(_|$)|app_version|version_name|body|text)')
                """,
                Tables))
            .Select(r => (string)r[0]!)
            .ToList();
        Assert.Empty(named);
    }

    public static TheoryData<string> BadMerchantNorms =>
    [
        "shop 123456",
        "acct 12 34 56",
        "acct 12-34-56",
        "acct 12/34/56",
        "فرع ١٢٣٤٥٦",
        "فرع ١٢ ٣٤ ٥٦",
        "فرع ١٢،٣٤،٥٦",
        "ref ۱۲۳۴۵۶",
        "ref １２３４５６",
        "name@bank",
        "a",
        new string('b', 65),
    ];

    /// <summary>AC 5, negative proof 2: the backstop rejects digit runs (any script, with separators), '@' and bad lengths.</summary>
    [Theory]
    [MemberData(nameof(BadMerchantNorms))]
    public async Task MerchantNormBackstopRejectsTheRowInAllThreeTables(string merchantNorm)
    {
        foreach (var (table, constraint) in new[]
                 {
                     ("llm_cat_answer_cache", "ck_llm_cat_answer_cache_merchant_norm"),
                     ("llm_cat_confirmations", "ck_llm_cat_confirmations_merchant_norm"),
                     ("llm_cat_corrections", "ck_llm_cat_corrections_merchant_norm"),
                 })
        {
            var error = await Assert.ThrowsAsync<PostgresException>(
                () => Rows.InsertAsync(fixture.Database, table, new Dictionary<string, object?> { ["merchant_norm"] = merchantNorm }));

            Assert.Equal(PostgresErrorCodes.CheckViolation, error.SqlState);
            Assert.Equal(constraint, error.ConstraintName);
        }
    }

    public static TheoryData<string> GoodMerchantNorms => ["carrefour maadi", "كارفور المعادي", "branch 12345", "7 eleven 2024", new string('c', 64), "ab"];

    [Theory]
    [MemberData(nameof(GoodMerchantNorms))]
    public async Task MerchantNormWithoutADigitRunIsAccepted(string merchantNorm)
    {
        foreach (var table in new[] { "llm_cat_answer_cache", "llm_cat_confirmations", "llm_cat_corrections" })
        {
            await Rows.InsertAsync(fixture.Database, table, new Dictionary<string, object?> { ["merchant_norm"] = merchantNorm });
        }
    }

    /// <summary>AC 6: the documented range edges are accepted (the out-of-range cases live in CheckConstraintTests).</summary>
    [Fact]
    public async Task RangeEdgesAreAccepted()
    {
        foreach (var month in new[] { 202601, 209912 })
        {
            await Rows.InsertAsync(fixture.Database, "llm_quota_counters", new Dictionary<string, object?> { ["month_key"] = month });
        }

        foreach (var confidence in new short[] { 0, 100 })
        {
            await Rows.InsertAsync(fixture.Database, "llm_cat_answer_cache", new Dictionary<string, object?> { ["confidence"] = confidence });
        }

        foreach (var feature in new[] { "ask", "cat" })
        {
            await Rows.InsertAsync(fixture.Database, "llm_spend_daily", new Dictionary<string, object?> { ["feature"] = feature });
        }

        foreach (var status in new[] { "open", "promoted", "rejected", "prompt_issue" })
        {
            await Rows.InsertAsync(fixture.Database, "llm_cat_corrections", new Dictionary<string, object?> { ["status"] = status });
        }
    }

    [Fact]
    public async Task OneConfirmationAndOneCorrectionPerMerchantAndInstallHash()
    {
        var hash = Rows.Bytes();
        var norm = "m" + Guid.NewGuid().ToString("N")[..12];
        foreach (var table in new[] { "llm_cat_confirmations", "llm_cat_corrections" })
        {
            var values = new Dictionary<string, object?> { ["merchant_norm"] = norm, ["install_hash"] = hash };
            await Rows.InsertAsync(fixture.Database, table, values);
            var error = await Assert.ThrowsAsync<PostgresException>(() => Rows.InsertAsync(fixture.Database, table, values));
            Assert.Equal(PostgresErrorCodes.UniqueViolation, error.SqlState);
        }
    }
}
