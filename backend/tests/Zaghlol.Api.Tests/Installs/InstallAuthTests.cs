using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Npgsql;
using Zaghlol.Api.Auth;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Api.Tests.Installs;

/// <summary>T-124: the install-token scheme, <c>DELETE /v1/installs/me</c> and token rotation.</summary>
[Collection(ApiHostGroup.Name)]
public class InstallAuthTests(InstallsHostFixture fixture) : IClassFixture<InstallsHostFixture>
{
    [Fact]
    public async Task MissingMalformedUnknownAndDeletedTokensGetIdenticalUnauthorizedBodies()
    {
        var (_, deletedToken) = await fixture.NewInstallAsync();
        using (var deleted = await fixture.SendAsync(HttpMethod.Delete, "/v1/installs/me", deletedToken))
        {
            Assert.Equal(HttpStatusCode.Accepted, deleted.StatusCode);
        }

        var (_, valid) = await fixture.NewInstallAsync();
        string?[] authorizations =
        [
            null,
            "Bearer " + valid[..42],
            "Bearer " + valid + "A",
            "Bearer " + valid[..42] + "+",
            "Bearer " + valid[..42] + "=",
            "Basic " + valid,
            "Bearer",
            "Bearer " + InstallTokens.Generate(),
            "Bearer " + deletedToken,
        ];

        var bodies = new List<string>();
        foreach (var authorization in authorizations)
        {
            using var response = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", token: null, authorization: authorization);
            var text = await Problems.AssertAsync(response, HttpStatusCode.Unauthorized, "INSTALL_TOKEN_INVALID");
            Assert.Equal("Bearer", response.Headers.WwwAuthenticate.ToString());
            bodies.Add(Problems.WithoutCorrelationId(text));
        }

        Assert.Single(bodies.Distinct(StringComparer.Ordinal));
    }

