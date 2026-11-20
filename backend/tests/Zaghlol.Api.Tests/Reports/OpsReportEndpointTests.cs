using System.Globalization;
using System.Net;
using System.Text.Json;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Tests.Flags;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Reports;

/// <summary>
/// BUG-003: <c>GET /admin/v1/bank-requests</c> (<c>catalog_editor</c>) and <c>GET /admin/v1/metrics/daily-active</c> (any operator
/// role) through the real pipeline: roles, shape, ordering, the 500 cap, zero days and <c>days</c> validation (QA cases API-127/128).
/// </summary>
[Collection(ApiHostGroup.Name)]
public class OpsReportEndpointTests(AdminFlagFixture fixture) : IClassFixture<AdminFlagFixture>
{
    private const string BankRequests = "/admin/v1/bank-requests";
    private const string DailyActive = "/admin/v1/metrics/daily-active";

    private static string Unique(string prefix) =>
        prefix + " " + string.Concat(Guid.NewGuid().ToByteArray().Take(8).Select(b => (char)('a' + (b % 26))));

    private Task SeedBankRequestsAsync(string name, string country, string channel, int installs, DateTimeOffset lastAt) =>
        ZaghlolTestDatabase.ExecuteAsync(
            fixture.Database.Migrator,
            string.Create(
                CultureInfo.InvariantCulture,
                $"""
                INSERT INTO zaghlol.bank_requests (institution_name_norm, country, channel, install_hash, received_at)
                SELECT '{name}', '{country}', '{channel}', decode(md5(g::text || '{name}') || md5('{channel}' || g::text), 'hex'),
                       TIMESTAMPTZ '{lastAt:yyyy-MM-dd'T'HH:mm:ss'Z'}' - (g - 1) * interval '1 hour'
                FROM generate_series(1, {installs}) AS g
                """));

    private Task SeedDailyAsync(DateOnly day, string platform, string version, int installs) =>
        ZaghlolTestDatabase.ExecuteAsync(
            fixture.Database.Migrator,
            string.Create(
                CultureInfo.InvariantCulture,
                $"INSERT INTO zaghlol.daily_active_counts (day, platform, app_version, installs) VALUES ('{day:yyyy-MM-dd}', '{platform}', '{version}', {installs})"));

