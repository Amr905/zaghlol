using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using WireMock.RequestBuilders;
using WireMock.ResponseBuilders;
using Zaghlol.Application.Purchases.Attestation;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Attestation;
using Zaghlol.Infrastructure.Tests.GooglePlay;
using Zaghlol.Infrastructure.Tests.Seats;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Attestation;

/// <summary>T-181 Play Integrity: one test per rule over a fake decoder, then the real client against WireMock.</summary>
public sealed class PlayIntegrityVerifierTests
{
    private const string Package = PlayWireMock.Package;
    private static readonly DateTimeOffset Now = new(2026, 11, 13, 12, 0, 0, TimeSpan.Zero);
    private static readonly byte[] BodyHash = SHA256.HashData("restore body"u8);

    [Fact]
    public async Task AValidDeviceTokenVerifiesAsDeviceAndTakesAReplayRow()
    {
        var replay = new MemoryReplayGuard();
        var result = await Verifier(Payload(), replay).VerifyAsync(Token("t1"), BodyHash, default);

        Assert.True(result.IsVerified);
        Assert.Equal(ProofLevel.Device, result.Level);
        var row = Assert.Single(replay.Rows);
        Assert.Equal(SHA256.HashData("t1"u8), row.Key);
        Assert.Equal(Now.AddMinutes(15), row.Value);
    }

    [Fact]
    public async Task ARequestHashForAnotherBodyIsHashMismatch() =>
        await AssertFails(Payload(requestHash: PlayIntegrityVerifier.Base64Url(SHA256.HashData("other body"u8))), AttestationFailure.HashMismatch);

    [Fact]
    public async Task AnotherPackageIsAppUnrecognized() =>
        await AssertFails(Payload(package: "app.zaghlol.fake"), AttestationFailure.AppUnrecognized);

    [Fact]
    public async Task ASixMinuteOldTimestampIsStale() =>
        await AssertFails(Payload(issued: Now.AddMinutes(-6)), AttestationFailure.Stale);

    [Fact]
    public async Task AFourMinuteOldTimestampStillVerifies()
    {
        var result = await Verifier(Payload(issued: Now.AddMinutes(-4))).VerifyAsync(Token("t"), BodyHash, default);
        Assert.True(result.IsVerified);
    }

    [Fact]
    public async Task ATimestampFromTheFutureIsStale() =>
        await AssertFails(Payload(issued: Now.AddMinutes(2)), AttestationFailure.Stale);

    [Theory]
    [InlineData("UNRECOGNIZED_VERSION")]
    [InlineData("UNEVALUATED")]
    [InlineData(null)]
    public async Task AnAppNotPlayRecognizedIsAppUnrecognized(string? verdict) =>
        await AssertFails(Payload(appVerdict: verdict), AttestationFailure.AppUnrecognized);

    [Fact]
    public async Task BasicOnlyVerifiesAsBasic()
    {
        var result = await Verifier(Payload(labels: ["MEETS_BASIC_INTEGRITY"])).VerifyAsync(Token("t"), BodyHash, default);
        Assert.True(result.IsVerified);
        Assert.Equal(ProofLevel.Basic, result.Level);
    }

    [Fact]
    public async Task NoLabelIsNoIntegrity() => await AssertFails(Payload(labels: []), AttestationFailure.NoIntegrity);

    [Fact]
    public async Task AReplayedTokenIsReplayed()
    {
        var replay = new MemoryReplayGuard();
        var verifier = Verifier(Payload(), replay);
        Assert.True((await verifier.VerifyAsync(Token("same"), BodyHash, default)).IsVerified);

        var second = await verifier.VerifyAsync(Token("same"), BodyHash, default);
        Assert.Equal(AttestationFailure.Replayed, second.Failure);
    }

    [Fact]
    public async Task AFailingTokenTakesNoReplayRow()
    {
        var replay = new MemoryReplayGuard();
        await Verifier(Payload(labels: []), replay).VerifyAsync(Token("t"), BodyHash, default);
        Assert.Empty(replay.Rows);
    }

