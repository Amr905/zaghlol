using System.Collections.Concurrent;
using System.Diagnostics;
using System.Diagnostics.Metrics;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Infrastructure.Seats;
using Zaghlol.Infrastructure.Tests.AppStore;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Seats;

/// <summary>
/// T-182 design note §5–§7 and §9: the <c>K_seat</c> startup check, KMS failure behaviour through the real
/// <see cref="IKeyedHasher"/>, the <c>zaghlol.seat.*</c> metrics, and the log / span / metric sentinel.
/// The KMS-fault cases count <c>kms_unavailable{op=hmac}</c> on the process-wide KMS meter, so the class shares the KMS metrics
/// collection.
/// </summary>
[Collection(Zaghlol.Infrastructure.Tests.Kms.SignerMetricsCollection.Name)]
public sealed class SeatKeyInfrastructureTests
{
    private static readonly InstallId Install = InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77");
    private static readonly Guid Purchase = Guid.Parse("5f0c8a7e-2b1d-4e3f-9a6b-7c8d9e0f1a2b");

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    [InlineData("Ci")]
    public async Task OutsideDevelopmentAndTestingAMissingCheckValueRefusesTheStart(string environment)
    {
        using var kms = FakeKms.CreateDefault();

        var error = await StartAsync(kms, environment, seatCheck: null);

        Assert.Equal(SeatKeyStartupCheckMessages.Missing, Assert.IsType<KmsConfigurationException>(error).Message);
    }

    [Theory]
    [InlineData("Production")]
    [InlineData("Development")]
    [InlineData("Testing")]
    public async Task AMismatchRefusesTheStartInEveryEnvironment(string environment)
    {
        using var kms = FakeKms.CreateDefault();
        var wrong = Convert.ToHexStringLower(new byte[32]);

        var error = await StartAsync(kms, environment, seatCheck: wrong);

        Assert.Equal(SeatKeyStartupCheckMessages.Mismatch, Assert.IsType<KmsConfigurationException>(error).Message);
        Assert.DoesNotContain(kms.SeatCheckHex()!, error.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task ARotatedKeyIsCaughtByTheCheck()
    {
        using var kms = FakeKms.CreateDefault();
        var before = kms.SeatCheckHex();
        kms.AddSecret(FakeKms.HmacKeyRef(KeyedHashKey.Seat), System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));

        var error = await StartAsync(kms, "Production", seatCheck: before);

        Assert.Equal(SeatKeyStartupCheckMessages.Mismatch, Assert.IsType<KmsConfigurationException>(error).Message);
    }

    [Fact]
    public async Task AnUnreachableKmsRefusesTheStart()
    {
        using var kms = FakeKms.CreateDefault();
        var check = kms.SeatCheckHex();
        kms.Fault = FakeKmsFault.Throw;

        var error = await StartAsync(kms, "Production", seatCheck: check);

        Assert.Equal(SeatKeyStartupCheckMessages.Unavailable, Assert.IsType<KmsConfigurationException>(error).Message);
    }

    [Theory]
    [InlineData("FE38D23CA263A6F7334148B2AE03E1D4B71A9FA54A062F3EFE0470055DE93E5B")]
    [InlineData("fe38d23c")]
    [InlineData("not-hex-not-hex-not-hex-not-hex-not-hex-not-hex-not-hex-not-hex")]
    public async Task AMalformedCheckValueRefusesTheStart(string value)
    {
        using var kms = FakeKms.CreateDefault().UseFixedSeatKey();

        var error = await StartAsync(kms, "Testing", seatCheck: value);

        Assert.Equal(SeatKeyStartupCheckMessages.Malformed, Assert.IsType<KmsConfigurationException>(error).Message);
    }

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    [InlineData("Testing")]
    public async Task TheCorrectValuePasses(string environment)
    {
        using var kms = FakeKms.CreateDefault().UseFixedSeatKey();

        Assert.Equal("fe38d23ca263a6f7334148b2ae03e1d4b71a9fa54a062f3efe0470055de93e5b", kms.SeatCheckHex());
        Assert.Null(await StartAsync(kms, environment, seatCheck: kms.SeatCheckHex()));
    }

    [Theory]
    [InlineData("Testing")]
    [InlineData("Development")]
    public async Task InDevelopmentAndTestingAnUnsetValueIsSkipped(string environment)
    {
        using var kms = FakeKms.CreateDefault();
        kms.Fault = FakeKmsFault.Throw;

        Assert.Null(await StartAsync(kms, environment, seatCheck: null));
    }

    [Fact]
    public async Task AKmsFaultIsKmsUnavailableAndNeverAResult()
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = Services(kms, "Testing", null);
        var verifier = services.GetRequiredService<SeatKeyProofVerifier>();
        var hasher = services.GetRequiredService<SeatKeyHasher>();
        using var a = new SeatKeyTestSigner();
        using var b = new SeatKeyTestSigner();
        var challenge = SeatChallenge.ForRestore(new byte[32]);
        var keys = verifier.ParseAndVerify([a.Prove(challenge, Install), b.Prove(challenge, Install)], challenge, Install).Keys!;
        var stored = await hasher.SeatKeyHashAsync(Purchase, keys.Others[0], CancellationToken.None);
        var registered = (await hasher.CheckElementZeroAsync(Install, null, keys, CancellationToken.None)).Computed;

        foreach (var fault in new[] { FakeKmsFault.Throw, FakeKmsFault.Crypto })
        {
            kms.Fault = fault;
            var errors = new[]
            {
                await Assert.ThrowsAsync<KmsUnavailableException>(() => hasher.CheckElementZeroAsync(Install, null, keys, CancellationToken.None)),
                await Assert.ThrowsAsync<KmsUnavailableException>(() => hasher.CheckElementZeroAsync(Install, registered, keys, CancellationToken.None)),
                await Assert.ThrowsAsync<KmsUnavailableException>(() => hasher.SeatCheckAsync(CancellationToken.None)),
                await Assert.ThrowsAsync<KmsUnavailableException>(() => hasher.MatchSeatAsync(Purchase, stored, keys, CancellationToken.None)),
                await Assert.ThrowsAsync<KmsUnavailableException>(() => hasher.SeatKeyHashAsync(Purchase, keys.ElementZero, CancellationToken.None)),
            };
            Assert.All(errors, e => Assert.Equal(KmsUnavailableException.DefaultMessage, e.Message));
            Assert.All(errors, e => Assert.DoesNotContain(FakeKms.CryptoFaultMessage, e.ToString(), StringComparison.Ordinal));
        }
    }

