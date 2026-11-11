using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Endpoints.V1;
using Zaghlol.Testing;
using ProblemAssert = Zaghlol.Api.Tests.Installs.Problems;

namespace Zaghlol.Api.Tests.Purchases;

/// <summary>Pub/Sub pushes for the T-133 tests: Google-shaped OIDC tokens from a fake Google issuer, envelopes and payloads.</summary>
public static class RtdnPushKit
{
    public const string Audience = "https://api.zaghlol.test/v1/notifications/google";
    public const string Account = "rtdn-push@zaghlol-test.iam.gserviceaccount.com";
    public const string Subscription = "projects/zaghlol-test/subscriptions/rtdn-push";
    public const string GoogleJwks = "https://www.googleapis.com/oauth2/v3/certs";

    /// <summary>The header the body-read spy keys its counter on.</summary>
    public const string SpyHeader = "X-Test-Spy";

    public static FakeOidcIssuer NewGoogle() => new(GoogleKeyCache.GoogleIssuer, GoogleJwks);

    public static Dictionary<string, string?> Settings() => new()
    {
        ["Purchases:Google:Rtdn:Audience"] = Audience,
        ["Purchases:Google:Rtdn:PushServiceAccount"] = Account,
        ["Purchases:Google:Rtdn:Subscription"] = Subscription,
        ["RateLimits:GoogleNotifications:TokenLimit"] = "100000",
        ["RateLimits:GoogleNotifications:TokensPerPeriod"] = "100000",
    };

    /// <summary>The endpoint's services with Google's discovery and JWKS served by <paramref name="google"/>.</summary>
    public static void Configure(IServiceCollection services, FakeOidcIssuer google)
    {
        services.AddZaghlolGoogleNotifications();
        services.AddHttpClient(GoogleKeyCache.HttpClientName).ConfigurePrimaryHttpMessageHandler(google.CreateHandler);
    }

    /// <summary>Counts every read of the request body of a request carrying <see cref="SpyHeader"/>, before anything else runs.</summary>
    public static void UseBodySpy(WebApplication application, ConcurrentDictionary<string, int> reads) =>
        application.Use(async (context, next) =>
        {
            if (context.Request.Headers.TryGetValue(SpyHeader, out var id))
            {
                reads.TryAdd(id.ToString(), 0);
                context.Request.Body = new SpyStream(context.Request.Body, () => reads.AddOrUpdate(id.ToString(), 1, (_, n) => n + 1));
            }

            await next(context);
        });

    /// <summary>A Google push token; <paramref name="claims"/> edits the payload (set a member to <c>null</c> to drop it).</summary>
    public static string Token(
        FakeOidcIssuer google,
        DateTimeOffset now,
        Action<Dictionary<string, JsonNode?>>? claims = null,
        string algorithm = "RS256",
        string? kid = null,
        string? issuer = null,
        string? audience = Audience,
        DateTimeOffset? issuedAt = null,
        long lifetimeSeconds = 3600,
        IReadOnlyDictionary<string, JsonNode?>? header = null,
        RSA? foreignKey = null)
    {
        ArgumentNullException.ThrowIfNull(google);
        var extra = new Dictionary<string, JsonNode?>
        {
            ["email"] = Account,
            ["email_verified"] = true,
            ["azp"] = "113774264463038321964",
        };
        claims?.Invoke(extra);
        var token = google.Mint(
            new OperatorTokenSpec
            {
                Subject = "113774264463038321964",
                Amr = null,
                Audience = audience,
                Issuer = issuer,
                Algorithm = algorithm,
                Kid = kid,
                IssuedAt = issuedAt ?? now,
                LifetimeSeconds = lifetimeSeconds,
                OmitNotBefore = true,
                Extra = extra.Where(e => e.Value is not null).ToDictionary(e => e.Key, e => e.Value),
                ExtraHeader = header,
                ForeignKey = foreignKey,
            },
            now);
        return token;
    }

