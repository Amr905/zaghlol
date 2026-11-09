using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Npgsql;

namespace Zaghlol.Api.Tests.Installs;

/// <summary>T-124: <c>POST /v1/installs</c>, R3-6 registration retries and the strict DTO policy.</summary>
[Collection(ApiHostGroup.Name)]
public class RegistrationTests(InstallsHostFixture fixture) : IClassFixture<InstallsHostFixture>
{
    [Fact]
    public async Task ANewInstallGets201AndOnlyHashesAreStored()
    {
        var installId = InstallsHostFixture.NewInstallId();
        var key = InstallsHostFixture.NewKey();
        var body = InstallsHostFixture.InstallBody(installId, "ios", "2.3.4-beta.1");

        using var response = await fixture.RegisterAsync(body, key);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.NoStore);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var token = json.RootElement.GetProperty("installToken").GetString()!;
        Assert.Matches("^[A-Za-z0-9_-]{43}$", token);
        var serverTime = json.RootElement.GetProperty("serverTime").GetString()!;
        Assert.Matches("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", serverTime);
        Assert.Equal(fixture.Clock.Now, DateTimeOffset.Parse(serverTime, System.Globalization.CultureInfo.InvariantCulture));

        var row = await Row(installId);
        Assert.Equal(SHA256.HashData(Encoding.ASCII.GetBytes(token)), row.TokenHash);
        Assert.Equal(SHA256.HashData(Encoding.ASCII.GetBytes(key)), row.KeyHash);
        Assert.Equal(SHA256.HashData(Encoding.UTF8.GetBytes(body)), row.BodyHash);
        Assert.Equal("ios", row.Platform);
        Assert.Equal("2.3.4-beta.1", row.AppVersion);
        Assert.Equal(fixture.Clock.Now, row.FirstSeenAt);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("01jzaghlo1testkey000000000")]
    [InlineData("01JZAGHXTESTKEY00000000000X")]
    [InlineData("01JZAGHXTESTKEY0000000000I")]
    [InlineData("01JZAGHXTESTKEY000000000-0")]
    public async Task AMissingOrMalformedIdempotencyKeyIs400(string? key)
    {
        using var response = await fixture.RegisterAsync(InstallsHostFixture.InstallBody(InstallsHostFixture.NewInstallId()), key);

        await Problems.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
    }

    [Theory]
    [InlineData("{\"installId\":\"0193F2C4-7A10-4C52-9D3E-5B1F8A2C6E77\",\"platform\":\"android\",\"appVersion\":\"1.0.0\"}")]
    [InlineData("{\"installId\":\"0193f2c4-7a10-1c52-9d3e-5b1f8a2c6e77\",\"platform\":\"android\",\"appVersion\":\"1.0.0\"}")]
    [InlineData("{\"installId\":\"0193f2c4-7a10-4c52-7d3e-5b1f8a2c6e77\",\"platform\":\"android\",\"appVersion\":\"1.0.0\"}")]
    [InlineData("{\"installId\":\"0193f2c47a104c529d3e5b1f8a2c6e77\",\"platform\":\"android\",\"appVersion\":\"1.0.0\"}")]
    [InlineData("{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"platform\":\"windows\",\"appVersion\":\"1.0.0\"}")]
    [InlineData("{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"platform\":\"Android\",\"appVersion\":\"1.0.0\"}")]
    [InlineData("{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"platform\":\"android\",\"appVersion\":\"1.0\"}")]
    [InlineData("{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"platform\":\"android\",\"appVersion\":\"١.0.0\"}")]
    [InlineData("{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"platform\":\"android\",\"appVersion\":\"1.0.0\\n\"}")]
    [InlineData("{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"platform\":\"android\",\"appVersion\":null}")]
    [InlineData("{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"platform\":\"android\"}")]
    [InlineData("{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"platform\":\"android\",\"appVersion\":100}")]
    [InlineData("{\"installId\":{\"value\":\"x\"},\"platform\":\"android\",\"appVersion\":\"1.0.0\"}")]
    [InlineData("{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"platform\":\"android\",\"appVersion\":\"1.0.0\",\"platform\":\"ios\"}")]
    [InlineData("[{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"platform\":\"android\",\"appVersion\":\"1.0.0\"}]")]
    [InlineData("{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"platform\":\"android\",\"appVersion\":\"1.0.0\",}")]
    [InlineData("")]
    [InlineData("null")]
    public async Task AnInvalidBodyIs400ValidationFailedWithoutEcho(string body)
    {
        using var response = await fixture.RegisterAsync(body, InstallsHostFixture.NewKey());

        var text = await Problems.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        Assert.DoesNotContain("installId", text, StringComparison.Ordinal);
        Assert.DoesNotContain("appVersion", text, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"platform\":\"android\",\"appVersion\":\"1.0.0\",\"smsBody\":\"secret-x9\"}")]
    [InlineData("{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"platform\":\"android\",\"appVersion\":\"1.0.0\",\"balance\":{\"amount\":\"secret-x9\"}}")]
    [InlineData("{\"InstallId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"platform\":\"android\",\"appVersion\":\"1.0.0\"}")]
    [InlineData("{\"secret-x9\":1}")]
    public async Task AnUnknownFieldIs400UnknownFieldWithoutEcho(string body)
    {
        using var response = await fixture.RegisterAsync(body, InstallsHostFixture.NewKey());

        var text = await Problems.AssertAsync(response, HttpStatusCode.BadRequest, "UNKNOWN_FIELD");
        Assert.DoesNotContain("secret-x9", text, StringComparison.Ordinal);
        Assert.DoesNotContain("smsBody", text, StringComparison.Ordinal);
        Assert.DoesNotContain("InstallId", text, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ABodyOver64KbIs413()
    {
        var body = "{\"installId\":\"" + new string('a', 65 * 1024) + "\"}";

        using var response = await fixture.RegisterAsync(body, InstallsHostFixture.NewKey());

        await Problems.AssertAsync(response, HttpStatusCode.RequestEntityTooLarge, "PAYLOAD_TOO_LARGE");
    }

    [Theory]
    [InlineData("text/plain")]
    [InlineData("application/x-www-form-urlencoded")]
    public async Task AnotherMediaTypeIs415(string mediaType)
    {
        using var response = await fixture.RegisterAsync(
            InstallsHostFixture.InstallBody(InstallsHostFixture.NewInstallId()),
            InstallsHostFixture.NewKey(),
            mediaType: mediaType);

        await Problems.AssertAsync(response, HttpStatusCode.UnsupportedMediaType, "UNSUPPORTED_MEDIA_TYPE");
    }

    [Fact]
    public async Task AReplayBeforeAnyAuthenticatedCallGets201WithADifferentTokenAndTheFirstStopsWorking()
    {
        var installId = InstallsHostFixture.NewInstallId();
        var key = InstallsHostFixture.NewKey();
        var body = InstallsHostFixture.InstallBody(installId);

        using var first = await fixture.RegisterAsync(body, key);
        using var replay = await fixture.RegisterAsync(body, key);

        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        Assert.Equal(HttpStatusCode.Created, replay.StatusCode);
        var firstToken = await InstallsHostFixture.TokenOf(first);
        var secondToken = await InstallsHostFixture.TokenOf(replay);
        Assert.NotEqual(firstToken, secondToken);

        using var old = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", firstToken);
        await Problems.AssertAsync(old, HttpStatusCode.Unauthorized, "INSTALL_TOKEN_INVALID");
        using var current = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", secondToken);
        Assert.Equal(HttpStatusCode.OK, current.StatusCode);
    }

    [Fact]
    public async Task AfterOneAuthenticatedCallTheSameReplayIsInstallExists()
    {
        var installId = InstallsHostFixture.NewInstallId();
        var key = InstallsHostFixture.NewKey();
        var body = InstallsHostFixture.InstallBody(installId);
        using var first = await fixture.RegisterAsync(body, key);
        var token = await InstallsHostFixture.TokenOf(first);

        using var call = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", token);
        Assert.Equal(HttpStatusCode.OK, call.StatusCode);
        var row = await Row(installId);
        Assert.Null(row.KeyHash);
        Assert.Null(row.BodyHash);

        using var replay = await fixture.RegisterAsync(body, key);

        var text = await Problems.AssertAsync(replay, HttpStatusCode.Conflict, "INSTALL_EXISTS");
        Assert.DoesNotContain("installToken", text, StringComparison.Ordinal);
        using var stillValid = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", token);
        Assert.Equal(HttpStatusCode.OK, stillValid.StatusCode);
    }

    [Fact]
    public async Task KnowingOnlyTheSupportCodeAndTheBodyGives409AndNoToken()
    {
        var installId = InstallsHostFixture.NewInstallId();
        var body = InstallsHostFixture.InstallBody(installId);
        using var first = await fixture.RegisterAsync(body, InstallsHostFixture.NewKey());
        var token = await InstallsHostFixture.TokenOf(first);

        using var attacker = await fixture.RegisterAsync(body, InstallsHostFixture.NewKey());

        var text = await Problems.AssertAsync(attacker, HttpStatusCode.Conflict, "INSTALL_EXISTS");
        Assert.DoesNotContain("installToken", text, StringComparison.Ordinal);
        Assert.DoesNotContain(token, text, StringComparison.Ordinal);
        using var owner = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", token);
        Assert.Equal(HttpStatusCode.OK, owner.StatusCode);
    }

    [Fact]
    public async Task TheSameKeyWithADifferentBodyIsIdempotencyKeyReused()
    {
        var installId = InstallsHostFixture.NewInstallId();
        var key = InstallsHostFixture.NewKey();
        using var first = await fixture.RegisterAsync(InstallsHostFixture.InstallBody(installId), key);
        var token = await InstallsHostFixture.TokenOf(first);

        using var other = await fixture.RegisterAsync(InstallsHostFixture.InstallBody(installId, appVersion: "1.0.1"), key);

        var text = await Problems.AssertAsync(other, HttpStatusCode.Conflict, "IDEMPOTENCY_KEY_REUSED");
        Assert.DoesNotContain("installToken", text, StringComparison.Ordinal);
        using var owner = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", token);
        Assert.Equal(HttpStatusCode.OK, owner.StatusCode);
    }

    [Fact]
    public async Task AReplayAfter24HoursIsInstallExists()
    {
        var installId = InstallsHostFixture.NewInstallId();
        var key = InstallsHostFixture.NewKey();
        var body = InstallsHostFixture.InstallBody(installId);
        using var first = await fixture.RegisterAsync(body, key);
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);

        fixture.Clock.Advance(TimeSpan.FromHours(24));
        using var replay = await fixture.RegisterAsync(body, key);

        await Problems.AssertAsync(replay, HttpStatusCode.Conflict, "INSTALL_EXISTS");
    }

    [Fact]
    public async Task ADeletedInstallCanNotBeRegisteredAgain()
    {
        var installId = InstallsHostFixture.NewInstallId();
        var key = InstallsHostFixture.NewKey();
        var body = InstallsHostFixture.InstallBody(installId);
        using var first = await fixture.RegisterAsync(body, key);
        var token = await InstallsHostFixture.TokenOf(first);
        using var deleted = await fixture.SendAsync(HttpMethod.Delete, "/v1/installs/me", token);
        Assert.Equal(HttpStatusCode.Accepted, deleted.StatusCode);

        using var replay = await fixture.RegisterAsync(body, key);

        await Problems.AssertAsync(replay, HttpStatusCode.Conflict, "INSTALL_EXISTS");
    }

    private async Task<(byte[] TokenHash, byte[]? KeyHash, byte[]? BodyHash, string Platform, string AppVersion, DateTimeOffset FirstSeenAt)> Row(string installId)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "SELECT token_hash, registration_key_hash, registration_body_sha256, platform, app_version, first_seen_at FROM zaghlol.installs WHERE id = @id",
            connection);
        command.Parameters.AddWithValue("id", Guid.Parse(installId));
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        return (
            (byte[])reader[0],
            reader.IsDBNull(1) ? null : (byte[])reader[1],
            reader.IsDBNull(2) ? null : (byte[])reader[2],
            reader.GetString(3),
            reader.GetString(4),
            reader.GetFieldValue<DateTimeOffset>(5));
    }
}

/// <summary>Shared assertions for <c>application/problem+json</c> answers.</summary>
internal static class Problems
{
    public static async Task<string> AssertAsync(HttpResponseMessage response, HttpStatusCode status, string code)
    {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(status == response.StatusCode, $"expected {(int)status}, got {(int)response.StatusCode}: {text}");
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        using var json = JsonDocument.Parse(text);
        Assert.Equal(code, json.RootElement.GetProperty("code").GetString());
        Assert.Equal((int)status, json.RootElement.GetProperty("status").GetInt32());
        Assert.True(json.RootElement.TryGetProperty("type", out _));
        Assert.True(json.RootElement.TryGetProperty("title", out _));
        return text;
    }

    /// <summary>The body without its per-request <c>correlationId</c>, for comparing two answers.</summary>
    public static string WithoutCorrelationId(string text)
    {
        var node = System.Text.Json.Nodes.JsonNode.Parse(text)!.AsObject();
        node.Remove("correlationId");
        return node.ToJsonString();
    }
}
