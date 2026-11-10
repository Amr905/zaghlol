using System.Globalization;
using System.Net;
using System.Text.Json;
using Npgsql;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Tests.Flags;
using Zaghlol.Api.Tests.Installs;
using TestProblems = Zaghlol.Api.Tests.Installs.Problems;

namespace Zaghlol.Api.Tests.Prices;

/// <summary>T-127: <c>PUT /admin/v1/prices/override</c> through the real pipeline (real clock; the frozen-clock cases are in the service tests).</summary>
[Collection(ApiHostGroup.Name)]
public class PriceAdminEndpointTests(AdminFlagFixture fixture) : IClassFixture<AdminFlagFixture>
{
    private const string Path = "/admin/v1/prices/override";
    private const string PricesAdmin = OperatorRoles.PricesAdmin;

    private static string Body(string symbol = "XAU21_G", string currency = "EGP", string price = "4217.50", string reason = "Feed outage, dealer quote", string? expiresAt = null) =>
        $"{{\"symbol\":\"{symbol}\",\"currency\":\"{currency}\",\"price\":\"{price}\",\"reason\":\"{reason}\""
        + (expiresAt is null ? string.Empty : $",\"expiresAt\":\"{expiresAt}\"") + "}";

    private static string Utc(TimeSpan fromNow) =>
        DateTimeOffset.UtcNow.Add(fromNow).ToString("yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'", CultureInfo.InvariantCulture);