    private async Task<JsonDocument> GetJsonAsync(string path, string token)
    {
        using var response = await fixture.SendAsync(HttpMethod.Get, path, token);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.NoStore);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);
        return JsonDocument.Parse(await response.Content.ReadAsStringAsync());
    }

    // ---- authentication and roles --------------------------------------------------------------------------------------

    [Theory]
    [InlineData(BankRequests)]
    [InlineData(DailyActive)]
    public async Task WithoutATokenOrWithAnInstallTokenItIs401(string path)
    {
        using var none = await fixture.SendAsync(HttpMethod.Get, path, token: null);
        using var junk = await fixture.SendAsync(HttpMethod.Get, path, "not-an-operator-token");

        await Installs.Problems.AssertAsync(none, HttpStatusCode.Unauthorized, "UNAUTHORIZED");
        await Installs.Problems.AssertAsync(junk, HttpStatusCode.Unauthorized, "UNAUTHORIZED");
    }

    [Fact]
    public async Task BankRequestsNeedTheCatalogEditorRole()
    {
        foreach (var role in OperatorRoles.All.Where(r => r != OperatorRoles.CatalogEditor))
        {
            var (_, token) = await fixture.NewOperatorAsync(role);
            using var response = await fixture.SendAsync(HttpMethod.Get, BankRequests, token);
            await Installs.Problems.AssertAsync(response, HttpStatusCode.Forbidden, "FORBIDDEN");
        }

        var (_, editor) = await fixture.NewOperatorAsync(OperatorRoles.CatalogEditor);
        using var ok = await fixture.SendAsync(HttpMethod.Get, BankRequests, editor);
        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
    }

    [Fact]
    public async Task DailyActiveAcceptsEveryKnownRoleAndRefusesATokenWithNoKnownRole()
    {
        foreach (var role in OperatorRoles.All)
        {
            var (_, token) = await fixture.NewOperatorAsync(role);
            using var response = await fixture.SendAsync(HttpMethod.Get, DailyActive, token);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        }

        var (_, nobody) = await fixture.NewOperatorAsync("bogus_role");
        using var forbidden = await fixture.SendAsync(HttpMethod.Get, DailyActive, nobody);
        await Installs.Problems.AssertAsync(forbidden, HttpStatusCode.Forbidden, "FORBIDDEN");
    }

    // ---- bank requests -------------------------------------------------------------------------------------------------

    [Fact]
    public async Task TheRankingIsByDistinctInstallsThenLastRequestAndShowsNoInstallData()
    {
        var now = DateTimeOffset.UtcNow;
        var (a, b, c, d) = (Unique("rank a"), Unique("rank b"), Unique("rank c"), Unique("rank d"));
        await SeedBankRequestsAsync(a, "EG", "sms", 3, now.AddDays(-5));
        await SeedBankRequestsAsync(b, "EG", "notification", 5, now.AddDays(-9));
        await SeedBankRequestsAsync(c, "SA", "sms", 3, now.AddDays(-1)); // ties a on count, requested more recently
        await SeedBankRequestsAsync(d, "EG", "sms", 2, now);
        await SeedBankRequestsAsync(d, "EG", "notification", 2, now); // same name, other channel: a separate entry
        var (_, token) = await fixture.NewOperatorAsync(OperatorRoles.CatalogEditor);

        using var json = await GetJsonAsync(BankRequests, token);

        var items = json.RootElement.GetProperty("items").EnumerateArray().ToList();
        var mine = items.Where(i => new[] { a, b, c, d }.Contains(i.GetProperty("institutionName").GetString())).ToList();
        Assert.Equal(
            [(b, "EG", "notification", 5), (c, "SA", "sms", 3), (a, "EG", "sms", 3), (d, "EG", "notification", 2), (d, "EG", "sms", 2)],
            mine.Select(i => (i.GetProperty("institutionName").GetString()!, i.GetProperty("country").GetString()!, i.GetProperty("channel").GetString()!, i.GetProperty("count").GetInt32())));
        foreach (var item in items)
        {
            Assert.Equal(["channel", "count", "country", "institutionName", "lastRequestedAt"], item.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal));
            Assert.Matches(@"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", item.GetProperty("lastRequestedAt").GetString());
            Assert.True(item.GetProperty("count").GetInt32() >= 1);
        }

        var firstOfA = mine.Single(i => i.GetProperty("institutionName").GetString() == a);
        Assert.Equal(now.AddDays(-5).UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture), firstOfA.GetProperty("lastRequestedAt").GetString());
        Assert.DoesNotContain("install", json.RootElement.GetRawText().Replace("institutionName", string.Empty, StringComparison.Ordinal), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task TheRankingIsCappedAt500()
    {
        await ZaghlolTestDatabase.ExecuteAsync(
            fixture.Database.Migrator,
            """
            INSERT INTO zaghlol.bank_requests (institution_name_norm, country, channel, install_hash)
            SELECT 'capname ' || chr(97 + g % 26) || chr(97 + (g / 26) % 26) || chr(97 + (g / 676) % 26), 'EG', 'sms',
                   decode(md5(g::text) || md5('cap' || g::text), 'hex')
            FROM generate_series(1, 510) AS g
            """);
        var (_, token) = await fixture.NewOperatorAsync(OperatorRoles.CatalogEditor);

        using var json = await GetJsonAsync(BankRequests, token);

        Assert.Equal(500, json.RootElement.GetProperty("items").GetArrayLength());
    }

    [Fact]
    public async Task BankRequestsRefuseAQueryParameter()
    {
        var (_, token) = await fixture.NewOperatorAsync(OperatorRoles.CatalogEditor);

        using var response = await fixture.SendAsync(HttpMethod.Get, BankRequests + "?limit=5", token);

        await Installs.Problems.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
    }

    // ---- daily active --------------------------------------------------------------------------------------------------

    [Fact]
    public async Task DailyActiveSumsPlatformsAndVersionsPerUtcDayAndIncludesZeroDays()
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        await SeedDailyAsync(today, "android", "1.0.0", 3);
        await SeedDailyAsync(today, "ios", "1.0.0", 4);
        await SeedDailyAsync(today, "android", "2.0.0", 5);
        await SeedDailyAsync(today.AddDays(-2), "android", "1.0.0", 7);
        await SeedDailyAsync(today.AddDays(-40), "android", "1.0.0", 99); // outside the default window
        var (_, token) = await fixture.NewOperatorAsync(OperatorRoles.SupportViewer);

        using var json = await GetJsonAsync(DailyActive, token);

        var days = json.RootElement.GetProperty("days").EnumerateArray().ToList();
        Assert.Equal(14, days.Count);
        Assert.Equal(
            Enumerable.Range(0, 14).Select(i => today.AddDays(i - 13).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)),
            days.Select(d => d.GetProperty("date").GetString()));
        Assert.Equal(12, days[^1].GetProperty("activeInstalls").GetInt32());
        Assert.Equal(0, days[^2].GetProperty("activeInstalls").GetInt32()); // a day with no counts is present, as zero
        Assert.Equal(7, days[^3].GetProperty("activeInstalls").GetInt32());
        Assert.Equal(19, days.Sum(d => d.GetProperty("activeInstalls").GetInt32()));
        Assert.All(days, d => Assert.Equal(["activeInstalls", "date"], d.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal)));
    }

    [Theory]
    [InlineData(1, 1)]
    [InlineData(7, 7)]
    [InlineData(90, 90)]
    public async Task DaysSetsTheWindow(int days, int expected)
    {
        var (_, token) = await fixture.NewOperatorAsync(OperatorRoles.FlagsAdmin);

        using var json = await GetJsonAsync(DailyActive + "?days=" + days.ToString(CultureInfo.InvariantCulture), token);

        var items = json.RootElement.GetProperty("days");
        Assert.Equal(expected, items.GetArrayLength());
        Assert.Equal(DateOnly.FromDateTime(DateTime.UtcNow).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture), items[expected - 1].GetProperty("date").GetString());
    }

    [Theory]
    [InlineData("0")]
    [InlineData("91")]
    [InlineData("-1")]
    [InlineData("100")]
    [InlineData("abc")]
    [InlineData("")]
    [InlineData("1.5")]
    [InlineData("%D9%A3")] // an Arabic-Indic digit
    [InlineData("+7")]
    [InlineData("99999999999")]
    [InlineData("7&days=8")] // repeated
    public async Task AnInvalidDaysIs400(string value)
    {
        var (_, token) = await fixture.NewOperatorAsync(OperatorRoles.FlagsAdmin);

        using var response = await fixture.SendAsync(HttpMethod.Get, DailyActive + "?days=" + value, token);

        await Installs.Problems.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
    }

    [Fact]
    public async Task DailyActiveRefusesAnUnknownQueryParameter()
    {
        var (_, token) = await fixture.NewOperatorAsync(OperatorRoles.FlagsAdmin);

        using var response = await fixture.SendAsync(HttpMethod.Get, DailyActive + "?platform=ios", token);

        await Installs.Problems.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
    }
}