    [Fact]
    public async Task TheInstallHeaderMustNameTheTokensInstall()
    {
        var (installId, token) = await fixture.NewInstallAsync();
        var (otherId, _) = await fixture.NewInstallAsync();

        using var matching = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", token, installHeader: installId);
        Assert.Equal(HttpStatusCode.OK, matching.StatusCode);
        using (var json = JsonDocument.Parse(await matching.Content.ReadAsStringAsync()))
        {
            Assert.Equal(installId, json.RootElement.GetProperty("installId").GetString());
        }

        using var mismatch = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", token, installHeader: otherId);
        await Problems.AssertAsync(mismatch, HttpStatusCode.Unauthorized, "INSTALL_TOKEN_INVALID");

        using var malformed = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", token, installHeader: installId.ToUpperInvariant());
        await Problems.AssertAsync(malformed, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
    }

    [Fact]
    public async Task APseudonymizerFailureLogsUnavailableAndTheRequestSucceeds()
    {
        var (_, token) = await fixture.NewInstallAsync();
        fixture.Pseudonymizer.Fail = true;
        try
        {
            using var response = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", token);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        }
        finally
        {
            fixture.Pseudonymizer.Fail = false;
        }

        await WaitForLogAsync(e => e.Contains("/v1/t/whoami", StringComparison.Ordinal)
            && e.Contains("InstallHash=\"" + LogFieldPolicy.InstallHashUnavailable + "\"", StringComparison.Ordinal));
    }

    [Fact]
    public async Task AuthenticatedRequestsLogAnInstallHashButNeverTheTokenOrTheId()
    {
        var installId = InstallsHostFixture.NewInstallId();
        var key = InstallsHostFixture.NewKey();
        using var created = await fixture.RegisterAsync(InstallsHostFixture.InstallBody(installId), key);
        var token = await InstallsHostFixture.TokenOf(created);
        using var ok = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", token);
        using var unauthorized = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", InstallTokens.Generate());

        // T-138 tests m2, re-run on the real filter: the Idempotency-Key of an idempotent call is never logged either.
        var idemKey = InstallsHostFixture.NewKey();
        using var idem = await fixture.SendAsync(HttpMethod.Post, "/v1/t/idem", token, "{\"mode\":\"ok\"}", idemKey);
        Assert.Equal(HttpStatusCode.OK, idem.StatusCode);
        await WaitForLogAsync(e => e.Contains("/v1/t/idem", StringComparison.Ordinal));

        await WaitForLogAsync(e => e.Contains("/v1/t/whoami", StringComparison.Ordinal) && e.Contains("Status=401", StringComparison.Ordinal));
        await WaitForLogAsync(e => e.Contains("/v1/t/whoami", StringComparison.Ordinal)
            && e.Contains("Status=200", StringComparison.Ordinal)
            && e.Contains("InstallHash=", StringComparison.Ordinal));
        foreach (var secret in new[] { token, installId, key, idemKey })
        {
            Assert.DoesNotContain(fixture.LogSink.Entries, e => e.Contains(secret, StringComparison.Ordinal));
        }
    }

    [Fact]
    public async Task DeleteTombstonesTheInstallKillsItsTokenAndRemovesOnlyItsIdempotencyRows()
    {
        var (installId, token) = await fixture.NewInstallAsync();
        var (otherId, otherToken) = await fixture.NewInstallAsync();
        foreach (var bearer in new[] { token, otherToken })
        {
            using var stored = await fixture.SendAsync(HttpMethod.Post, "/v1/t/idem", bearer, "{\"mode\":\"ok\"}", InstallsHostFixture.NewKey());
            Assert.Equal(HttpStatusCode.OK, stored.StatusCode);
        }

        Assert.Equal(1L, await CountIdempotencyRows(installId));

        using var deleted = await fixture.SendAsync(HttpMethod.Delete, "/v1/installs/me", token);

        Assert.Equal(HttpStatusCode.Accepted, deleted.StatusCode);
        Assert.Empty(await deleted.Content.ReadAsByteArrayAsync());
        Assert.Equal(0L, await CountIdempotencyRows(installId));
        Assert.Equal(1L, await CountIdempotencyRows(otherId));
        using var after = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", token);
        await Problems.AssertAsync(after, HttpStatusCode.Unauthorized, "INSTALL_TOKEN_INVALID");
        using var again = await fixture.SendAsync(HttpMethod.Delete, "/v1/installs/me", token);
        await Problems.AssertAsync(again, HttpStatusCode.Unauthorized, "INSTALL_TOKEN_INVALID");
        using var other = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", otherToken);
        Assert.Equal(HttpStatusCode.OK, other.StatusCode);

        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT deleted_at FROM zaghlol.installs WHERE id = @id", connection);
        command.Parameters.AddWithValue("id", Guid.Parse(installId));
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        Assert.Equal(fixture.Clock.Now, reader.GetFieldValue<DateTimeOffset>(0));
    }

    [Fact]
    public async Task ARotatedTokenReplacesTheOldOneAtOnce()
    {
        var (_, token) = await fixture.NewInstallAsync();

        using var rotated = await fixture.SendAsync(HttpMethod.Post, "/v1/t/rotate", token);

        Assert.Equal(HttpStatusCode.OK, rotated.StatusCode);
        using var json = JsonDocument.Parse(await rotated.Content.ReadAsStringAsync());
        var next = json.RootElement.GetProperty("rotateInstallToken").GetString()!;
        Assert.True(InstallTokens.IsWellFormed(next));
        using var old = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", token);
        await Problems.AssertAsync(old, HttpStatusCode.Unauthorized, "INSTALL_TOKEN_INVALID");
        using var current = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", next);
        Assert.Equal(HttpStatusCode.OK, current.StatusCode);
    }

    [Fact]
    public async Task ThePerTokenBucketAnswers429WithRetryAfter()
    {
        // The fixture's per-token bucket: burst 20, one token an hour. Other tokens are unaffected.
        var (installId, token) = await fixture.NewInstallAsync();
        for (var i = 0; i < 20; i++)
        {
            using var allowed = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", token);
            Assert.Equal(HttpStatusCode.OK, allowed.StatusCode);
        }

        using var limited = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", token);

        var text = await Problems.AssertAsync(limited, HttpStatusCode.TooManyRequests, "RATE_LIMITED");
        var retryAfter = limited.Headers.RetryAfter?.Delta;
        Assert.NotNull(retryAfter);
        Assert.True(retryAfter >= TimeSpan.FromSeconds(1));
        using (var json = JsonDocument.Parse(text))
        {
            Assert.Equal((int)retryAfter.Value.TotalSeconds, json.RootElement.GetProperty("retryAfterSeconds").GetInt32());
        }

        var (_, fresh) = await fixture.NewInstallAsync();
        using var other = await fixture.SendAsync(HttpMethod.Get, "/v1/t/whoami", fresh);
        Assert.Equal(HttpStatusCode.OK, other.StatusCode);

        // T-124 security S-5: the token-bucket 429 is logged without the token or the install ID.
        await WaitForLogAsync(e => e.Contains("/v1/t/whoami", StringComparison.Ordinal) && e.Contains("Status=429", StringComparison.Ordinal));
        foreach (var secret in new[] { token, installId })
        {
            Assert.DoesNotContain(fixture.LogSink.Entries, e => e.Contains(secret, StringComparison.Ordinal));
        }
    }

    private async Task<long> CountIdempotencyRows(string installId)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT count(*) FROM zaghlol.idempotency_records WHERE install_id = @id", connection);
        command.Parameters.AddWithValue("id", Guid.Parse(installId));
        return (long)(await command.ExecuteScalarAsync())!;
    }

    private async Task WaitForLogAsync(Func<string, bool> predicate)
    {
        var deadline = DateTime.UtcNow.AddSeconds(5);
        while (!fixture.LogSink.Entries.Any(predicate) && DateTime.UtcNow < deadline)
        {
            await Task.Delay(50);
        }

        Assert.Contains(fixture.LogSink.Entries, e => predicate(e));
    }
}

/// <summary>T-124 F7: the startup check of the log pseudonym.</summary>
[Collection(ApiHostGroup.Name)]
public class InstallHashStartupCheckTests
{
    [Theory]
    [InlineData("Production", true)]
    [InlineData("Staging", true)]
    [InlineData("Development", false)]
    [InlineData("Testing", false)]
    public async Task WithoutAKmsTheHostRefusesToStartOutsideDevelopmentAndTesting(string environment, bool refuses)
    {
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = environment });
        builder.WebHost.UseTestServer();
        builder.Services.AddSingleton<ILogPseudonymizer>(new ThrowingPseudonymizer());
        builder.Services.AddHostedService<InstallHashStartupCheck>();
        await using var app = builder.Build();

        if (refuses)
        {
            var error = await Assert.ThrowsAsync<InstallHashUnavailableException>(() => app.StartAsync());
            Assert.Equal(InstallHashUnavailableException.DefaultMessage, error.Message);
        }
        else
        {
            await app.StartAsync();
            await app.StopAsync();
        }
    }

    private sealed class ThrowingPseudonymizer : ILogPseudonymizer
    {
        public ValueTask<string> InstallHashAsync(InstallId installId, CancellationToken cancellationToken) =>
            throw new InvalidOperationException("installHash needs the KMS-derived log key outside Development and Testing.");
    }
}