    [Fact]
    public async Task AnUpstreamOutageIsUnavailableAndTakesNoRow()
    {
        var replay = new MemoryReplayGuard();
        var verifier = new PlayIntegrityVerifier(
            new FixedDecoder(new PlayIntegrityDecode(PlayIntegrityDecodeStatus.Unavailable, null)),
            replay,
            Options(),
            new ManualTime(Now),
            NullLogger<PlayIntegrityVerifier>.Instance);

        var result = await verifier.VerifyAsync(Token("t"), BodyHash, default);
        Assert.Equal(AttestationOutcome.Unavailable, result.Outcome);
        Assert.Null(result.Failure);
        Assert.Empty(replay.Rows);
    }

    internal static JsonObject Payload(
        string package = Package,
        string? requestHash = null,
        DateTimeOffset? issued = null,
        string? appVerdict = "PLAY_RECOGNIZED",
        string[]? labels = null,
        bool optionalVerdicts = false,
        string sentinel = "")
    {
        var payload = new JsonObject
        {
            ["requestDetails"] = new JsonObject
            {
                ["requestPackageName"] = package,
                ["requestHash"] = requestHash ?? PlayIntegrityVerifier.Base64Url(BodyHash),
                ["timestampMillis"] = (issued ?? Now.AddSeconds(-10)).ToUnixTimeMilliseconds().ToString(System.Globalization.CultureInfo.InvariantCulture),
            },
            ["appIntegrity"] = new JsonObject
            {
                ["appRecognitionVerdict"] = appVerdict,
                ["packageName"] = package,
                ["certificateSha256Digest"] = new JsonArray("6a6a1474b5cbbb2b1aa57e0bc3"),
                ["versionCode"] = "42",
            },
            ["deviceIntegrity"] = new JsonObject
            {
                ["deviceRecognitionVerdict"] = new JsonArray([.. (labels ?? ["MEETS_DEVICE_INTEGRITY", "MEETS_BASIC_INTEGRITY"]).Select(l => (JsonNode)l)]),
            },
            ["accountDetails"] = new JsonObject { ["appLicensingVerdict"] = "LICENSED" },
        };
        if (optionalVerdicts)
        {
            ((JsonObject)payload["deviceIntegrity"]!)["deviceAttributes"] = new JsonObject { ["sdkVersion"] = 34, ["marker"] = sentinel + "-attr" };
            ((JsonObject)payload["deviceIntegrity"]!)["recentDeviceActivity"] = new JsonObject { ["deviceActivityLevel"] = sentinel + "-activity" };
            payload["appAccessRiskVerdict"] = new JsonObject { ["appsDetected"] = new JsonArray(sentinel + "-risk") };
            payload["environmentDetails"] = new JsonObject { ["playProtectVerdict"] = sentinel + "-protect" };
        }

        return new JsonObject { ["tokenPayloadExternal"] = payload };
    }

    internal static Sensitive<string> Token(string value) => new(value);

    private static PlayIntegrityOptions Options() => new() { PackageName = Package, BaseUrl = new Uri("http://127.0.0.1/") };

    private static PlayIntegrityVerifier Verifier(JsonObject response, MemoryReplayGuard? replay = null)
    {
        var dto = System.Text.Json.JsonSerializer.Deserialize(response.ToJsonString(), PlayIntegrityJsonContext.Default.DecodeIntegrityTokenResponseDto)!;
        return new PlayIntegrityVerifier(
            new FixedDecoder(new PlayIntegrityDecode(PlayIntegrityDecodeStatus.Decoded, dto.TokenPayloadExternal)),
            replay ?? new MemoryReplayGuard(),
            Options(),
            new ManualTime(Now),
            NullLogger<PlayIntegrityVerifier>.Instance);
    }

    private static async Task AssertFails(JsonObject response, AttestationFailure failure)
    {
        var result = await Verifier(response).VerifyAsync(Token("t"), BodyHash, default);
        Assert.Equal(AttestationOutcome.Failed, result.Outcome);
        Assert.Equal(failure, result.Failure);
    }

