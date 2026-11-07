using Npgsql;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>
/// Test gaps G1-G3 of the round-1 test review: unique keys (23505), FK actions and orphans (23503), and single-column
/// support corrections that would break a pair CHECK.
/// </summary>
[Collection(SchemaGroup.Name)]
public class ConstraintBehaviourTests(SchemaFixture fixture)
{
    // table -> (key columns copied from the first row, expected constraint)
    private static readonly Dictionary<string, (string Table, string[] Key, string Constraint)> UniqueCases =
        new(StringComparer.Ordinal)
        {
            ["accounts (provider, provider_subject)"] = ("accounts", ["provider", "provider_subject"], "ux_accounts_provider_provider_subject"),
            ["purchases (store, store_key)"] = ("purchases", ["store", "store_key"], "ux_purchases_store_store_key"),
            ["store_notifications (store, external_id)"] = ("store_notifications", ["store", "external_id"], "ux_store_notifications_store_external_id"),
            ["app_attest_keys: one key per install"] = ("app_attest_keys", ["install_id"], "ux_app_attest_keys_install_id"),
            ["app_attest_keys primary key"] = ("app_attest_keys", ["key_id"], "pk_app_attest_keys"),
            ["catalog_merchants canonical"] = ("catalog_merchants", ["canonical"], "ux_catalog_merchants_canonical"),
            ["merchant_contributions: one vote per install"] = ("merchant_contributions", ["merchant_norm", "institution_code", "install_hash"], "ux_merchant_contributions_identity"),
            ["operators oidc_subject"] = ("operators", ["oidc_subject"], "ux_operators_oidc_subject"),
            ["seat_claimants primary key"] = ("seat_claimants", ["purchase_id", "install_id"], "pk_seat_claimants"),
            ["purchase_seats: one seat per purchase"] = ("purchase_seats", ["purchase_id"], "pk_purchase_seats"),
            ["idempotency_records primary key"] = ("idempotency_records", ["install_id", "operation_id", "idempotency_key"], "pk_idempotency_records"),
            ["replay_guard primary key"] = ("replay_guard", ["key_hash"], "pk_replay_guard"),
            ["bank_requests: one request per install"] = ("bank_requests", ["institution_name_norm", "country", "channel", "install_hash"], "pk_bank_requests"),
        };

    private static readonly string[] CategoryReferences =
        ["fk_catalog_merchants_catalog_categories_category_code", "fk_catalog_categories_catalog_categories_parent_code"];

    public static TheoryData<string> UniqueCaseNames => [.. UniqueCases.Keys];

    // An insert whose FK points nowhere.
    public static TheoryData<string, string, string> Orphans => new()
    {
        { "purchases", "install_id", "fk_purchases_installs_install_id" },
        { "purchase_seats", "purchase_id", "fk_purchase_seats_purchases_purchase_id" },
        { "purchase_seats", "install_id", "fk_purchase_seats_installs_install_id" },
        { "seat_claimants", "install_id", "fk_seat_claimants_installs_install_id" },
        { "app_attest_keys", "install_id", "fk_app_attest_keys_installs_install_id" },
        { "purchase_events", "purchase_id", "fk_purchase_events_purchases_purchase_id" },
    };

    [Theory]
    [MemberData(nameof(UniqueCaseNames))]
    public async Task ASecondRowWithTheSameKeyIsRejected(string name)
    {
        var (table, key, constraint) = UniqueCases[name];
        var first = await Rows.InsertAsync(fixture.Database, table);

        var error = await Assert.ThrowsAsync<PostgresException>(
            () => Rows.InsertAsync(fixture.Database, table, key.ToDictionary(c => c, c => first[c], StringComparer.Ordinal)));

        Assert.Equal(PostgresErrorCodes.UniqueViolation, error.SqlState);
        Assert.Equal(constraint, error.ConstraintName);
    }

