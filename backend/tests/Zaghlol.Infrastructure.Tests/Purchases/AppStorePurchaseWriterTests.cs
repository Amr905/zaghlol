using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Purchases;

namespace Zaghlol.Infrastructure.Tests.Purchases;

/// <summary>
/// T-131 §3 step 6 and §4 against PostgreSQL 17 (migration <c>PurchaseLastPaymentAt</c>): App Store upserts on the App login, the
/// new-payment rule on <c>last_payment_at</c> (once, also under concurrency, independent of the monotonic guard), the re-plan of an
/// upgraded row, a refund keeping the stored expiry, and the grants (only <c>app_rw</c> may advance the marker).
/// </summary>
public class AppStorePurchaseWriterTests(PurchaseStoreFixture fixture) : IClassFixture<PurchaseStoreFixture>
{
    private static readonly DateTimeOffset Now = new(2026, 11, 11, 12, 0, 0, TimeSpan.Zero);

    private PurchaseWriter Writer => fixture.Services.GetRequiredService<PurchaseWriter>();

    [Fact]
    public async Task AFirstPurchaseIsANewPaymentAndItsReVerifyIsNot()
    {
        var install = await InstallAsync();
        var original = Original();

        var first = await Writer.UpsertAsync(Upsert(original, install, Now, paidAt: Now.AddMinutes(-1)), "verify", CancellationToken.None);
        var again = await Writer.UpsertAsync(Upsert(original, install, Now.AddMinutes(1), paidAt: Now.AddMinutes(-1)), "verify", CancellationToken.None);

        Assert.True(first.Inserted);
        Assert.True(first.IsNewPayment);
        Assert.False(again.Inserted);
        Assert.False(again.IsNewPayment);
        var row = await RowAsync(original);
        Assert.Equal(Now.AddMinutes(-1), row.LastPaymentAt);
        Assert.True(row.Acknowledged);
        Assert.Equal("app_store", row.Store);
    }

    [Fact]
    public async Task ALaterPurchaseAdvancesOnceAnOlderOneOrNoneNeverAndTheGuardDoesNotMatter()
    {
        var install = await InstallAsync();
        var original = Original();
        await Writer.UpsertAsync(Upsert(original, install, Now, paidAt: Now), "verify", CancellationToken.None);

        // A newer row read already stored (an RTDN-like later read): the guard skips the state update, but the payment still counts.
        var stale = await Writer.UpsertAsync(Upsert(original, install, Now.AddMinutes(-5), paidAt: Now.AddMinutes(10)), "verify", CancellationToken.None);
        var older = await Writer.UpsertAsync(Upsert(original, install, Now.AddMinutes(1), paidAt: Now.AddDays(-30)), "verify", CancellationToken.None);
        var none = await Writer.UpsertAsync(Upsert(original, install, Now.AddMinutes(2), paidAt: null), "verify", CancellationToken.None);

        Assert.False(stale.Applied);
        Assert.True(stale.IsNewPayment);
        Assert.False(older.IsNewPayment);
        Assert.False(none.IsNewPayment);
        Assert.Equal(Now.AddMinutes(10), (await RowAsync(original)).LastPaymentAt);
    }

    [Fact]
    public async Task ConcurrentVerifiesOfOneUpgradeFlagItExactlyOnce()
    {
        var install = await InstallAsync();
        var original = Original();
        await Writer.UpsertAsync(Upsert(original, install, Now, paidAt: Now), "verify", CancellationToken.None);

        var results = await Task.WhenAll(Enumerable.Range(0, 12).Select(i =>
            Writer.UpsertAsync(Upsert(original, install, Now.AddSeconds(i + 1), paidAt: Now.AddMinutes(3)), "verify", CancellationToken.None)));

        Assert.Equal(1, results.Count(r => r.IsNewPayment));
    }