    public static JsonObject Payload(string token, int type = 2, DateTimeOffset? eventTime = null, Action<JsonObject>? edit = null)
    {
        var payload = new JsonObject
        {
            ["version"] = "1.0",
            ["packageName"] = PlayWireMock.Package,
            ["eventTimeMillis"] = (eventTime ?? DateTimeOffset.UtcNow).ToUnixTimeMilliseconds().ToString(System.Globalization.CultureInfo.InvariantCulture),
            ["subscriptionNotification"] = new JsonObject { ["version"] = "1.0", ["notificationType"] = type, ["purchaseToken"] = token },
        };
        edit?.Invoke(payload);
        return payload;
    }

    public static JsonObject Envelope(JsonObject payload, string messageId, DateTimeOffset publishTime, Action<JsonObject>? edit = null)
    {
        var envelope = new JsonObject
        {
            ["message"] = new JsonObject
            {
                ["data"] = Convert.ToBase64String(Encoding.UTF8.GetBytes(payload.ToJsonString())),
                ["messageId"] = messageId,
                ["message_id"] = messageId,
                ["publishTime"] = publishTime.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", System.Globalization.CultureInfo.InvariantCulture),
                ["publish_time"] = publishTime.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", System.Globalization.CultureInfo.InvariantCulture),
                ["attributes"] = new JsonObject(),
            },
            ["subscription"] = Subscription,
            ["deliveryAttempt"] = 1,
        };
        edit?.Invoke(envelope);
        return envelope;
    }

    public static string NewMessageId() => RandomNumberGenerator.GetInt32(1, int.MaxValue).ToString(System.Globalization.CultureInfo.InvariantCulture)
        + RandomNumberGenerator.GetInt32(1, int.MaxValue).ToString(System.Globalization.CultureInfo.InvariantCulture);

    public static async Task<HttpResponseMessage> PostAsync(
        HttpClient client,
        string body,
        string? authorization,
        string? spy = null,
        string contentType = "application/json",
        IReadOnlyList<string>? authorizations = null)
    {
        ArgumentNullException.ThrowIfNull(client);
        using var request = new HttpRequestMessage(HttpMethod.Post, GoogleNotificationEndpoints.Route);
        request.Content = new StringContent(body, Encoding.UTF8);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue(contentType);
        if (authorizations is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", authorizations);
        }
        else if (authorization is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", authorization);
        }

        if (spy is not null)
        {
            request.Headers.Add(SpyHeader, spy);
        }

        return await client.SendAsync(request);
    }

    /// <summary>A read-counting wrapper; every read (sync or async) is counted before it reaches the real body.</summary>
    private sealed class SpyStream(Stream inner, Action onRead) : Stream
    {
        public override bool CanRead => true;

        public override bool CanSeek => false;

        public override bool CanWrite => false;

        public override long Length => throw new NotSupportedException();

        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }

        public override int Read(byte[] buffer, int offset, int count)
        {
            onRead();
            return inner.Read(buffer, offset, count);
        }

        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            onRead();
            return await inner.ReadAsync(buffer, cancellationToken);
        }

        public override Task<int> ReadAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken) =>
            ReadAsync(buffer.AsMemory(offset, count), cancellationToken).AsTask();

        public override void Flush()
        {
        }

        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();

        public override void SetLength(long value) => throw new NotSupportedException();

        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }
}

/// <summary>
/// The push endpoint without a database (the App connection is unreachable): every authentication outcome and every pre-insert
/// outcome is decided before PostgreSQL is touched, and a valid push proves the 503-on-database-failure rule.
/// </summary>
public class GoogleAuthHostFixture : Installs.InstallsHostFixture
{
    public FakeOidcIssuer Google { get; } = RtdnPushKit.NewGoogle();

    public ConcurrentDictionary<string, int> BodyReads { get; } = new(StringComparer.Ordinal);

    protected override bool WithDatabase => false;

