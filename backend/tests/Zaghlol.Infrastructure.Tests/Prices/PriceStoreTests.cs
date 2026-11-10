using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Zaghlol.Application.Prices;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Prices;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Prices;

/// <summary>A migrated database of its own and the price stores on the Worker, Admin and App logins, built the way the hosts build them.</summary>
public sealed class PriceStoreFixture : IAsyncLifetime
{
    private ServiceProvider? services;

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public IServiceProvider Services => services!;

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:App"] = Database.Api,
                ["ConnectionStrings:Admin"] = Database.Admin,
                ["ConnectionStrings:Worker"] = Database.Worker,
            })
            .Build();
        var collection = new ServiceCollection();
        collection.AddLogging();
        collection.AddSingleton(TimeProvider.System);
        collection.AddSingleton<IConfiguration>(configuration);
        collection.AddZaghlolDatabase(DatabaseRole.App, DatabaseRole.Admin, DatabaseRole.Worker);
        collection.AddZaghlolPrices();
        collection.AddZaghlolPriceWorker();
        services = collection.BuildServiceProvider();
    }

    public async Task DisposeAsync()
    {
        if (services is not null)
        {
            await services.DisposeAsync();
        }

        if (Database is not null)
        {
            await Database.DisposeAsync();
        }
    }

    public async Task<Guid> NewOperatorAsync()
    {
        var id = Guid.NewGuid();
        await Db.ExecuteAsync(
            Database.Migrator,
            "INSERT INTO zaghlol.operators (id, oidc_subject, display_name, roles) VALUES ($1, $2, $3, ARRAY['prices_admin'])",
            id,
            "sub-" + id,
            "Test operator");
        return id;
    }
}

/// <summary>T-127: the price stores against PostgreSQL (feed upsert vs override, audit, grants, CHECKs, numeric precision).</summary>
public class PriceStoreTests(PriceStoreFixture fixture) : IClassFixture<PriceStoreFixture>
{
    private static readonly DateTimeOffset T0 = new(2026, 11, 10, 9, 0, 0, TimeSpan.Zero);

    private IPriceFeedStore Feed => fixture.Services.GetRequiredService<IPriceFeedStore>();

    private IPriceAdminStore Admin => fixture.Services.GetRequiredService<IPriceAdminStore>();

    private IPriceReader Reader => fixture.Services.GetRequiredService<IPriceReader>();

    private static NormalizedPrices Prices(decimal gold24Egp, decimal usdEgp = 50m, string source = "fake") =>
        PriceNormalizer.Normalize([(source, new ProviderSnapshot([new GoldQuote("XAU24_G", "EGP", gold24Egp)], [new FxQuote("EGP", usdEgp), new FxQuote("SAR", 3.75m)], T0))]);

    private async Task<PriceRow> RowAsync(string symbol, string currency) =>
        (await Reader.ListGoldAsync(CancellationToken.None)).Single(r => r.Symbol == symbol && r.Currency == currency);

    // The tables are shared by the tests of this class, so each test starts from an empty cache.
    private async Task ResetAsync()
    {
        await Db.ExecuteAsync(fixture.Database.Superuser, "DELETE FROM zaghlol.price_quotes");
        await Db.ExecuteAsync(fixture.Database.Superuser, "DELETE FROM zaghlol.fx_rates");
    }

    [Fact]
    public async Task TheWorkerWritesDecimalPricesAndTheAppLoginReadsThemBack()
    {
        await ResetAsync();

        await Feed.ApplyFeedAsync(Prices(4821.37m), T0, CancellationToken.None);

        var gold = await Reader.ListGoldAsync(CancellationToken.None);
        Assert.Equal(6, gold.Count);
        var k21 = await RowAsync("XAU21_G", "EGP");
        Assert.Equal(4218.70m, k21.Price);
        Assert.Equal(4218.70m, k21.FeedPrice);
        Assert.Equal(T0, k21.AsOf);
        Assert.Equal(T0, k21.FeedAsOf);
        Assert.False(k21.IsOverride);
        Assert.Null(k21.OverrideExpiresAt);
        Assert.Equal("fake+derived", k21.Source);
        var fx = await Reader.ListFxAsync(CancellationToken.None);
        Assert.Equal(50m, fx.Single(f => f.Quote == "EGP").Rate);
        Assert.Equal(["EGP", "SAR"], fx.Select(f => f.Quote).Order());
    }

    [Fact]
    public async Task ASecondRunReplacesTheQuotesInPlace()
    {
        await ResetAsync();
        await Feed.ApplyFeedAsync(Prices(4800m), T0, CancellationToken.None);

        await Feed.ApplyFeedAsync(Prices(4900m, 51m), T0.AddHours(1), CancellationToken.None);

        var k24 = await RowAsync("XAU24_G", "EGP");
        Assert.Equal(4900m, k24.Price);
        Assert.Equal(T0.AddHours(1), k24.AsOf);
        Assert.Equal(6, (await Reader.ListGoldAsync(CancellationToken.None)).Count);
        Assert.Equal(51m, (await Reader.ListFxAsync(CancellationToken.None)).Single(f => f.Quote == "EGP").Rate);
        Assert.Equal(T0.AddHours(1), (await Feed.FeedTimesAsync(CancellationToken.None))["XAU24_G"]);
    }