    [Fact]
    public async Task ConcurrentFirstVerifiesMakeOneRowAndOneNewPayment()
    {
        var install = await InstallAsync();
        var original = Original();

        var results = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ =>
            Writer.UpsertAsync(Upsert(original, install, Now, paidAt: Now), "verify", CancellationToken.None)));

        Assert.Single(results.Select(r => r.PurchaseId).Distinct());
        Assert.Equal(1, results.Count(r => r.Inserted));
        Assert.Equal(1, results.Count(r => r.IsNewPayment));
    }

    [Fact]
    public async Task AnUpgradeRePlansTheAppleRowAndARefundKeepsTheStoredExpiry()
    {
        var install = await InstallAsync();
        var original = Original();
        await Writer.UpsertAsync(Upsert(original, install, Now, product: "zaghlol_gold_monthly", plan: GoldPlan.Monthly), "verify", CancellationToken.None);
        await Writer.UpsertAsync(Upsert(original, install, Now.AddMinutes(1), expires: Now.AddDays(365)), "verify", CancellationToken.None);

        var upgraded = await RowAsync(original);
        Assert.Equal("zaghlol_gold_yearly", upgraded.Product);
        Assert.Equal("yearly", upgraded.Plan);

        var refund = Upsert(original, install, Now.AddMinutes(2), state: StoredPurchaseState.Refunded, expires: Now.AddDays(999)) with { KeepStoredExpiry = true };
        var result = await Writer.UpsertAsync(refund, "verify", CancellationToken.None);

        Assert.Equal(StoredPurchaseState.Refunded, result.State);
        Assert.Equal(Now.AddDays(365), result.ExpiresAt);
        Assert.Equal(Now.AddDays(365), (await RowAsync(original)).ExpiresAt);
    }

    [Fact]
    public async Task AGoogleRowNeverChangesItsProductOnUpdate()
    {
        var install = await InstallAsync();
        var token = "tok." + Guid.NewGuid().ToString("N");
        var google = Upsert(token, install, Now) with { Store = PurchaseStore.GooglePlay, ProductId = "zaghlol_gold_monthly", Plan = GoldPlan.Monthly };
        await Writer.UpsertAsync(google, "verify", CancellationToken.None);
        await Writer.UpsertAsync(google with { ProductId = "zaghlol_gold_yearly", Plan = GoldPlan.Yearly, ReadAt = Now.AddMinutes(1) }, "verify", CancellationToken.None);

        Assert.Equal("monthly", (await RowAsync(token)).Plan);
    }

    [Fact]
    public async Task OnlyTheAppLoginMayAdvanceTheNewPaymentMarker()
    {
        var install = await InstallAsync();
        var original = Original();
        var id = (await Writer.UpsertAsync(Upsert(original, install, Now), "verify", CancellationToken.None)).PurchaseId;

        await using var worker = new NpgsqlConnection(fixture.Database.Worker);
        await worker.OpenAsync();
        await using var update = new NpgsqlCommand("UPDATE zaghlol.purchases SET last_payment_at = now() WHERE id = @id", worker);
        update.Parameters.AddWithValue("id", id);
        var denied = await Assert.ThrowsAsync<PostgresException>(() => update.ExecuteNonQueryAsync());
        Assert.Equal(PostgresErrorCodes.InsufficientPrivilege, denied.SqlState);

        await using var opsRo = new NpgsqlConnection(fixture.Database.OpsRo);
        await opsRo.OpenAsync();
        await using var read = new NpgsqlCommand("SELECT last_payment_at FROM zaghlol.purchases WHERE id = @id", opsRo);
        read.Parameters.AddWithValue("id", id);
        Assert.Equal(PostgresErrorCodes.InsufficientPrivilege, (await Assert.ThrowsAsync<PostgresException>(() => read.ExecuteScalarAsync())).SqlState);
    }

    private static string Original() => "2" + Random.Shared.NextInt64(100000000000000, 999999999999999).ToString(System.Globalization.CultureInfo.InvariantCulture);

    private static PurchaseUpsert Upsert(
        string original,
        InstallId install,
        DateTimeOffset readAt,
        DateTimeOffset? paidAt = null,
        string product = "zaghlol_gold_yearly",
        GoldPlan plan = GoldPlan.Yearly,
        StoredPurchaseState state = StoredPurchaseState.Active,
        DateTimeOffset? expires = null) => new(
        PurchaseStore.AppStore,
        product,
        plan,
        new Sensitive<string>(original),
        null,
        install,
        state,
        expires ?? Now.AddDays(30),
        true,
        PurchaseEnvironment.Production,
        StoreBindingRef.Compute(install),
        readAt,
        NewPaymentAt: paidAt);

    private async Task<InstallId> InstallAsync()
    {
        var id = Guid.NewGuid();
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("INSERT INTO zaghlol.installs (id, token_hash, platform, app_version) VALUES (@id, @hash, 'ios', '1.0.0')", connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("hash", System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));
        await command.ExecuteNonQueryAsync();
        return InstallId.FromGuid(id);
    }

    private async Task<(string Store, string Product, string Plan, bool Acknowledged, DateTimeOffset? ExpiresAt, DateTimeOffset? LastPaymentAt)> RowAsync(string key)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "SELECT store, product_id, plan, acknowledged, expires_at, last_payment_at FROM zaghlol.purchases WHERE store_key = @k", connection);
        command.Parameters.AddWithValue("k", key);
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        return (
            reader.GetString(0),
            reader.GetString(1),
            reader.GetString(2),
            reader.GetBoolean(3),
            reader.IsDBNull(4) ? null : reader.GetFieldValue<DateTimeOffset>(4),
            reader.IsDBNull(5) ? null : reader.GetFieldValue<DateTimeOffset>(5));
    }
}