    protected override IReadOnlyDictionary<string, string?> Settings
    {
        get
        {
            var settings = new Dictionary<string, string?>(base.Settings)
            {
                ["Purchases:Google:PackageName"] = PlayWireMock.Package,
                ["Purchases:Google:CredentialSource"] = "None",
                ["Purchases:Google:Products:" + PlayWireMock.Monthly + ":Kind"] = "subscription",
                ["Purchases:Google:Products:" + PlayWireMock.Monthly + ":Plan"] = "monthly",
                ["Purchases:Google:Products:" + PlayWireMock.Yearly + ":Kind"] = "subscription",
                ["Purchases:Google:Products:" + PlayWireMock.Yearly + ":Plan"] = "yearly",
                ["Purchases:Google:Products:" + PlayWireMock.Lifetime + ":Kind"] = "onetime",
                ["Purchases:Google:Products:" + PlayWireMock.Lifetime + ":Plan"] = "lifetime",
            };
            foreach (var (key, value) in RtdnPushKit.Settings())
            {
                settings[key] = value;
            }

            return settings;
        }
    }

    protected override void ConfigureServices(IServiceCollection services) => RtdnPushKit.Configure(services, Google);

    protected override void UseBeforePipeline(WebApplication application) => RtdnPushKit.UseBodySpy(application, BodyReads);

    protected override void MapEndpoints(WebApplication application) => application.MapGoogleNotifications();

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            Google.Dispose();
        }

        base.Dispose(disposing);
    }
}

/// <summary>The same host whose Google discovery fails from the start: no key set was ever loaded.</summary>
public sealed class GoogleKeysDownHostFixture : GoogleAuthHostFixture
{
    public GoogleKeysDownHostFixture() => Google.Failing = true;
}