    private sealed class FixedDecoder(PlayIntegrityDecode decode) : IPlayIntegrityDecoder
    {
        public Task<PlayIntegrityDecode> DecodeAsync(Sensitive<string> token, CancellationToken cancellationToken) => Task.FromResult(decode);
    }
}

/// <summary>An in-memory <c>replay_guard</c> for Play Integrity tokens.</summary>
internal sealed class MemoryReplayGuard : IPlayIntegrityReplayGuard
{
    private readonly ConcurrentDictionary<string, DateTimeOffset> rows = new();

    public IReadOnlyDictionary<byte[], DateTimeOffset> Rows => rows.ToDictionary(r => Convert.FromHexString(r.Key), r => r.Value);

    public Task<bool> TryUseAsync(byte[] tokenHash, DateTimeOffset expiresAt, CancellationToken cancellationToken) =>
        Task.FromResult(rows.TryAdd(Convert.ToHexString(tokenHash), expiresAt));
}

/// <summary>The real <see cref="PlayIntegrityClient"/> through <c>AddZaghlolAttestation</c> against WireMock, with production logging.</summary>
[Collection(PlayClientGroup.Name)]
public sealed class PlayIntegrityClientTests : IDisposable
{
    private const string DecodePath = "/v1/" + PlayWireMock.Package + ":decodeIntegrityToken";
    private readonly PlayWireMock play = new();

    public void Dispose() => play.Dispose();

    [Theory]
    [InlineData(500)]
    [InlineData(503)]
    [InlineData(429)]
    [InlineData(403)]
    public async Task AnUpstreamErrorIsUnavailableNeverAFailure(int status)
    {
        play.Server.Given(Request.Create().WithPath(DecodePath).UsingPost()).RespondWith(Response.Create().WithStatusCode(status));
        await using var host = Start();

        var result = await host.Services.GetRequiredService<IPlayIntegrityVerifier>()
            .VerifyAsync(PlayIntegrityVerifierTests.Token("tok"), SHA256.HashData("restore body"u8), default);

        Assert.Equal(AttestationOutcome.Unavailable, result.Outcome);
    }

    [Fact]
    public async Task ATimeoutIsUnavailable()
    {
        play.Server.Given(Request.Create().WithPath(DecodePath).UsingPost())
            .RespondWith(Response.Create().WithStatusCode(200).WithDelay(TimeSpan.FromSeconds(3)).WithBody("{}"));
        await using var host = Start(attemptTimeoutMs: 200, totalTimeoutMs: 600);

        var result = await host.Services.GetRequiredService<IPlayIntegrityVerifier>()
            .VerifyAsync(PlayIntegrityVerifierTests.Token("tok"), SHA256.HashData("restore body"u8), default);

        Assert.Equal(AttestationOutcome.Unavailable, result.Outcome);
    }

    [Fact]
    public async Task ATokenGoogleRejectsIsAFailureNotAnOutage()
    {
        play.Server.Given(Request.Create().WithPath(DecodePath).UsingPost()).RespondWith(Response.Create().WithStatusCode(400));
        await using var host = Start();

        var result = await host.Services.GetRequiredService<IPlayIntegrityVerifier>()
            .VerifyAsync(PlayIntegrityVerifierTests.Token("tok"), SHA256.HashData("restore body"u8), default);

        Assert.Equal(AttestationFailure.Chain, result.Failure);
    }

