using System.Net;
using System.Text.Json;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Idempotency;
using Zaghlol.Api.Tests.Installs;
using Zaghlol.Application.Flags;
using Zaghlol.Domain;
using TestProblems = Zaghlol.Api.Tests.Installs.Problems;

namespace Zaghlol.Api.Tests.Flags;

/// <summary>
/// T-126: <c>GET/PUT /admin/v1/flags/{key}</c> through the real pipeline. State is per flag: <c>roi_named_products</c> is never
/// written (the default-OFF test), <c>zakah</c> is the round-trip flag, <c>smart_roi</c> the versioning flag.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class FlagAdminEndpointTests(AdminFlagFixture fixture) : IClassFixture<AdminFlagFixture>
{
    private const string FlagsAdmin = OperatorRoles.FlagsAdmin;

    private static string Put(string value, string? rules = null) =>
        rules is null ? $"{{\"value\":{value}}}" : $"{{\"value\":{value},\"rules\":{rules}}}";

    [Fact]
    public async Task ANeverSetKnownFlagIsOffWithNoRulesAndVersionZero()
    {
        var (_, token) = await fixture.NewOperatorAsync(FlagsAdmin);

        using var response = await fixture.SendAsync(HttpMethod.Get, "/admin/v1/flags/roi_named_products", token);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.NoStore);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var root = json.RootElement;
        Assert.Equal("roi_named_products", root.GetProperty("key").GetString());
        Assert.False(root.GetProperty("value").GetBoolean());
        Assert.Equal(JsonValueKind.Object, root.GetProperty("rules").ValueKind);
        Assert.Empty(root.GetProperty("rules").EnumerateObject());
        Assert.Equal(0, root.GetProperty("version").GetInt32());
        Assert.EndsWith("Z", root.GetProperty("updatedAt").GetString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task PutWithRulesRoundTripsThroughGetIsAuditedAndPostedToTheOpsChannel()
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(FlagsAdmin);
        const string Rules = "{\"platforms\":[\"android\"],\"minAppVersion\":\"1.4.0\",\"rolloutPercent\":10}";
        var postedBefore = fixture.Notifier.Posted.Count;

        using var put = await fixture.SendAsync(HttpMethod.Put, "/admin/v1/flags/zakah", token, Put("true", Rules));
        using var get = await fixture.SendAsync(HttpMethod.Get, "/admin/v1/flags/zakah", token);

        Assert.Equal(HttpStatusCode.OK, put.StatusCode);
        Assert.Equal(HttpStatusCode.OK, get.StatusCode);
        var putBody = await put.Content.ReadAsStringAsync();
        var getBody = await get.Content.ReadAsStringAsync();
        using var putJson = JsonDocument.Parse(putBody);
        using var getJson = JsonDocument.Parse(getBody);
        foreach (var json in new[] { putJson, getJson })
        {
            var root = json.RootElement;
            Assert.True(root.GetProperty("value").GetBoolean());
            Assert.True(root.GetProperty("version").GetInt32() >= 1);
            var rules = root.GetProperty("rules");
            Assert.Equal("android", Assert.Single(rules.GetProperty("platforms").EnumerateArray()).GetString());
            Assert.Equal("1.4.0", rules.GetProperty("minAppVersion").GetString());
            Assert.Equal(10, rules.GetProperty("rolloutPercent").GetInt32());
            Assert.Equal(3, rules.EnumerateObject().Count());
        }

        Assert.Equal(putJson.RootElement.GetProperty("rules").GetRawText(), getJson.RootElement.GetProperty("rules").GetRawText());
        Assert.Equal(putJson.RootElement.GetProperty("version").GetInt32(), getJson.RootElement.GetProperty("version").GetInt32());
        Assert.Equal(1, await fixture.AuditCountAsync(operatorId));
        var posted = fixture.Notifier.Posted.Skip(postedBefore).Single();
        Assert.Equal("zakah", posted.Key);
        Assert.True(posted.Value);
    }

    [Fact]
    public async Task PutAndGetNeedNoIdempotencyKey()
    {
        var (_, token) = await fixture.NewOperatorAsync(FlagsAdmin);

        using var put = await fixture.SendAsync(HttpMethod.Put, "/admin/v1/flags/smart_roi", token, Put("false"));

        Assert.Equal(HttpStatusCode.OK, put.StatusCode);
    }

    [Fact]
    public async Task EachPutIncrementsTheVersionAndRulesAreKeptWhenAbsentAndReplacedWhenPresent()
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(FlagsAdmin);
        const string Path = "/admin/v1/flags/smart_roi";

        var first = await VersionAndRules(await fixture.SendAsync(HttpMethod.Put, Path, token, Put("true", "{\"rolloutPercent\":25}")));
        var kept = await VersionAndRules(await fixture.SendAsync(HttpMethod.Put, Path, token, Put("false")));
        var replaced = await VersionAndRules(await fixture.SendAsync(HttpMethod.Put, Path, token, Put("true", "{\"platforms\":[\"ios\"]}")));
        var cleared = await VersionAndRules(await fixture.SendAsync(HttpMethod.Put, Path, token, Put("true", "{}")));

        Assert.Equal(first.Version + 1, kept.Version);
        Assert.Equal(kept.Version + 1, replaced.Version);
        Assert.Equal(replaced.Version + 1, cleared.Version);
        Assert.Equal("{\"rolloutPercent\":25}", first.Rules);
        Assert.Equal("{\"rolloutPercent\":25}", kept.Rules);
        Assert.Equal("{\"platforms\":[\"ios\"]}", replaced.Rules);
        Assert.Equal("{}", cleared.Rules);
        Assert.Equal(4, await fixture.AuditCountAsync(operatorId));
    }

    [Theory]
    [InlineData("{\"value\":true,\"rules\":{\"platforms\":[\"android\"],\"audience\":\"beta\"}}")]
    [InlineData("{\"value\":true,\"rules\":{\"rolloutPercent\":5,\"nested\":{\"x\":1}}}")]
    [InlineData("{\"value\":true,\"rules\":{\"minAppVersion\":\"1.0.0\",\"MinAppVersion\":\"1.0.0\"}}")]
    [InlineData("{\"value\":true,\"extra\":1}")]
    [InlineData("{\"value\":true,\"rules\":{\"platforms\":[\"android\"]},\"messages\":[]}")]
    public async Task AnUnknownMemberAnywhereIs400UnknownFieldAndChangesNothing(string body)
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(FlagsAdmin);

        using var response = await fixture.SendAsync(HttpMethod.Put, "/admin/v1/flags/zakah", token, body);

        var text = await TestProblems.AssertAsync(response, HttpStatusCode.BadRequest, "UNKNOWN_FIELD");
        Assert.DoesNotContain("audience", text, StringComparison.Ordinal);
        Assert.Equal(0, await fixture.AuditCountAsync(operatorId));
    }

    [Theory]
    [InlineData("{\"rules\":{}}")]
    [InlineData("{\"value\":\"true\"}")]
    [InlineData("{\"value\":1}")]
    [InlineData("{\"value\":true,\"rules\":{\"rolloutPercent\":101}}")]
    [InlineData("{\"value\":true,\"rules\":{\"rolloutPercent\":-1}}")]
    [InlineData("{\"value\":true,\"rules\":{\"rolloutPercent\":\"10\"}}")]
    [InlineData("{\"value\":true,\"rules\":{\"rolloutPercent\":10.5}}")]
    [InlineData("{\"value\":true,\"rules\":{\"platforms\":[]}}")]
    [InlineData("{\"value\":true,\"rules\":{\"platforms\":[\"android\",\"android\"]}}")]
    [InlineData("{\"value\":true,\"rules\":{\"platforms\":[\"windows\"]}}")]
    [InlineData("{\"value\":true,\"rules\":{\"minAppVersion\":\"1.4\"}}")]
    [InlineData("{\"value\":true,\"rules\":{\"minAppVersion\":\"1.4.0-beta\"}}")]
    [InlineData("{\"value\":true,\"rules\":[]}")]
    [InlineData("[]")]
    [InlineData("not json")]
    [InlineData("")]
    public async Task AnInvalidBodyIs400ValidationFailedAndChangesNothing(string body)
    {
        var (operatorId, token) = await fixture.NewOperatorAsync(FlagsAdmin);

        using var response = await fixture.SendAsync(HttpMethod.Put, "/admin/v1/flags/zakah", token, body);

        await TestProblems.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        Assert.Equal(0, await fixture.AuditCountAsync(operatorId));
    }

    [Fact]
    public async Task UnknownAndMalformedKeys()
    {
        var (_, token) = await fixture.NewOperatorAsync(FlagsAdmin);

        foreach (var method in new[] { HttpMethod.Get, HttpMethod.Put })
        {
            var body = method == HttpMethod.Put ? Put("true") : null;
            using var unknown = await fixture.SendAsync(method, "/admin/v1/flags/not_a_flag", token, body);
            await TestProblems.AssertAsync(unknown, HttpStatusCode.NotFound, "NOT_FOUND");

            foreach (var key in new[] { "Zakah", "a", "2zakah", "zakah%0A", "za-kah", new string('a', 65) })
            {
                using var malformed = await fixture.SendAsync(method, "/admin/v1/flags/" + key, token, body);
                await TestProblems.AssertAsync(malformed, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
            }
        }
    }

    [Fact]
    public async Task AWrongContentTypeIs415AndAnOversizedBodyIs413()
    {
        var (_, token) = await fixture.NewOperatorAsync(FlagsAdmin);

        using var wrongType = await fixture.SendAsync(HttpMethod.Put, "/admin/v1/flags/zakah", token, Put("true"), "text/plain");
        using var tooLarge = await fixture.SendAsync(HttpMethod.Put, "/admin/v1/flags/zakah", token, "{\"value\":true,\"pad\":\"" + new string('a', 70_000) + "\"}");

        await TestProblems.AssertAsync(wrongType, HttpStatusCode.UnsupportedMediaType, "UNSUPPORTED_MEDIA_TYPE");
        await TestProblems.AssertAsync(tooLarge, HttpStatusCode.RequestEntityTooLarge, "PAYLOAD_TOO_LARGE");
    }

    [Fact]
    public async Task MissingMalformedAndUnknownTokensGetOneIdenticalUnauthorizedBody()
    {
        var bodies = new List<string>();
        foreach (var authorization in new string?[] { null, "Bearer", "Bearer ", "Basic abc", "Bearer not-a-known-token", "Bearer " + new string('x', 9000), "Bearer a b" })
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, "/admin/v1/flags/zakah");
            if (authorization is not null)
            {
                request.Headers.TryAddWithoutValidation("Authorization", authorization);
            }

            using var response = await fixture.Client.SendAsync(request);
            var text = await TestProblems.AssertAsync(response, HttpStatusCode.Unauthorized, "UNAUTHORIZED");
            Assert.Equal("Bearer", response.Headers.WwwAuthenticate.ToString());
            bodies.Add(TestProblems.WithoutCorrelationId(text));
        }

        Assert.Single(bodies.Distinct(StringComparer.Ordinal));
    }

    [Fact]
    public async Task AValidOperatorWithoutTheFlagsAdminRoleIs403ForBothOperations()
    {
        var (operatorId, token) = await fixture.NewOperatorAsync("catalog_editor", "prices_admin", "support_viewer");

        using var get = await fixture.SendAsync(HttpMethod.Get, "/admin/v1/flags/zakah", token);
        using var put = await fixture.SendAsync(HttpMethod.Put, "/admin/v1/flags/zakah", token, Put("true"));

        await TestProblems.AssertAsync(get, HttpStatusCode.Forbidden, "FORBIDDEN");
        await TestProblems.AssertAsync(put, HttpStatusCode.Forbidden, "FORBIDDEN");
        Assert.Equal(0, await fixture.AuditCountAsync(operatorId));
    }

    [Fact]
    public async Task AnInstallTokenIsNotAnOperatorToken()
    {
        using var register = new HttpRequestMessage(HttpMethod.Post, "/v1/installs")
        {
            Content = new StringContent(InstallsHostFixture.InstallBody(InstallsHostFixture.NewInstallId()), System.Text.Encoding.UTF8, "application/json"),
        };
        register.Headers.Add(IdempotencyKeys.HeaderName, InstallsHostFixture.NewKey());
        using var registered = await fixture.Client.SendAsync(register);
        Assert.Equal(HttpStatusCode.Created, registered.StatusCode);
        var installToken = await InstallsHostFixture.TokenOf(registered);

        using var response = await fixture.SendAsync(HttpMethod.Get, "/admin/v1/flags/zakah", installToken);

        await TestProblems.AssertAsync(response, HttpStatusCode.Unauthorized, "UNAUTHORIZED");
    }

    [Fact]
    public async Task TheStoredFlagDrivesTheSyncSnapshotForTargetedInstalls()
    {
        var (_, token) = await fixture.NewOperatorAsync(FlagsAdmin);
        using var put = await fixture.SendAsync(HttpMethod.Put, "/admin/v1/flags/zakah", token, Put("true", "{\"platforms\":[\"android\"],\"minAppVersion\":\"1.4.0\",\"rolloutPercent\":100}"));
        Assert.Equal(HttpStatusCode.OK, put.StatusCode);
        var reader = (IFlagReader)fixture.Services.GetService(typeof(IFlagReader))!;
        var installId = InstallId.Parse(Guid.NewGuid().ToString("D"));

        var stored = await reader.ListAsync(CancellationToken.None);

        Assert.True(FlagEvaluator.Snapshot(stored, "android", "1.4.0", installId).Values["zakah"]);
        Assert.False(FlagEvaluator.Snapshot(stored, "ios", "1.4.0", installId).Values["zakah"]);
        Assert.False(FlagEvaluator.Snapshot(stored, "android", "1.3.9", installId).Values["zakah"]);
    }

    private static async Task<(int Version, string Rules)> VersionAndRules(HttpResponseMessage response)
    {
        using (response)
        {
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            return (json.RootElement.GetProperty("version").GetInt32(), json.RootElement.GetProperty("rules").GetRawText());
        }
    }
}