/// <summary>
/// T-133 design note §1 step 2, AC 3: every forged or malformed push token is 401 (503 with no Google keys) with the body never read
/// (a read-counting spy installed before the pipeline), nothing written and no detail in the problem.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class GoogleNotificationAuthTests(GoogleAuthHostFixture fixture) : IClassFixture<GoogleAuthHostFixture>
{
    private FakeOidcIssuer Google => fixture.Google;

    private DateTimeOffset Now => fixture.Clock.GetUtcNow();

    public static TheoryData<string> Forgeries => new()
    {
        "no_header", "two_headers", "basic", "two_segments", "too_long", "alg_none", "alg_hs256", "alg_rs512", "alg_es256", "jku_header",
        "jwk_header", "unknown_kid", "payload_byte", "signature_byte", "foreign_key", "issuer_other", "audience_other", "audience_array",
        "audience_missing", "email_other", "email_case", "email_verified_false", "email_verified_missing", "email_verified_string",
        "expired", "issued_in_future", "exp_missing", "exp_string",
    };

    [Theory]
    [MemberData(nameof(Forgeries))]
    public async Task EveryForgedTokenIsUnauthorizedAndTheBodyIsNeverRead(string forgery)
    {
        var spy = Guid.NewGuid().ToString("N");
        var body = RtdnPushKit.Envelope(RtdnPushKit.Payload("tok.forged"), RtdnPushKit.NewMessageId(), Now).ToJsonString();
        var (authorization, authorizations) = Forge(forgery);

        using var response = await RtdnPushKit.PostAsync(fixture.Client, body, authorization, spy, authorizations: authorizations);

        var text = await ProblemAssert.AssertAsync(response, HttpStatusCode.Unauthorized, "UNAUTHORIZED");
        Assert.DoesNotContain("detail", text, StringComparison.Ordinal);
        Assert.Equal(0, fixture.BodyReads[spy]);
    }

    /// <summary>
    /// §7: each check answers its own fixed outcome word (<c>zaghlol.rtdn.auth{outcome}</c>), so every check is individually
    /// observable (and individually provable: the RS256-only signature parameters and the RSA-only key cache would still refuse an
    /// <c>alg</c> forgery if the header check were missing, but not with <c>bad_alg</c>).
    /// </summary>
    [Theory]
    [InlineData("no_header", "missing")]
    [InlineData("basic", "malformed")]
    [InlineData("two_segments", "malformed")]
    [InlineData("too_long", "malformed")]
    [InlineData("alg_none", "bad_alg")]
    [InlineData("alg_hs256", "bad_alg")]
    [InlineData("alg_rs512", "bad_alg")]
    [InlineData("alg_es256", "bad_alg")]
    [InlineData("unknown_kid", "unknown_kid")]
    [InlineData("signature_byte", "bad_signature")]
    [InlineData("foreign_key", "bad_signature")]
    [InlineData("jwk_header", "bad_signature")]
    [InlineData("issuer_other", "bad_issuer")]
    [InlineData("audience_array", "bad_audience")]
    [InlineData("audience_other", "bad_audience")]
    [InlineData("email_case", "bad_email")]
    [InlineData("email_verified_string", "unverified_email")]
    [InlineData("expired", "expired")]
    [InlineData("issued_in_future", "expired")]
    public async Task EachForgeryIsCountedUnderItsOwnOutcome(string forgery, string outcome)
    {
        var validator = fixture.Services.GetRequiredService<PubSubPushTokenValidator>();
        var (single, many) = Forge(forgery);
        var header = many is not null
            ? new Microsoft.Extensions.Primitives.StringValues([.. many])
            : single is null ? Microsoft.Extensions.Primitives.StringValues.Empty : new Microsoft.Extensions.Primitives.StringValues(single);

        Assert.Equal(outcome, await validator.ValidateAsync(header, CancellationToken.None));
        Assert.Equal("ok", await validator.ValidateAsync(new Microsoft.Extensions.Primitives.StringValues("Bearer " + RtdnPushKit.Token(Google, Now)), CancellationToken.None));
    }

    /// <summary>Positive control for the spy: an authenticated push is read (and, with no database, answered 503 so Pub/Sub retries).</summary>
    [Fact]
    public async Task AValidPushIsReadAndADatabaseFailureIs503()
    {
        var spy = Guid.NewGuid().ToString("N");
        var body = RtdnPushKit.Envelope(RtdnPushKit.Payload("tok.valid"), RtdnPushKit.NewMessageId(), Now).ToJsonString();

        using var response = await RtdnPushKit.PostAsync(fixture.Client, body, "Bearer " + RtdnPushKit.Token(Google, Now), spy);

        await ProblemAssert.AssertAsync(response, HttpStatusCode.ServiceUnavailable, "UPSTREAM_UNAVAILABLE");
        Assert.NotNull(response.Headers.RetryAfter);
        Assert.True(fixture.BodyReads[spy] > 0);
    }

    [Theory]
    [InlineData("accounts.google.com")]
    [InlineData("https://accounts.google.com")]
    public async Task BothGoogleIssuerFormsAreAccepted(string issuer)
    {
        var body = RtdnPushKit.Envelope(RtdnPushKit.Payload("tok.issuer"), "not:a-message-id", Now).ToJsonString();

        using var response = await RtdnPushKit.PostAsync(fixture.Client, body, "Bearer " + RtdnPushKit.Token(Google, Now, issuer: issuer));

        // Authenticated; the envelope is then ignored (malformed messageId) without touching the database.
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
    }

    [Fact]
    public async Task ATokenAtTheSkewLimitsIsAccepted()
    {
        var body = RtdnPushKit.Envelope(RtdnPushKit.Payload("tok.edge"), "x:y", Now).ToJsonString();
        var lateExp = RtdnPushKit.Token(Google, Now, issuedAt: Now.AddSeconds(-3659), lifetimeSeconds: 3600);
        var earlyIat = RtdnPushKit.Token(Google, Now, issuedAt: Now.AddMinutes(5));

        using var a = await RtdnPushKit.PostAsync(fixture.Client, body, "Bearer " + lateExp);
        using var b = await RtdnPushKit.PostAsync(fixture.Client, body, "Bearer " + earlyIat);

        Assert.Equal(HttpStatusCode.NoContent, a.StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, b.StatusCode);
    }

    public static TheoryData<string> Ignored => new()
    {
        "not_json", "text_plain", "too_large", "array", "no_message", "message_id_colon", "stale", "future", "other_package",
        "other_subscription", "two_kinds", "bad_token", "data_not_base64",
    };

    /// <summary>§1 step 3: after authentication every unusable push is 204 (never a nack), not stored (no database touched here).</summary>
    [Theory]
    [MemberData(nameof(Ignored))]
    public async Task AnAuthenticatedButUnusablePushIsAcknowledgedWith204(string defect)
    {
        var token = RtdnPushKit.Token(Google, Now);
        var payload = RtdnPushKit.Payload("tok.ignored");
        var id = RtdnPushKit.NewMessageId();
        var (body, contentType) = defect switch
        {
            "not_json" => ("not json", "application/json"),
            "text_plain" => (RtdnPushKit.Envelope(payload, id, Now).ToJsonString(), "text/plain"),
            "too_large" => ("{\"message\":{\"data\":\"" + new string('A', 300 * 1024) + "\"}}", "application/json"),
            "array" => ("[]", "application/json"),
            "no_message" => ("{\"subscription\":\"" + RtdnPushKit.Subscription + "\"}", "application/json"),
            "message_id_colon" => (RtdnPushKit.Envelope(payload, "sweep:1", Now).ToJsonString(), "application/json"),
            "stale" => (RtdnPushKit.Envelope(payload, id, Now.AddDays(-33)).ToJsonString(), "application/json"),
            "future" => (RtdnPushKit.Envelope(payload, id, Now.AddMinutes(6)).ToJsonString(), "application/json"),
            "other_package" => (RtdnPushKit.Envelope(RtdnPushKit.Payload("tok.x", edit: p => p["packageName"] = "com.other"), id, Now).ToJsonString(), "application/json"),
            "other_subscription" => (RtdnPushKit.Envelope(payload, id, Now, e => e["subscription"] = "projects/other-proj/subscriptions/rtdn").ToJsonString(), "application/json"),
            "two_kinds" => (RtdnPushKit.Envelope(RtdnPushKit.Payload("tok.x", edit: p => p["testNotification"] = new JsonObject()), id, Now).ToJsonString(), "application/json"),
            "bad_token" => (RtdnPushKit.Envelope(RtdnPushKit.Payload("tok/../x"), id, Now).ToJsonString(), "application/json"),
            "data_not_base64" => (RtdnPushKit.Envelope(payload, id, Now, e => e["message"]!["data"] = "%%%").ToJsonString(), "application/json"),
            _ => throw new ArgumentOutOfRangeException(nameof(defect)),
        };

        using var response = await RtdnPushKit.PostAsync(fixture.Client, body, "Bearer " + token, contentType: contentType);

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Empty(await response.Content.ReadAsByteArrayAsync());
    }

    [Fact]
    public async Task AnUnknownKidRefreshesAtMostOncePerFiveMinutes()
    {
        var body = RtdnPushKit.Envelope(RtdnPushKit.Payload("tok.kid"), RtdnPushKit.NewMessageId(), Now).ToJsonString();
        using (await RtdnPushKit.PostAsync(fixture.Client, body, "Bearer " + RtdnPushKit.Token(Google, Now, kid: "warm-up")))
        {
        }

        var before = Google.DiscoveryRequests;
        fixture.Clock.Advance(OidcKeyCache.RefreshThrottle);
        using var first = await RtdnPushKit.PostAsync(fixture.Client, body, "Bearer " + RtdnPushKit.Token(Google, Now, kid: "made-up-1"));
        using var second = await RtdnPushKit.PostAsync(fixture.Client, body, "Bearer " + RtdnPushKit.Token(Google, Now, kid: "made-up-2"));

        Assert.Equal(HttpStatusCode.Unauthorized, first.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, second.StatusCode);
        Assert.Equal(before + 1, Google.DiscoveryRequests);
    }

    [Fact]
    public async Task TheRtdnRouteHasNoInstallTokenAndIgnoresAnyOtherHeaders()
    {
        var body = RtdnPushKit.Envelope(RtdnPushKit.Payload("tok.hdr"), "bad:id", Now).ToJsonString();

        using var response = await RtdnPushKit.PostAsync(fixture.Client, body, "Bearer " + RtdnPushKit.Token(Google, Now));

        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Equal("no-store", response.Headers.CacheControl?.ToString());
    }

    private (string? Single, IReadOnlyList<string>? Many) Forge(string forgery)
    {
        var good = RtdnPushKit.Token(Google, Now);
        var parts = good.Split('.');
        string Flip(string s, int i)
        {
            var chars = s.ToCharArray();
            chars[i] = chars[i] == 'A' ? 'B' : 'A';
            return new string(chars);
        }

        using var foreign = RSA.Create(2048);
        var foreignJwk = new JsonObject
        {
            ["kty"] = "RSA",
            ["n"] = System.Buffers.Text.Base64Url.EncodeToString(foreign.ExportParameters(false).Modulus!),
            ["e"] = System.Buffers.Text.Base64Url.EncodeToString(foreign.ExportParameters(false).Exponent!),
        };

        return forgery switch
        {
            "no_header" => (null, null),
            "two_headers" => (null, ["Bearer " + good, "Bearer " + good]),
            "basic" => ("Basic " + Convert.ToBase64String("a:b"u8.ToArray()), null),
            "two_segments" => ("Bearer " + parts[0] + "." + parts[1], null),
            "too_long" => ("Bearer " + good + new string('A', 4097 - 7 - good.Length), null),
            "alg_none" => ("Bearer " + RtdnPushKit.Token(Google, Now, algorithm: "none", kid: Google.RsaKid), null),
            "alg_hs256" => ("Bearer " + RtdnPushKit.Token(Google, Now, algorithm: "HS256", kid: Google.RsaKid), null),
            "alg_rs512" => ("Bearer " + Resign(h => h["alg"] = "RS512"), null),
            "alg_es256" => ("Bearer " + RtdnPushKit.Token(Google, Now, algorithm: "ES256"), null),
            "jku_header" => ("Bearer " + RtdnPushKit.Token(Google, Now, foreignKey: foreign, header: new Dictionary<string, JsonNode?> { ["jku"] = "https://evil.example/jwks" }), null),
            "jwk_header" => ("Bearer " + RtdnPushKit.Token(Google, Now, foreignKey: foreign, header: new Dictionary<string, JsonNode?> { ["jwk"] = foreignJwk }), null),
            "unknown_kid" => ("Bearer " + RtdnPushKit.Token(Google, Now, kid: "not-a-google-kid"), null),
            "payload_byte" => ("Bearer " + parts[0] + "." + Flip(parts[1], 10) + "." + parts[2], null),
            "signature_byte" => ("Bearer " + parts[0] + "." + parts[1] + "." + Flip(parts[2], 5), null),
            "foreign_key" => ("Bearer " + RtdnPushKit.Token(Google, Now, foreignKey: foreign), null),
            "issuer_other" => ("Bearer " + RtdnPushKit.Token(Google, Now, issuer: "https://accounts.google.com.evil.example"), null),
            "audience_other" => ("Bearer " + RtdnPushKit.Token(Google, Now, audience: "https://api.zaghlol.test/v1/notifications/apple"), null),
            "audience_array" => ("Bearer " + RtdnPushKit.Token(Google, Now, audience: null, claims: c => c["aud"] = new JsonArray(RtdnPushKit.Audience)), null),
            "audience_missing" => ("Bearer " + RtdnPushKit.Token(Google, Now, audience: null), null),
            "email_other" => ("Bearer " + RtdnPushKit.Token(Google, Now, claims: c => c["email"] = "attacker@evil-proj.iam.gserviceaccount.com"), null),
            "email_case" => ("Bearer " + RtdnPushKit.Token(Google, Now, claims: c => c["email"] = RtdnPushKit.Account.ToUpperInvariant()), null),
            "email_verified_false" => ("Bearer " + RtdnPushKit.Token(Google, Now, claims: c => c["email_verified"] = false), null),
            "email_verified_missing" => ("Bearer " + RtdnPushKit.Token(Google, Now, claims: c => c["email_verified"] = null), null),
            "email_verified_string" => ("Bearer " + RtdnPushKit.Token(Google, Now, claims: c => c["email_verified"] = "true"), null),
            "expired" => ("Bearer " + RtdnPushKit.Token(Google, Now, issuedAt: Now.AddSeconds(-3661), lifetimeSeconds: 3600), null),
            "issued_in_future" => ("Bearer " + RtdnPushKit.Token(Google, Now, issuedAt: Now.AddMinutes(6)), null),
            "exp_missing" => ("Bearer " + Google.Mint(new OperatorTokenSpec { Subject = "s", Amr = null, Audience = RtdnPushKit.Audience, Issuer = GoogleKeyCache.GoogleIssuer, OmitExpiry = true, OmitNotBefore = true, Extra = new Dictionary<string, JsonNode?> { ["email"] = RtdnPushKit.Account, ["email_verified"] = true } }, Now), null),
            "exp_string" => ("Bearer " + RtdnPushKit.Token(Google, Now, claims: c => c["exp"] = Now.AddHours(1).ToUnixTimeSeconds().ToString(System.Globalization.CultureInfo.InvariantCulture)), null),
            _ => throw new ArgumentOutOfRangeException(nameof(forgery)),
        };

        string Resign(Action<JsonObject> header)
        {
            var h = JsonNode.Parse(System.Buffers.Text.Base64Url.DecodeFromChars(parts[0]))!.AsObject();
            header(h);
            var input = System.Buffers.Text.Base64Url.EncodeToString(Encoding.UTF8.GetBytes(h.ToJsonString())) + "." + parts[1];
            using var rsa = RSA.Create(2048);
            return input + "." + System.Buffers.Text.Base64Url.EncodeToString(rsa.SignData(Encoding.ASCII.GetBytes(input), HashAlgorithmName.SHA512, RSASignaturePadding.Pkcs1));
        }
    }
}