    [Fact]
    public async Task MetricsCarryOnlyFixedWords()
    {
        using var kms = FakeKms.CreateDefault();
        using var capture = new MetricCapture("zaghlol.seat.");
        await using var services = Services(kms, "Testing", null);
        var verifier = services.GetRequiredService<SeatKeyProofVerifier>();
        var hasher = services.GetRequiredService<SeatKeyHasher>();
        using var signer = new SeatKeyTestSigner();
        var challenge = SeatChallenge.ForSignIn("nonce-for-metrics");

        var keys = verifier.ParseAndVerify([signer.Prove(challenge, Install)], challenge, Install).Keys!;
        _ = verifier.ParseAndVerify([SeatKeyTestSigner.Defective(signer.Prove(challenge, Install), SeatKeyDefect.OffCurve)], challenge, Install);
        _ = verifier.Parse(SeatOp.Verify, []);
        var zero = await hasher.CheckElementZeroAsync(Install, null, keys, CancellationToken.None);
        _ = await hasher.CheckElementZeroAsync(Install, zero.Computed, keys, CancellationToken.None);

        Assert.Equal(
            [
                "zaghlol.seat.proof{op=signin,result=valid}",
                "zaghlol.seat.proof{op=signin,result=bad_point}",
                "zaghlol.seat.proof{op=verify,result=empty}",
                "zaghlol.seat.element_zero{op=signin,status=none_registered}",
                "zaghlol.seat.element_zero{op=signin,status=matches}",
            ],
            capture.Samples);
    }