    [Fact]
    public async Task AnOverrideSurvivesFeedRunsUntilItExpiresAndTheFeedValueIsKept()
    {
        await ResetAsync();
        var op = await fixture.NewOperatorAsync();
        await Feed.ApplyFeedAsync(Prices(4800m), T0, CancellationToken.None);

        var set = await Admin.SetOverrideAsync("XAU21_G", "EGP", 4300.5m, "Feed outage", T0, T0.AddHours(24), op, CancellationToken.None);
        await Feed.ApplyFeedAsync(Prices(4880m), T0.AddHours(1), CancellationToken.None);
        var during = await RowAsync("XAU21_G", "EGP");

        Assert.Equal(4300.5m, set.Price);
        Assert.True(during.IsOverride);
        Assert.Equal(4300.5m, during.Price);
        Assert.Equal(T0, during.AsOf);
        Assert.Equal(T0.AddHours(24), during.OverrideExpiresAt);
        Assert.Equal(4270.00m, during.FeedPrice);
        Assert.Equal(T0.AddHours(1), during.FeedAsOf);
        Assert.Equal(4300.5m, during.Effective(T0.AddHours(2))!.Price);
        Assert.Equal(4270.00m, during.Effective(T0.AddHours(24))!.Price);

        // After expiry the next feed run clears the override flag and the row is the feed again.
        await Feed.ApplyFeedAsync(Prices(4900m), T0.AddHours(25), CancellationToken.None);
        var after = await RowAsync("XAU21_G", "EGP");
        Assert.False(after.IsOverride);
        Assert.Null(after.OverrideExpiresAt);
        Assert.Equal(4287.50m, after.Price);
        Assert.Equal("fake+derived", after.Source);
    }

    [Fact]
    public async Task AnOverrideOnAQuoteWithoutAFeedValueIsStoredAndExpiresToNothing()
    {
        await ResetAsync();
        var op = await fixture.NewOperatorAsync();

        var set = await Admin.SetOverrideAsync("XAU18_G", "USD", 70m, "Manual quote", T0, T0.AddHours(24), op, CancellationToken.None);

        Assert.Null(set.FeedPrice);
        Assert.Equal(70m, set.Effective(T0.AddHours(1))!.Price);
        Assert.Null(set.Effective(T0.AddHours(25)));
    }

    [Fact]
    public async Task AnOverrideOverANonOverrideRowFromBeforeFeedColumnsKeepsItAsTheFeedValue()
    {
        await ResetAsync();
        var op = await fixture.NewOperatorAsync();
        await Db.ExecuteAsync(
            fixture.Database.Superuser,
            "INSERT INTO zaghlol.price_quotes (symbol, currency, price, per_unit, as_of, source, is_override) VALUES ('XAU24_G', 'EGP', 4700, 'gram', $1, 'old', false)",
            T0);

        var set = await Admin.SetOverrideAsync("XAU24_G", "EGP", 4750m, "Manual quote", T0.AddHours(1), T0.AddHours(5), op, CancellationToken.None);

        Assert.Equal(4700m, set.FeedPrice);
        Assert.Equal(T0, set.FeedAsOf);
        Assert.Equal(4700m, set.Effective(T0.AddHours(6))!.Price);
    }

    [Fact]
    public async Task ASecondOverrideReplacesTheFirstAndKeepsTheFeedValue()
    {
        await ResetAsync();
        var op = await fixture.NewOperatorAsync();
        await Feed.ApplyFeedAsync(Prices(4800m), T0, CancellationToken.None);
        await Admin.SetOverrideAsync("XAU24_G", "EGP", 4900m, "First", T0, T0.AddHours(24), op, CancellationToken.None);

        var second = await Admin.SetOverrideAsync("XAU24_G", "EGP", 4950m, "Second", T0.AddHours(1), T0.AddHours(30), op, CancellationToken.None);

        Assert.Equal(4950m, second.Price);
        Assert.Equal(T0.AddHours(30), second.OverrideExpiresAt);
        Assert.Equal(4800m, second.FeedPrice);
    }

    [Fact]
    public async Task ClearingEndsAnActiveOverrideAtOnceAndWritesAnAuditRow()
    {
        await ResetAsync();
        var op = await fixture.NewOperatorAsync();
        await Feed.ApplyFeedAsync(Prices(4800m), T0, CancellationToken.None);
        await Admin.SetOverrideAsync("XAU24_G", "EGP", 4900m, "Wrong feed", T0, T0.AddHours(24), op, CancellationToken.None);

        var cleared = await Admin.ClearOverrideAsync("XAU24_G", "EGP", T0.AddHours(1), op, CancellationToken.None);
        var again = await Admin.ClearOverrideAsync("XAU24_G", "EGP", T0.AddHours(1), op, CancellationToken.None);

        Assert.True(cleared);
        Assert.False(again);
        var row = await RowAsync("XAU24_G", "EGP");
        Assert.False(row.OverrideActive(T0.AddHours(1)));
        Assert.Equal(4800m, row.Effective(T0.AddHours(1))!.Price);
        var actions = await Db.QueryAsync(fixture.Database.Superuser, "SELECT action FROM zaghlol.audit_log WHERE operator_id = $1 ORDER BY id", op);
        Assert.Equal(["price_override", "price_override_clear"], actions.Select(a => (string)a[0]!));
    }