/// <summary>§1 step 2: with no Google key set at all, a push is 503 (Pub/Sub retries; fail closed but recoverable), the body unread.</summary>
[Collection(ApiHostGroup.Name)]
public class GoogleKeysUnavailableTests(GoogleKeysDownHostFixture fixture) : IClassFixture<GoogleKeysDownHostFixture>
{
    [Fact]
    public async Task NoUsableKeysIs503WithRetryAfterAndTheBodyUnread()
    {
        var spy = Guid.NewGuid().ToString("N");
        var now = fixture.Clock.GetUtcNow();
        var body = RtdnPushKit.Envelope(RtdnPushKit.Payload("tok.keys"), RtdnPushKit.NewMessageId(), now).ToJsonString();

        using var response = await RtdnPushKit.PostAsync(fixture.Client, body, "Bearer " + RtdnPushKit.Token(fixture.Google, now), spy);

        await ProblemAssert.AssertAsync(response, HttpStatusCode.ServiceUnavailable, "UPSTREAM_UNAVAILABLE");
        Assert.Equal(TimeSpan.FromSeconds(PubSubPushAuthenticationHandler.KeysUnavailableRetryAfterSeconds), response.Headers.RetryAfter?.Delta);
        Assert.Equal(0, fixture.BodyReads[spy]);

        // A token malformed before any key lookup stays a plain 401.
        using var forged = await RtdnPushKit.PostAsync(fixture.Client, body, "Bearer a.b.c");
        Assert.Equal(HttpStatusCode.Unauthorized, forged.StatusCode);
    }
}