    [Theory]
    [MemberData(nameof(Orphans))]
    public async Task AnOrphanRowIsRejected(string table, string column, string constraint)
    {
        var error = await Assert.ThrowsAsync<PostgresException>(() => Rows.InsertAsync(
            fixture.Database,
            table,
            new Dictionary<string, object?>(StringComparer.Ordinal) { [column] = Guid.CreateVersion7() }));

        Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, error.SqlState);
        Assert.Equal(constraint, error.ConstraintName);
    }

    [Fact]
    public async Task AMerchantNeedsAnExistingCategory()
    {
        var error = await Assert.ThrowsAsync<PostgresException>(() => Rows.InsertAsync(
            fixture.Database, "catalog_merchants", new Dictionary<string, object?> { ["category_code"] = "no_such_category" }));

        Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, error.SqlState);
        Assert.Equal("fk_catalog_merchants_catalog_categories_category_code", error.ConstraintName);
    }

    [Fact]
    public async Task DeletingAnAccountCascadesItsInstallLinks()
    {
        var database = fixture.Database;
        var account = await Rows.InsertAsync(database, "accounts");
        var install = await Rows.InsertAsync(database, "installs");
        await Db.InsertAsync(database.Api, "account_installs", new Dictionary<string, object?>
        {
            ["account_id"] = account["id"],
            ["install_id"] = install["id"],
        });

        await Db.ExecuteAsync(database.Api, "DELETE FROM zaghlol.accounts WHERE id = $1", account["id"]);

        Assert.Equal(0L, await Db.ScalarAsync(database.Superuser, "SELECT count(*) FROM zaghlol.account_installs WHERE account_id = $1", account["id"]));
        Assert.Equal(1L, await Db.ScalarAsync(database.Superuser, "SELECT count(*) FROM zaghlol.installs WHERE id = $1", install["id"]));
    }

    [Fact]
    public async Task ACatalogRowStillReferencedCannotBeDeleted()
    {
        // NO ACTION FKs. The owner runs the deletes, so only the FK (not a missing grant) can stop them.
        var database = fixture.Database;
        var merchant = await Rows.InsertAsync(database, "catalog_merchants");
        var category = (string)merchant["category_code"]!;
        var child = Rows.Base("catalog_categories");
        child["parent_code"] = category;
        await Db.InsertAsync(database.Admin, "catalog_categories", child);
        var merchantId = (int)(await Db.ScalarAsync(database.Superuser, "SELECT id FROM zaghlol.catalog_merchants WHERE canonical = $1", merchant["canonical"]))!;
        await Db.InsertAsync(database.Admin, "catalog_aliases", new Dictionary<string, object?>
        {
            ["merchant_id"] = merchantId,
            ["alias_norm"] = "alias " + Guid.NewGuid().ToString("N")[..8],
            ["match"] = "exact",
            ["version"] = 1,
        });

        var categoryDelete = await Assert.ThrowsAsync<PostgresException>(() => Db.ExecuteAsync(
            database.Migrator, "DELETE FROM zaghlol.catalog_categories WHERE code = $1", category));
        var merchantDelete = await Assert.ThrowsAsync<PostgresException>(() => Db.ExecuteAsync(
            database.Migrator, "DELETE FROM zaghlol.catalog_merchants WHERE id = $1", merchantId));

        Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, categoryDelete.SqlState);
        Assert.Contains(categoryDelete.ConstraintName, CategoryReferences);
        Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, merchantDelete.SqlState);
        Assert.Equal("fk_catalog_aliases_catalog_merchants_merchant_id", merchantDelete.ConstraintName);
    }

    [Fact]
    public async Task ACategoryWithAChildCategoryCannotBeDeleted()
    {
        var database = fixture.Database;
        var parent = await Rows.InsertAsync(database, "catalog_categories");
        var child = Rows.Base("catalog_categories");
        child["parent_code"] = parent["code"];
        await Db.InsertAsync(database.Admin, "catalog_categories", child);

        var error = await Assert.ThrowsAsync<PostgresException>(() => Db.ExecuteAsync(
            database.Migrator, "DELETE FROM zaghlol.catalog_categories WHERE code = $1", parent["code"]));

        Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, error.SqlState);
        Assert.Equal("fk_catalog_categories_catalog_categories_parent_code", error.ConstraintName);
    }

    [Fact]
    public async Task ASupportDetachMustClearTheLinkAndItsSourceTogether()
    {
        var database = fixture.Database;
        var purchase = await Rows.InsertAsync(database, "purchases", new Dictionary<string, object?>
        {
            ["account_id"] = new Ref("accounts"),
            ["account_linked_by"] = "support",
        });

        var half = await Assert.ThrowsAsync<PostgresException>(() => Db.ExecuteAsync(
            database.Admin, "UPDATE zaghlol.purchases SET account_linked_by = NULL WHERE id = $1", purchase["id"]));
        var otherHalf = await Assert.ThrowsAsync<PostgresException>(() => Db.ExecuteAsync(
            database.Admin, "UPDATE zaghlol.purchases SET account_id = NULL WHERE id = $1", purchase["id"]));

        Assert.Equal("ck_purchases_account_link_pair", half.ConstraintName);
        Assert.Equal("ck_purchases_account_link_pair", otherHalf.ConstraintName);
        Assert.Equal(1, await Db.ExecuteAsync(
            database.Admin, "UPDATE zaghlol.purchases SET account_id = NULL, account_linked_by = NULL WHERE id = $1", purchase["id"]));
    }

    [Fact]
    public async Task ASupportSeatMoveMustKeepTheSeatPairsConsistent()
    {
        var database = fixture.Database;
        var seat = await Rows.InsertAsync(database, "purchase_seats", new Dictionary<string, object?>
        {
            ["last_moved_at"] = Rows.Now(),
            ["next_move_at"] = Rows.WholeHour(),
        });
        var id = seat["purchase_id"];

        var moveTimes = await Assert.ThrowsAsync<PostgresException>(() => Db.ExecuteAsync(
            database.Admin, "UPDATE zaghlol.purchase_seats SET next_move_at = NULL WHERE purchase_id = $1", id));
        var holder = await Assert.ThrowsAsync<PostgresException>(() => Db.ExecuteAsync(
            database.Admin, "UPDATE zaghlol.purchase_seats SET install_id = NULL WHERE purchase_id = $1", id));

        Assert.Equal("ck_purchase_seats_move_pair", moveTimes.ConstraintName);
        Assert.Equal("ck_purchase_seats_holder_proof", holder.ConstraintName);
        Assert.Equal(1, await Db.ExecuteAsync(
            database.Admin,
            "UPDATE zaghlol.purchase_seats SET install_id = NULL, proof = NULL, bound_at = NULL, last_moved_at = NULL, next_move_at = NULL WHERE purchase_id = $1",
            id));
    }

    [Fact]
    public async Task DeletingAnInstallLeavesOtherSeatsAndInstallsUntouched()
    {
        var database = fixture.Database;
        var gone = await Rows.InsertAsync(database, "installs");
        var stays = await Rows.InsertAsync(database, "purchase_seats");
        await Rows.InsertAsync(database, "purchase_seats", new Dictionary<string, object?> { ["install_id"] = gone["id"] });

        Assert.Equal(1, await Db.ExecuteAsync(database.Worker, "DELETE FROM zaghlol.installs WHERE id = $1", gone["id"]));

        Assert.Equal(stays["install_id"], await Db.ScalarAsync(
            database.Superuser, "SELECT install_id FROM zaghlol.purchase_seats WHERE purchase_id = $1", stays["purchase_id"]));
    }

    [Fact]
    public async Task DeletingAnInstallWithoutASeatSucceeds()
    {
        var install = await Rows.InsertAsync(fixture.Database, "installs");

        Assert.Equal(1, await Db.ExecuteAsync(fixture.Database.Worker, "DELETE FROM zaghlol.installs WHERE id = $1", install["id"]));
    }
}