/// <summary>T-126: the admin routes are rate limited per operator, after authentication.</summary>
[Collection(ApiHostGroup.Name)]
public class FlagAdminRateLimitTests(RateLimitedAdminFlagFixture fixture) : IClassFixture<RateLimitedAdminFlagFixture>
{
    [Fact]
    public async Task AnOperatorOverItsBurstGets429AndAnotherOperatorDoesNot()
    {
        var (_, busy) = await fixture.NewOperatorAsync(OperatorRoles.FlagsAdmin);
        var (_, other) = await fixture.NewOperatorAsync(OperatorRoles.FlagsAdmin);

        for (var i = 0; i < 3; i++)
        {
            using var allowed = await fixture.SendAsync(HttpMethod.Get, "/admin/v1/flags/zakah", busy);
            Assert.Equal(HttpStatusCode.OK, allowed.StatusCode);
        }

        using var limited = await fixture.SendAsync(HttpMethod.Get, "/admin/v1/flags/zakah", busy);
        using var unaffected = await fixture.SendAsync(HttpMethod.Get, "/admin/v1/flags/zakah", other);

        var text = await TestProblems.AssertAsync(limited, HttpStatusCode.TooManyRequests, "RATE_LIMITED");
        Assert.NotNull(limited.Headers.RetryAfter);
        Assert.DoesNotContain(busy, text, StringComparison.Ordinal);
        Assert.Equal(HttpStatusCode.OK, unaffected.StatusCode);
    }
}

/// <summary>T-126: with no operator validator configured (the default until T-136), the admin API is closed.</summary>
[Collection(ApiHostGroup.Name)]
public class FlagAdminDefaultClosedTests(ApiFixture fixture) : IClassFixture<ApiFixture>
{
    [Fact]
    public async Task EveryAdminCallIs401WithTheDefaultValidator()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/admin/v1/flags/zakah");
        request.Headers.TryAddWithoutValidation("Authorization", "Bearer eyJhbGciOiJFUzI1NiJ9.e30.c2ln");

        using var response = await fixture.Client.SendAsync(request);

        await TestProblems.AssertAsync(response, HttpStatusCode.Unauthorized, "UNAUTHORIZED");
    }
}