    [Fact]
    public async Task ClearingAnOverrideWithNoFeedValueLeavesNothingToServe()
    {
        await ResetAsync();
        var op = await fixture.NewOperatorAsync();
        await Admin.SetOverrideAsync("XAU18_G", "USD", 70m, "Manual quote", T0, T0.AddHours(24), op, CancellationToken.None);

        Assert.True(await Admin.ClearOverrideAsync("XAU18_G", "USD", T0.AddHours(1), op, CancellationToken.None));

        Assert.Null((await RowAsync("XAU18_G", "USD")).Effective(T0.AddHours(1)));
    }

    [Fact]
    public async Task EachOverrideWritesExactlyOneAuditRowWithTheDocumentedDetails()
    {
        await ResetAsync();
        var op = await fixture.NewOperatorAsync();

        await Admin.SetOverrideAsync("XAU21_G", "EGP", 4217.5m, "Feed outage, dealer quote", T0, T0.AddHours(24), op, CancellationToken.None);

        var rows = await Db.QueryAsync(
            fixture.Database.Superuser,
            "SELECT action, target, details::text FROM zaghlol.audit_log WHERE operator_id = $1",
            op);
        var row = Assert.Single(rows);
        Assert.Equal("price_override", (string)row[0]!);
        Assert.Equal("price:XAU21_G:EGP", (string)row[1]!);
        var details = (string)row[2]!;
        Assert.Contains("\"price\": \"4217.50\"", details, StringComparison.Ordinal);
        Assert.Contains("\"expires_at\": \"2026-11-11T09:00:00Z\"", details, StringComparison.Ordinal);
        Assert.Contains("\"reason\": \"Feed outage, dealer quote\"", details, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AnUnknownOperatorRollsTheOverrideBack()
    {
        await ResetAsync();

        await Assert.ThrowsAsync<PostgresException>(() =>
            Admin.SetOverrideAsync("XAU21_G", "EGP", 1m, "Rollback probe", T0, T0.AddHours(1), Guid.NewGuid(), CancellationToken.None));

        Assert.Empty(await Reader.ListGoldAsync(CancellationToken.None));
    }

    [Fact]
    public async Task PricesKeepTheirDecimalsAtTheStoredPrecision()
    {
        await ResetAsync();
        var op = await fixture.NewOperatorAsync();

        var set = await Admin.SetOverrideAsync("XAU24_G", "EGP", 123456789012.123456m, "Precision probe", T0, T0.AddHours(1), op, CancellationToken.None);

        Assert.Equal(123456789012.123456m, set.Price);
    }

    [Fact]
    public async Task TheAppLoginCannotWritePricesAndTheWorkerCannotWriteAudit()
    {
        var op = await fixture.NewOperatorAsync();
        var appWrite = await Assert.ThrowsAsync<PostgresException>(() =>
            Db.ExecuteAsync(fixture.Database.Api, "UPDATE zaghlol.price_quotes SET price = 1"));
        var fxWrite = await Assert.ThrowsAsync<PostgresException>(() =>
            Db.ExecuteAsync(fixture.Database.Api, "DELETE FROM zaghlol.fx_rates"));
        var workerAudit = await Assert.ThrowsAsync<PostgresException>(() =>
            Db.ExecuteAsync(
                fixture.Database.Worker,
                "INSERT INTO zaghlol.audit_log (operator_id, action, target, details) VALUES ($1, 'price_override', 'price:X:Y', '{}')",
                op));
        var adminFx = await Assert.ThrowsAsync<PostgresException>(() =>
            Db.ExecuteAsync(fixture.Database.Admin, "DELETE FROM zaghlol.fx_rates"));

        Assert.All([appWrite, fxWrite, workerAudit, adminFx], e => Assert.Equal("42501", e.SqlState));
    }

    [Fact]
    public async Task APriceCheckViolationNeverReachesTheDatabaseFromTheService()
    {
        // The service validates first (positive price, '@'-free reason); the CHECKs are only the backstop.
        var op = await fixture.NewOperatorAsync();
        var service = fixture.Services.GetRequiredService<PriceOverrideService>();

        var zero = await service.SetAsync(new PriceOverrideInput("XAU24_G", "EGP", "0", "Zero price", null), op, CancellationToken.None);
        var mail = await service.SetAsync(new PriceOverrideInput("XAU24_G", "EGP", "10", "ask a@b.c", null), op, CancellationToken.None);

        Assert.True(zero.Invalid);
        Assert.True(mail.Invalid);
    }
}