    /// <summary>
    /// The sentinel: parse, verify, hash, element 0, seat match, a rejected set, the startup check and a KMS fault run under a
    /// capturing logger, an activity listener and a meter listener. No base64url or hex of any key, signature, hash, message
    /// or challenge appears in a log line, span, tag, metric tag or exception text.
    /// </summary>
    [Fact]
    public async Task NoKeySignatureHashOrMessageReachesLogsSpansMetricsOrExceptions()
    {
        using var kms = FakeKms.CreateDefault();
        using var metrics = new MetricCapture(string.Empty);
        using var spans = new SpanCapture();
        var logs = new CapturingLoggerProvider();
        await using var services = Services(kms, "Production", kms.SeatCheckHex(), logs);
        foreach (var hosted in services.GetServices<IHostedService>())
        {
            await hosted.StartAsync(CancellationToken.None);
        }

        var verifier = services.GetRequiredService<SeatKeyProofVerifier>();
        var hasher = services.GetRequiredService<SeatKeyHasher>();
        using var a = new SeatKeyTestSigner();
        using var b = new SeatKeyTestSigner();
        var challenge = SeatChallenge.ForRestore(Enumerable.Repeat((byte)0x5a, 32).ToArray());
        var pa = a.Prove(challenge, Install);
        var pb = b.Prove(challenge, Install);
        var texts = new List<string>();

        var verified = verifier.ParseAndVerify([pa, pb], challenge, Install);
        var keys = verified.Keys!;
        var zero = await hasher.CheckElementZeroAsync(Install, null, keys, CancellationToken.None);
        var seat = await hasher.SeatKeyHashAsync(Purchase, keys.Others[0], CancellationToken.None);
        var match = await hasher.MatchSeatAsync(Purchase, seat, keys, CancellationToken.None);
        Assert.Equal(1, match);
        var rejected = verifier.ParseAndVerify([pa, SeatKeyTestSigner.Defective(pb, SeatKeyDefect.FlippedSignatureBit)], challenge, Install);
        Assert.False(rejected.IsValid);
        texts.AddRange([verified.ToString(), rejected.ToString(), keys.ToString(), zero.ToString(), seat.ToString(), $"{pa}", $"{keys.ElementZero}"]);

        texts.Add((await Assert.ThrowsAnyAsync<ArgumentException>(() => hasher.CheckElementZeroAsync(InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e78"), null, keys, CancellationToken.None))).ToString());
        texts.Add(Assert.ThrowsAny<ArgumentException>(() => verifier.Verify(verifier.Parse(SeatOp.Restore, [pa]).Keys!, SeatChallenge.ForSignIn("n"), Install)).ToString());
        texts.Add((await StartAsync(kms, "Production", Convert.ToHexStringLower(new byte[32])))!.ToString());
        kms.Fault = FakeKmsFault.Crypto;
        texts.Add((await Assert.ThrowsAsync<KmsUnavailableException>(() => hasher.CheckElementZeroAsync(Install, zero.Computed, keys, CancellationToken.None))).ToString());
        texts.Add((await StartAsync(kms, "Production", Convert.ToHexStringLower(new byte[32])))!.ToString());

        var sentinels = new List<string>();
        foreach (var proof in new[] { pa, pb })
        {
            var point = System.Buffers.Text.Base64Url.DecodeFromChars(proof.PublicKey);
            var signature = System.Buffers.Text.Base64Url.DecodeFromChars(proof.Signature);
            sentinels.AddRange([proof.PublicKey, proof.Signature, proof.PublicKey[1..20], proof.Signature[..20], Hex(point)[2..40], Hex(signature)[..40], Convert.ToBase64String(point)[..30]]);
        }

        sentinels.AddRange(
        [
            Hex(zero.Computed.ToStorage())[..32], Hex(seat.ToStorage())[..32], kms.SeatCheckHex()![..32],
            Hex(keys.Digest())[..32], Hex(challenge.ToArray())[..16], "5a5a5a5a5a5a",
        ]);

        var haystacks = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["logs"] = string.Join('\n', logs.Lines),
            ["spans"] = string.Join('\n', spans.Lines),
            ["metrics"] = string.Join('\n', metrics.Samples),
            ["exceptions and ToString"] = string.Join('\n', texts),
        };
        Assert.Contains(logs.Lines, l => l.Contains("K_seat startup check passed", StringComparison.Ordinal));
        Assert.Contains(metrics.Samples, s => s.StartsWith("zaghlol.seat.proof", StringComparison.Ordinal));

        foreach (var (where, haystack) in haystacks)
        {
            foreach (var sentinel in sentinels)
            {
                Assert.False(haystack.Contains(sentinel, StringComparison.OrdinalIgnoreCase), $"{where} contains a key, signature, hash or message fragment");
            }
        }
    }

    private static string Hex(byte[] bytes) => Convert.ToHexStringLower(bytes);

    private static ServiceProvider Services(FakeKms kms, string environment, string? seatCheck, ILoggerProvider? logs = null)
    {
        var extra = new Dictionary<string, string?>(StringComparer.Ordinal) { [SeatKeysServiceCollectionExtensions.SeatCheckKey] = seatCheck };
        return kms.BuildServices(extra, s =>
        {
            s.AddSingleton<IHostEnvironment>(new AppStoreOptionsTests.Env(environment));
            s.AddSingleton(new KmsCallPolicy { Timeout = TimeSpan.FromMilliseconds(200) });
            s.AddZaghlolSeatKeys();
            if (logs is not null)
            {
                s.AddLogging(l => l.ClearProviders().AddProvider(logs).SetMinimumLevel(LogLevel.Trace));
            }
        });
    }

    /// <summary>Runs only the K_seat check (the T-123 ring check is covered by its own tests). Null when it passed.</summary>
    private static async Task<Exception?> StartAsync(FakeKms kms, string environment, string? seatCheck)
    {
        await using var services = Services(kms, environment, seatCheck);
        var check = services.GetServices<IHostedService>().Single(h => h.GetType().Name == "SeatKeyStartupCheck");
        try
        {
            await check.StartAsync(CancellationToken.None);
            return null;
        }
#pragma warning disable CA1031 // The test returns whatever the check threw.
        catch (Exception ex)
#pragma warning restore CA1031
        {
            return ex;
        }
    }

    private static class SeatKeyStartupCheckMessages
    {
        public const string Missing = SeatKeyStartupCheck.MissingMessage;
        public const string Mismatch = SeatKeyStartupCheck.MismatchMessage;
        public const string Unavailable = SeatKeyStartupCheck.UnavailableMessage;
        public const string Malformed = SeatKeyStartupCheck.MalformedMessage;
    }

    private sealed class MetricCapture : IDisposable
    {
        private readonly MeterListener listener = new();
        private readonly ConcurrentQueue<string> samples = new();

        public MetricCapture(string prefix)
        {
            listener.InstrumentPublished = (instrument, l) =>
            {
                if (instrument.Name.StartsWith(prefix, StringComparison.Ordinal))
                {
                    l.EnableMeasurementEvents(instrument);
                }
            };
            listener.SetMeasurementEventCallback<long>((instrument, _, tags, _) =>
            {
                if (instrument.Meter.Name is ZaghlolMetrics.MeterName or KmsMetrics.MeterName)
                {
                    var list = new List<string>();
                    foreach (var tag in tags)
                    {
                        list.Add($"{tag.Key}={tag.Value}");
                    }

                    samples.Enqueue($"{instrument.Name}{{{string.Join(',', list)}}}");
                }
            });
            listener.Start();
        }

        public IReadOnlyList<string> Samples => [.. samples];

        public void Dispose() => listener.Dispose();
    }

    private sealed class SpanCapture : IDisposable
    {
        private readonly ActivityListener listener;
        private readonly ConcurrentQueue<string> lines = new();

        public SpanCapture()
        {
            listener = new ActivityListener
            {
                ShouldListenTo = _ => true,
                Sample = (ref ActivityCreationOptions<ActivityContext> _) => ActivitySamplingResult.AllDataAndRecorded,
                ActivityStopped = a => lines.Enqueue($"{a.Source.Name} {a.DisplayName} {string.Join(',', a.TagObjects.Select(t => $"{t.Key}={t.Value}"))} {string.Join(',', a.Events.Select(e => e.Name))}"),
            };
            ActivitySource.AddActivityListener(listener);
        }

        public IReadOnlyList<string> Lines => [.. lines];

        public void Dispose() => listener.Dispose();
    }

    private sealed class CapturingLoggerProvider : ILoggerProvider
    {
        private readonly ConcurrentQueue<string> lines = new();

        public IReadOnlyList<string> Lines => [.. lines];

        public ILogger CreateLogger(string categoryName) => new Logger(categoryName, lines);

        public void Dispose()
        {
        }

        private sealed class Logger(string category, ConcurrentQueue<string> lines) : ILogger
        {
            public IDisposable? BeginScope<TState>(TState state)
                where TState : notnull => null;

            public bool IsEnabled(LogLevel logLevel) => true;

            public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
            {
                var values = state is IEnumerable<KeyValuePair<string, object?>> pairs ? string.Join(',', pairs.Select(p => $"{p.Key}={p.Value}")) : string.Empty;
                lines.Enqueue($"{category} {logLevel} {formatter(state, exception)} {values} {exception}");
            }
        }
    }
}
