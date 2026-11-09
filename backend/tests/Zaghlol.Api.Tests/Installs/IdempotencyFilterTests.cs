using System.Buffers.Text;
using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Zaghlol.Api.Idempotency;
using Zaghlol.Api.Signing;
using Zaghlol.Api.Tests.Signing;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Api.Tests.Installs;

/// <summary>T-124: the idempotency filter and store (backend-api §1, R2-8, R3-6) on the test-only <c>POST /v1/t/idem</c>.</summary>
[Collection(ApiHostGroup.Name)]
public partial class IdempotencyFilterTests(InstallsHostFixture fixture) : IClassFixture<InstallsHostFixture>
{
    [GeneratedRegex("^kid=(s[0-9]{4}[a-z]); alg=ES256; sig=([A-Za-z0-9_-]{86})\\z")]
    private static partial Regex SignatureHeader();

    [Fact]
    public async Task AReplayReturnsTheStoredResultWithoutRunningTheHandlerAndIsSignedAgain()
    {
        var (_, token) = await fixture.NewInstallAsync();
        var key = InstallsHostFixture.NewKey();
        const string Body = "{\"mode\":\"ok\",\"marker\":\"first\"}";

        using var first = await Post(token, Body, key);
        var runs = fixture.Runs;
        using var replay = await Post(token, Body, key);

        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.Equal(HttpStatusCode.OK, replay.StatusCode);
        var firstBody = await first.Content.ReadAsByteArrayAsync();
        var replayBody = await replay.Content.ReadAsByteArrayAsync();
        Assert.Equal(firstBody, replayBody);
        Assert.Equal(runs, fixture.Runs);
        Assert.Equal("application/json", replay.Content.Headers.ContentType?.MediaType);
        AssertSigned(first, firstBody);
        AssertSigned(replay, replayBody);
    }

    [Fact]
    public async Task TheSameKeyWithADifferentBodyIs409AndNeverTheStoredBody()
    {
        var (_, token) = await fixture.NewInstallAsync();
        var key = InstallsHostFixture.NewKey();
        using var first = await Post(token, "{\"mode\":\"ok\",\"marker\":\"original-7f3\"}", key);
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);

        using var other = await Post(token, "{\"mode\":\"ok\",\"marker\":\"changed\"}", key);