    private async Task<(string Price, bool IsOverride, DateTimeOffset Expires)> StoredAsync(string symbol, string currency)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "SELECT price::text, is_override, override_expires_at FROM zaghlol.price_quotes WHERE symbol = @s AND currency = @c",
            connection);
        command.Parameters.AddWithValue("s", symbol);
        command.Parameters.AddWithValue("c", currency);
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        return (reader.GetString(0), reader.GetBoolean(1), reader.GetFieldValue<DateTimeOffset>(2));
    }

    private async Task<long> AuditCountAsync(Guid operatorId)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT count(*) FROM zaghlol.audit_log WHERE operator_id = @id AND action = 'price_override'", connection);
        command.Parameters.AddWithValue("id", operatorId);
        return (long)(await command.ExecuteScalarAsync())!;
    }

    [Fact]
    public async Task APriceAdminOverrideIs200WithDecimalStringsStoresItAndDefaultsTheExpiryTo24Hours()
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(PricesAdmin);
        var before = DateTimeOffset.UtcNow;

        using var response = await fixture.SendAsync(HttpMethod.Put, Path, token, Body("XAU21_G", "EGP", "4217.5"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.NoStore);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var root = json.RootElement;
        Assert.Equal("XAU21_G", root.GetProperty("symbol").GetString());
        Assert.Equal("EGP", root.GetProperty("currency").GetString());
        Assert.Equal(JsonValueKind.String, root.GetProperty("price").ValueKind);
        Assert.Equal("4217.50", root.GetProperty("price").GetString());
        Assert.EndsWith("Z", root.GetProperty("asOf").GetString(), StringComparison.Ordinal);

        var stored = await StoredAsync("XAU21_G", "EGP");
        Assert.True(stored.IsOverride);
        Assert.Equal("4217.500000", stored.Price);
        Assert.InRange((stored.Expires - before).TotalHours, 23.9, 24.1);
        Assert.Equal(1, await AuditCountAsync(operatorId));
    }

    [Fact]
    public async Task AnExplicitExpiryWithinSevenDaysIsStored()
    {
        var (_, token) = await fixture.NewOperatorAsync(PricesAdmin);

        using var response = await fixture.SendAsync(HttpMethod.Put, Path, token, Body("XAU18_G", "USD", "70", expiresAt: Utc(TimeSpan.FromDays(6))));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var stored = await StoredAsync("XAU18_G", "USD");
        Assert.InRange((stored.Expires - DateTimeOffset.UtcNow).TotalDays, 5.9, 6.1);
    }

    [Theory]
    [InlineData(7 * 24 + 1)]
    [InlineData(30 * 24)]
    [InlineData(-1)]
    public async Task AnExpiryBeyondSevenDaysOrInThePastIs400ValidationFailedAndChangesNothing(int hoursFromNow)
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(PricesAdmin);

        using var response = await fixture.SendAsync(HttpMethod.Put, Path, token, Body("XAU24_G", "USD", expiresAt: Utc(TimeSpan.FromHours(hoursFromNow))));

        await TestProblems.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        Assert.Equal(0, await AuditCountAsync(operatorId));
    }

    [Theory]
    [InlineData("XAU99_G", "EGP", "10", "A reason")]
    [InlineData("XAU21_G", "EUR", "10", "A reason")]
    [InlineData("XAU21_G", "EGP", "0", "A reason")]
    [InlineData("XAU21_G", "EGP", "-1", "A reason")]
    [InlineData("XAU21_G", "EGP", "1e3", "A reason")]
    [InlineData("XAU21_G", "EGP", "10.1234567", "A reason")]
    [InlineData("XAU21_G", "EGP", "10", "ab")]
    [InlineData("XAU21_G", "EGP", "10", "me@example.com")]
    public async Task InvalidFieldsAre400ValidationFailedAndAuditNothing(string symbol, string currency, string price, string reason)
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(PricesAdmin);

        using var response = await fixture.SendAsync(HttpMethod.Put, Path, token, Body(symbol, currency, price, reason));

        var text = await TestProblems.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        Assert.DoesNotContain("example.com", text, StringComparison.Ordinal);
        Assert.Equal(0, await AuditCountAsync(operatorId));
    }

    [Theory]
    [InlineData("{\"symbol\":\"XAU21_G\",\"currency\":\"EGP\",\"price\":4217.5,\"reason\":\"A reason\"}")]
    [InlineData("{\"symbol\":\"XAU21_G\",\"currency\":\"EGP\",\"reason\":\"A reason\"}")]
    [InlineData("{\"symbol\":\"XAU21_G\",\"currency\":\"EGP\",\"price\":\"10\"}")]
    [InlineData("{\"symbol\":\"XAU21_G\",\"currency\":\"EGP\",\"price\":\"10\",\"reason\":\"A reason\",\"expiresAt\":\"2030-01-01T00:00:00+00:00\"}")]
    [InlineData("{\"symbol\":\"XAU21_G\",\"currency\":\"EGP\",\"price\":\"10\",\"reason\":\"A reason\",\"expiresAt\":86400}")]
    [InlineData("not json")]
    public async Task ANumberPriceMissingMembersOrBadTimestampsAre400ValidationFailed(string body)
    {
        var (_, token) = await fixture.NewOperatorAsync(PricesAdmin);

        using var response = await fixture.SendAsync(HttpMethod.Put, Path, token, body);

        await TestProblems.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
    }

    [Fact]
    public async Task AnUnknownMemberIs400UnknownFieldAndChangesNothing()
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(PricesAdmin);

        using var response = await fixture.SendAsync(
            HttpMethod.Put,
            Path,
            token,
            "{\"symbol\":\"XAU21_G\",\"currency\":\"EGP\",\"price\":\"10\",\"reason\":\"A reason\",\"note\":\"x\"}");

        var text = await TestProblems.AssertAsync(response, HttpStatusCode.BadRequest, "UNKNOWN_FIELD");
        Assert.DoesNotContain("note", text, StringComparison.Ordinal);
        Assert.Equal(0, await AuditCountAsync(operatorId));
    }

    [Fact]
    public async Task OnlyThePricesAdminRoleMayOverrideAndAnonymousIs401()
    {
        var (_, flagsOnly) = await fixture.NewOperatorAsync(OperatorRoles.FlagsAdmin);
        var (_, catalogOnly) = await fixture.NewOperatorAsync(OperatorRoles.CatalogEditor);

        using var anonymous = await fixture.SendAsync(HttpMethod.Put, Path, token: null, Body());
        using var forbidden = await fixture.SendAsync(HttpMethod.Put, Path, flagsOnly, Body());
        using var forbiddenToo = await fixture.SendAsync(HttpMethod.Put, Path, catalogOnly, Body());

        await TestProblems.AssertAsync(anonymous, HttpStatusCode.Unauthorized, "UNAUTHORIZED");
        await TestProblems.AssertAsync(forbidden, HttpStatusCode.Forbidden, "FORBIDDEN");
        await TestProblems.AssertAsync(forbiddenToo, HttpStatusCode.Forbidden, "FORBIDDEN");
    }

    [Fact]
    public async Task APricesAdminTokenCannotReachOtherAdminRoutes()
    {
        var (_, token) = await fixture.NewOperatorAsync(PricesAdmin);

        using var response = await fixture.SendAsync(HttpMethod.Get, "/admin/v1/flags/zakah", token);

        await TestProblems.AssertAsync(response, HttpStatusCode.Forbidden, "FORBIDDEN");
    }

    [Fact]
    public async Task NoIdempotencyKeyIsNeededAndWrongMediaTypeIs415()
    {
        var (_, token) = await fixture.NewOperatorAsync(PricesAdmin);

        using var ok = await fixture.SendAsync(HttpMethod.Put, Path, token, Body("XAU24_G", "EGP", "4900"));
        using var wrongType = await fixture.SendAsync(HttpMethod.Put, Path, token, Body(), "text/plain");

        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
        await TestProblems.AssertAsync(wrongType, HttpStatusCode.UnsupportedMediaType, "UNSUPPORTED_MEDIA_TYPE");
    }
}
