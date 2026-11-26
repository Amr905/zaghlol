using System.Net;
using System.Text.Json;
using Npgsql;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Tests.Installs;
using TestProblems = Zaghlol.Api.Tests.Installs.Problems;

namespace Zaghlol.Api.Tests.Flags;

/// <summary>T-334: <c>/admin/v1/config</c> through the real pipeline (shares the flag admin host and database).</summary>
[Collection(ApiHostGroup.Name)]
public class ConfigAdminEndpointTests(AdminFlagFixture fixture) : IClassFixture<AdminFlagFixture>
{
    private const string FlagsAdmin = OperatorRoles.FlagsAdmin;

    [Fact]
    public async Task AnUnknownKeyIs404EvenWithAnInvalidBody()
    {
        var (_, token) = await fixture.NewOperatorAsync(FlagsAdmin);

        using var get = await fixture.SendAsync(HttpMethod.Get, "/admin/v1/config/no.such_key", token);
        using var put = await fixture.SendAsync(HttpMethod.Put, "/admin/v1/config/no.such_key", token, "not json");

        await TestProblems.AssertAsync(get, HttpStatusCode.NotFound, "NOT_FOUND");
        await TestProblems.AssertAsync(put, HttpStatusCode.NotFound, "NOT_FOUND");
    }

    [Theory]
    [InlineData("{\"value\":\"many\"}")]
    [InlineData("{\"value\":\"-1\"}")]
    [InlineData("{\"value\":\"100001\"}")]
    [InlineData("{\"value\":7}")]
    [InlineData("{\"value\":true}")]
    [InlineData("{}")]
    public async Task AWrongTypeOrOutOfRangeValueIs400AndChangesNothing(string body)
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(FlagsAdmin);

        using var response = await fixture.SendAsync(HttpMethod.Put, "/admin/v1/config/ask.quota_gold", token, body);

        await TestProblems.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        Assert.Equal(0, await AuditCountAsync(operatorId));
    }

    [Fact]
    public async Task ASuccessfulSetIsAuditedBumpsTheVersionAndRoundTripsThroughGetAndList()
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(FlagsAdmin);

        using var first = await fixture.SendAsync(HttpMethod.Put, "/admin/v1/config/llm.spend_cap_usd", token, "{\"value\":\"12\"}");
        using var second = await fixture.SendAsync(HttpMethod.Put, "/admin/v1/config/llm.spend_cap_usd", token, "{\"value\":\"15.50\"}");
        using var get = await fixture.SendAsync(HttpMethod.Get, "/admin/v1/config/llm.spend_cap_usd", token);
        using var list = await fixture.SendAsync(HttpMethod.Get, "/admin/v1/config", token);

        foreach (var response in new[] { first, second, get, list })
        {
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            Assert.True(response.Headers.CacheControl?.NoStore);
        }

        using var firstJson = JsonDocument.Parse(await first.Content.ReadAsStringAsync());
        using var secondJson = JsonDocument.Parse(await second.Content.ReadAsStringAsync());
        using var getJson = JsonDocument.Parse(await get.Content.ReadAsStringAsync());
        Assert.Equal("12.00", firstJson.RootElement.GetProperty("value").GetString());
        Assert.Equal(secondJson.RootElement.GetProperty("version").GetInt64(), firstJson.RootElement.GetProperty("version").GetInt64() + 1);
        Assert.Equal("15.50", getJson.RootElement.GetProperty("value").GetString());
        Assert.False(getJson.RootElement.GetProperty("isDefault").GetBoolean());
        Assert.Equal(2, await AuditCountAsync(operatorId));

        using var listJson = JsonDocument.Parse(await list.Content.ReadAsStringAsync());
        Assert.Contains(listJson.RootElement.GetProperty("items").EnumerateArray(), i => i.GetProperty("key").GetString() == "ask.quota_free");
    }

    [Fact]
    public async Task OtherRolesAreRefused()
    {
        var (_, token) = await fixture.NewOperatorAsync(OperatorRoles.CatalogEditor);

        using var response = await fixture.SendAsync(HttpMethod.Put, "/admin/v1/config/ask.quota_free", token, "{\"value\":\"6\"}");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    private async Task<long> AuditCountAsync(Guid operatorId)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT count(*) FROM zaghlol.audit_log WHERE operator_id = @id AND action = 'config_update'", connection);
        command.Parameters.AddWithValue("id", operatorId);
        return (long)(await command.ExecuteScalarAsync())!;
    }
}