        var text = await Problems.AssertAsync(other, HttpStatusCode.Conflict, "IDEMPOTENCY_KEY_REUSED");
        Assert.DoesNotContain("original-7f3", text, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AnotherInstallsSameKeyIsANewRequestAndNeverSeesTheFirstBody()
    {
        var (_, tokenA) = await fixture.NewInstallAsync();
        var (_, tokenB) = await fixture.NewInstallAsync();
        var key = InstallsHostFixture.NewKey();
        using var a = await Post(tokenA, "{\"mode\":\"ok\",\"marker\":\"install-a-only\"}", key);
        var runs = fixture.Runs;

        using var b = await Post(tokenB, "{\"mode\":\"ok\",\"marker\":\"install-b\"}", key);

        Assert.Equal(HttpStatusCode.OK, b.StatusCode);
        Assert.Equal(runs + 1, fixture.Runs);
        var text = await b.Content.ReadAsStringAsync();
        Assert.DoesNotContain("install-a-only", text, StringComparison.Ordinal);
        Assert.Contains("install-b", text, StringComparison.Ordinal);

        // Even the same body from B runs fresh rather than replaying A's.
        var runsBefore = fixture.Runs;
        using var sameBody = await Post(tokenB, "{\"mode\":\"ok\",\"marker\":\"install-a-only\"}", InstallsHostFixture.NewKey());
        Assert.Equal(runsBefore + 1, fixture.Runs);
    }

    [Fact]
    public async Task ARecordPastExpiresAtIsNeverServedEvenBeforeThePurge()
    {
        var (_, token) = await fixture.NewInstallAsync();
        var key = InstallsHostFixture.NewKey();
        const string Body = "{\"mode\":\"ok\"}";
        using var first = await Post(token, Body, key);
        Assert.Equal(1L, await CountRows(key));

        fixture.Clock.Advance(TimeSpan.FromHours(24));
        var runs = fixture.Runs;
        using var later = await Post(token, Body, key);

        Assert.Equal(HttpStatusCode.OK, later.StatusCode);
        Assert.Equal(runs + 1, fixture.Runs);
        Assert.NotEqual(await first.Content.ReadAsStringAsync(), await later.Content.ReadAsStringAsync());
    }

    [Theory]
    [InlineData("tooMany", HttpStatusCode.TooManyRequests)]
    [InlineData("unavailable", HttpStatusCode.ServiceUnavailable)]
    [InlineData("throw", HttpStatusCode.InternalServerError)]
    public async Task TooManyRequestsAndServerErrorsAreNotStoredAndARetryRunsAgain(string mode, HttpStatusCode status)
    {
        var (_, token) = await fixture.NewInstallAsync();
        var key = InstallsHostFixture.NewKey();
        var body = "{\"mode\":\"" + mode + "\"}";

        using var first = await Post(token, body, key);
        var runs = fixture.Runs;
        using var retry = await Post(token, body, key);

        Assert.Equal(status, first.StatusCode);
        Assert.Equal(status, retry.StatusCode);
        Assert.Equal(runs + 1, fixture.Runs);
        Assert.Equal(0L, await CountRows(key));
    }

    [Theory]
    [InlineData("conflict", HttpStatusCode.Conflict)]
    [InlineData("unprocessable", HttpStatusCode.UnprocessableEntity)]
    public async Task ConflictsAndUnprocessableResultsAreFinalAndReplayed(string mode, HttpStatusCode status)
    {
        var (_, token) = await fixture.NewInstallAsync();
        var key = InstallsHostFixture.NewKey();
        var body = "{\"mode\":\"" + mode + "\"}";

        using var first = await Post(token, body, key);
        var runs = fixture.Runs;
        using var replay = await Post(token, body, key);

        Assert.Equal(status, first.StatusCode);
        Assert.Equal(status, replay.StatusCode);
        Assert.Equal(runs, fixture.Runs);
        Assert.Equal(await first.Content.ReadAsStringAsync(), await replay.Content.ReadAsStringAsync());
        Assert.Equal(1L, await CountRows(key));
    }

    [Fact]
    public async Task TheStoredBodyIsCiphertextBoundToItsInstallAndOperation()
    {
        var (installId, token) = await fixture.NewInstallAsync();
        var key = InstallsHostFixture.NewKey();
        using var response = await Post(token, "{\"mode\":\"ok\",\"marker\":\"plain-marker-41\"}", key);
        var plain = await response.Content.ReadAsByteArrayAsync();

        byte[] stored;
        await using (var connection = new NpgsqlConnection(fixture.Database.Superuser))
        {
            await connection.OpenAsync();
            await using var command = new NpgsqlCommand("SELECT response_body_enc FROM zaghlol.idempotency_records WHERE idempotency_key = @k", connection);
            command.Parameters.AddWithValue("k", key);
            stored = (byte[])(await command.ExecuteScalarAsync())!;
        }

        Assert.Equal(-1, stored.AsSpan().IndexOf("plain-marker-41"u8));
        var cipher = fixture.Services.GetRequiredService<IEnvelopeCipher>();
        var id = InstallId.Parse(installId);
        Assert.Equal(plain, await cipher.DecryptAsync(stored, IdempotencyFilter.EnvelopeContext(id, IdempotentOperation.VerifyPurchase), CancellationToken.None));
        await Assert.ThrowsAsync<EnvelopeDecryptionException>(async () =>
            await cipher.DecryptAsync(stored, IdempotencyFilter.EnvelopeContext(id, IdempotentOperation.SignIn), CancellationToken.None));
        await Assert.ThrowsAsync<EnvelopeDecryptionException>(async () =>
            await cipher.DecryptAsync(stored, IdempotencyFilter.EnvelopeContext(InstallId.FromGuid(Guid.NewGuid()), IdempotentOperation.VerifyPurchase), CancellationToken.None));
    }

    [Fact]
    public async Task ConcurrentRequestsWithOneKeyRunTheHandlerOnceAndTheLoserGets429()
    {
        var (_, token) = await fixture.NewInstallAsync();
        var key = InstallsHostFixture.NewKey();
        const string Body = "{\"mode\":\"slow\"}";
        var runs = fixture.Runs;

        var first = Post(token, Body, key);
        Assert.True(await fixture.Entered.WaitAsync(TimeSpan.FromSeconds(10)));
        using (var loser = await Post(token, Body, key))
        {
            await Problems.AssertAsync(loser, HttpStatusCode.TooManyRequests, "RATE_LIMITED");
            Assert.Equal(TimeSpan.FromSeconds(1), loser.Headers.RetryAfter?.Delta);
        }

        fixture.Release();
        using var winner = await first;
        Assert.Equal(HttpStatusCode.OK, winner.StatusCode);
        Assert.Equal(runs + 1, fixture.Runs);

        using var replay = await Post(token, Body, key);
        Assert.Equal(HttpStatusCode.OK, replay.StatusCode);
        Assert.Equal(runs + 1, fixture.Runs);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("not-a-ulid")]
    public async Task TheKeyIsRequiredAndMustBeAUlid(string? key)
    {
        var (_, token) = await fixture.NewInstallAsync();
        var runs = fixture.Runs;

        using var response = await Post(token, "{\"mode\":\"ok\"}", key);

        await Problems.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        Assert.Equal(runs, fixture.Runs);
    }

    [Fact]
    public async Task AMalformedTimeNonceIsRejectedBeforeAnyReplay()
    {
        var (_, token) = await fixture.NewInstallAsync();
        var key = InstallsHostFixture.NewKey();
        using var first = await Post(token, "{\"mode\":\"ok\"}", key);

        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/t/idem");
        request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        request.Headers.Add(IdempotencyKeys.HeaderName, key);
        request.Headers.Add(TimeNonceFilter.HeaderName, "not-a-nonce");
        request.Content = new StringContent("{\"mode\":\"ok\"}", System.Text.Encoding.UTF8, "application/json");
        using var response = await fixture.Client.SendAsync(request);

        await Problems.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
    }

    private Task<HttpResponseMessage> Post(string token, string body, string? key) =>
        fixture.SendAsync(HttpMethod.Post, "/v1/t/idem", token, body, key);

    private async Task<long> CountRows(string key)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT count(*) FROM zaghlol.idempotency_records WHERE idempotency_key = @k", connection);
        command.Parameters.AddWithValue("k", key);
        return (long)(await command.ExecuteScalarAsync())!;
    }

    private void AssertSigned(HttpResponseMessage response, byte[] body)
    {
        Assert.True(response.Headers.TryGetValues(ResponseSigningMiddleware.HeaderName, out var values));
        var match = SignatureHeader().Match(values.Single());
        Assert.True(match.Success);
        var signer = fixture.Services.GetRequiredService<ISigner>();
        var key = signer.PublishedKeys(SigningPurpose.Sync).Single(k => k.Kid == match.Groups[1].Value && k.Status == SigningKeyStatus.Active);
        Assert.True(SignatureCheck.Verifies(key.PublicJwk, body, Base64Url.DecodeFromChars(match.Groups[2].Value)));
    }
}