    /// <summary>
    /// R2-7 and the log/trace sentinel: a payload carrying all four optional verdicts verifies normally, and neither the token,
    /// any decoded value nor any optional-verdict value reaches the logs, spans or the replay row (only SHA-256(token) is kept).
    /// </summary>
    [Fact]
    public async Task OptionalVerdictsAreIgnoredAndNothingSensitiveIsLoggedOrTraced()
    {
        const string sentinel = "SENTINELq7Zk";
        var token = "tok-" + sentinel + "-integrity";
        var bodyHash = SHA256.HashData("restore body"u8);
        var payload = PlayIntegrityVerifierTests.Payload(issued: DateTimeOffset.UtcNow.AddSeconds(-5), optionalVerdicts: true, sentinel: sentinel);
        play.Server.Given(Request.Create().WithPath(DecodePath).UsingPost())
            .RespondWith(Response.Create().WithStatusCode(200).WithHeader("Content-Type", "application/json").WithBody(payload.ToJsonString()));
        var replay = new MemoryReplayGuard();
        await using var host = Start(replay: replay);
        var verifier = host.Services.GetRequiredService<IPlayIntegrityVerifier>();

        var first = await verifier.VerifyAsync(new Sensitive<string>(token), bodyHash, default);
        var second = await verifier.VerifyAsync(new Sensitive<string>(token), bodyHash, default);
        var mismatch = await verifier.VerifyAsync(new Sensitive<string>(token + "x"), SHA256.HashData("other"u8), default);

        Assert.True(first.IsVerified);
        Assert.Equal(ProofLevel.Device, first.Level);
        Assert.Equal(AttestationFailure.Replayed, second.Failure);
        Assert.Equal(AttestationFailure.HashMismatch, mismatch.Failure);
        Assert.Equal(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(token)), Assert.Single(replay.Rows).Key);

        // The token went out in the request body (not the URL) with exactly one member.
        var sent = play.Server.LogEntries.Select(e => e.RequestMessage!).First(r => r.Body?.Contains(sentinel, StringComparison.Ordinal) == true);
        Assert.DoesNotContain(sentinel, sent.Url!, StringComparison.Ordinal);
        Assert.Equal(["integrityToken"], JsonNode.Parse(sent.Body!)!.AsObject().Select(p => p.Key));

        var haystack = host.LogOutput + "\n" + string.Join('\n', host.Spans);
        Assert.Contains("attestation_failed", host.LogOutput, StringComparison.Ordinal);
        Assert.Contains("replayed", host.LogOutput, StringComparison.Ordinal);
        foreach (var fragment in new[] { sentinel, PlayIntegrityVerifier.Base64Url(bodyHash), "MEETS_DEVICE_INTEGRITY", "PLAY_RECOGNIZED", "LICENSED", "sdkVersion", "playProtectVerdict", "appsDetected" })
        {
            Assert.DoesNotContain(fragment, haystack, StringComparison.OrdinalIgnoreCase);
        }

        // The DTO has no member for any optional verdict (R2-7).
        var members = typeof(TokenPayloadDto).Assembly.GetTypes()
            .Where(t => t.Namespace == typeof(TokenPayloadDto).Namespace && t.Name.EndsWith("Dto", StringComparison.Ordinal))
            .SelectMany(t => t.GetProperties().Select(p => p.Name))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var forbidden in new[] { "DeviceAttributes", "RecentDeviceActivity", "AppAccessRiskVerdict", "EnvironmentDetails", "AccountDetails" })
        {
            Assert.DoesNotContain(forbidden, members);
        }
    }

    private PlayClientHost Start(int attemptTimeoutMs = 4000, int totalTimeoutMs = 10000, MemoryReplayGuard? replay = null) =>
        PlayClientHost.Start(
            play,
            new Dictionary<string, string?>
            {
                ["Attestation:PlayIntegrity:BaseUrl"] = play.BaseUrl,
                ["Purchases:Apple:BundleId"] = AppAttestTestSigner.BundleId,
            },
            configure: services =>
            {
                services.AddSingleton<IPlayIntegrityReplayGuard>(replay ?? new MemoryReplayGuard());
                services.AddSingleton(provider => new PlayIntegrityOptions
                {
                    PackageName = PlayWireMock.Package,
                    BaseUrl = new Uri(play.BaseUrl.TrimEnd('/') + "/"),
                    AttemptTimeout = TimeSpan.FromMilliseconds(attemptTimeoutMs),
                    TotalTimeout = TimeSpan.FromMilliseconds(totalTimeoutMs),
                });
                services.AddZaghlolAttestation();
            });
}
