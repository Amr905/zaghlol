using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Zaghlol.Application.Config;
using Zaghlol.Application.Flags;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Attestation;
using Zaghlol.Application.Purchases.Attestation;
using Zaghlol.Application.Seats;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Attestation;
using Zaghlol.Infrastructure.GooglePlay;
using Zaghlol.Infrastructure.Tests.Attestation;
using Zaghlol.Infrastructure.Tests.Seats;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Llm.Attestation;

/// <summary>
/// T-336: the mode-aware LLM verifier over the <b>real</b> Play Integrity rules (fake decode call, in-memory replay guard) and the
/// <b>real</b> App Attest verifier (test root, in-memory key store). No database or network.
/// </summary>
public sealed class LlmAttestationVerifierTests : IDisposable
{
    private const string Question = "MARKER-question-text-91f3 how much did I spend";
    private static readonly DateTimeOffset Now = new(2026, 11, 26, 12, 0, 0, TimeSpan.Zero);
    private static readonly byte[] DevKey = RandomNumberGenerator.GetBytes(32);

    private readonly InstallId install = InstallId.FromGuid(Guid.NewGuid());
    private readonly IssuingDecoder decoder = new();
    private readonly MemoryReplayGuard replay = new();
    private readonly AppAttestTestSigner signer = new();
    private readonly InMemoryAppAttestKeyStore keys = new();
    private readonly MemoryTransactions transactions;
    private readonly FakeReadiness readiness = new();
    private readonly RecordingTelemetry telemetry = new();
    private readonly LineLogger logger = new();

    public LlmAttestationVerifierTests() => transactions = new MemoryTransactions(keys);

    public void Dispose() => signer.Dispose();

    // ---- AC2: valid proofs pass; missing, stale, replayed, wrong-body, wrong-install are refused in Enforce ----
    [Fact]
    public async Task AValidPlayIntegrityTokenPassesInEnforce()
    {
        var hash = Body(install).Hash;
        var decision = await Verifier(LlmAttestationMode.Enforce).VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash, Play(decoder.Issue(hash, Now)), default);

        Assert.Equal(new LlmAttestationDecision(LlmAttestationVerdict.Pass, "ok", true), decision);
        Assert.Single(replay.Rows);
    }

    [Fact]
    public async Task AValidAppAttestFirstUseAndLaterAssertionPassAndCommit()
    {
        using var key = AppAttestTestSigner.NewKey();
        var hash = Body(install, "q1").Hash;
        var clientData = LlmBinding.ClientDataHash(LlmFeature.Categorise, hash);
        var first = new LlmAppAttestProof(key.KeyId, AppAttestTestSigner.Assert(key, clientData, 1), signer.Attest(key, clientData));

        var firstUse = await Verifier(LlmAttestationMode.Enforce).VerifyAsync(LlmFeature.Categorise, LlmAttestPlatform.Ios, install, hash, first, default);

        var hash2 = Body(install, "q2").Hash;
        var later = new LlmAppAttestProof(key.KeyId, AppAttestTestSigner.Assert(key, LlmBinding.ClientDataHash(LlmFeature.Categorise, hash2), 2), null);
        var next = await Verifier(LlmAttestationMode.Enforce).VerifyAsync(LlmFeature.Categorise, LlmAttestPlatform.Ios, install, hash2, later, default);

        Assert.True(firstUse.Verified);
        Assert.True(next.Verified);
        Assert.Equal(2, transactions.Commits);
        Assert.Equal(2, keys.Rows[install.Value].SignCount);
    }

    public static TheoryData<string> FailureCases => ["missing", "stale", "replayed", "wrong_body", "wrong_install", "wrong_type", "dev_in_enforce"];

    [Theory]
    [MemberData(nameof(FailureCases))]
    public async Task EveryInvalidProofIsRefusedInEnforceAndCountedButPassedInReportOnly(string kind)
    {
        foreach (var mode in new[] { LlmAttestationMode.Enforce, LlmAttestationMode.ReportOnly })
        {
            var (proof, hash, expectedReason) = await Case(kind);
            var decision = await Verifier(mode).VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash, proof, default);

            Assert.False(decision.Verified);
            Assert.Equal(expectedReason, decision.Reason);
            Assert.Equal(mode == LlmAttestationMode.Enforce ? LlmAttestationVerdict.Refuse : LlmAttestationVerdict.Pass, decision.Verdict);
            Assert.Contains(telemetry.Events, e => e.Mode == mode && e.Reason == expectedReason && e.Verdict == decision.Verdict);
        }
    }

    // ---- AC3: unconfigured verifiers -> every request 503; outage -> 503 ----
    [Fact]
    public async Task WithUnconfiguredVerifiersEveryRequestIsUnavailable()
    {
        readiness.Android = false;
        readiness.Ios = false;
        var hash = Body(install).Hash;
        LlmAttestationProof?[] proofs = [null, Play(decoder.Issue(hash, Now)), new LlmDevProof(new Sensitive<string>(LlmAttestationVerifier.DevProof(DevKey, hash))),
            new LlmAppAttestProof(new byte[32], new byte[64], null)];

        foreach (var platform in new[] { LlmAttestPlatform.Android, LlmAttestPlatform.Ios })
        {
            foreach (var proof in proofs)
            {
                var decision = await Verifier(LlmAttestationMode.Enforce).VerifyAsync(LlmFeature.Ask, platform, install, hash, proof, default);
                Assert.Equal(new LlmAttestationDecision(LlmAttestationVerdict.Unavailable, "not_configured", false), decision);
            }
        }

        Assert.Empty(replay.Rows);
        Assert.Equal(0, decoder.Calls);
    }

    [Fact]
    public async Task APlayIntegrityOutageIsUnavailableInEnforceAndPassesInReportOnly()
    {
        decoder.Outage = true;
        var hash = Body(install).Hash;

        var enforce = await Verifier(LlmAttestationMode.Enforce).VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash, Play("synthetic-token-outage-1"), default);
        var report = await Verifier(LlmAttestationMode.ReportOnly).VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash, Play("synthetic-token-outage-2"), default);

        Assert.Equal(LlmAttestationVerdict.Unavailable, enforce.Verdict);
        Assert.Equal(LlmAttestationVerdict.Pass, report.Verdict);
        Assert.Equal("unavailable", report.Reason);
    }

    // ---- AC5 (negative proof 2): body binding and single use ----
    [Fact]
    public async Task AProofForOneBodyIsRefusedWhenAnyByteOfTheBodyChanges()
    {
        const string original = """{"planVersion":1,"requestId":"01JD8Z3Q4F6R7T9V0W1X2Y3Z4A","q":"How much on dining","lang":"en","consent":{"provider":"openai-luna","v":1}}""";
        var originalHash = Hash(LlmFeature.Ask, install, original)!;
        var token = decoder.Issue(originalHash, Now);
        using var key = AppAttestTestSigner.NewKey();
        await RegisterAsync(key);
        var assertion = AppAttestTestSigner.Assert(key, LlmBinding.ClientDataHash(LlmFeature.Ask, originalHash), 5);
        var dev = LlmAttestationVerifier.DevProof(DevKey, originalHash);

        var bytes = Encoding.ASCII.GetBytes(original);
        var tried = 0;
        for (var i = 0; i < bytes.Length; i++)
        {
            var changed = (byte[])bytes.Clone();
            changed[i] = (byte)(changed[i] == (byte)'x' ? 'y' : 'x');
            var hash = Hash(LlmFeature.Ask, install, Encoding.ASCII.GetString(changed));
            if (hash is null)
            {
                continue; // no longer a JSON object: the endpoint answers VALIDATION_FAILED before attestation
            }

            tried++;
            Assert.NotEqual(originalHash, hash);
            Assert.Equal(LlmAttestationVerdict.Refuse, (await Verifier(LlmAttestationMode.Enforce).VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash, Play(token), default)).Verdict);
            Assert.Equal(LlmAttestationVerdict.Refuse, (await Verifier(LlmAttestationMode.Enforce).VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Ios, install, hash, new LlmAppAttestProof(key.KeyId, assertion, null), default)).Verdict);
            Assert.Equal(LlmAttestationVerdict.Refuse, (await Verifier(LlmAttestationMode.Fake).VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash, new LlmDevProof(new Sensitive<string>(dev)), default)).Verdict);
        }

        Assert.True(tried > bytes.Length / 2, "most single-byte changes still parse");

        // The untouched body still verifies on every path, so the refusals above came from the change.
        Assert.True((await Verifier(LlmAttestationMode.Enforce).VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, originalHash, Play(token), default)).Verified);
        Assert.True((await Verifier(LlmAttestationMode.Enforce).VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Ios, install, originalHash, new LlmAppAttestProof(key.KeyId, assertion, null), default)).Verified);
    }

    [Fact]
    public async Task AValidProofUsedTwiceIsRefusedTheSecondTime()
    {
        var hash = Body(install).Hash;
        var token = decoder.Issue(hash, Now);
        using var key = AppAttestTestSigner.NewKey();
        await RegisterAsync(key);
        var assertion = new LlmAppAttestProof(key.KeyId, AppAttestTestSigner.Assert(key, LlmBinding.ClientDataHash(LlmFeature.Ask, hash), 7), null);
        var verifier = Verifier(LlmAttestationMode.Enforce);

        Assert.True((await verifier.VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash, Play(token), default)).Verified);
        Assert.True((await verifier.VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Ios, install, hash, assertion, default)).Verified);

        var playAgain = await verifier.VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash, Play(token), default);
        var appleAgain = await verifier.VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Ios, install, hash, assertion, default);

        Assert.Equal(new LlmAttestationDecision(LlmAttestationVerdict.Refuse, "replayed", false), playAgain);
        Assert.Equal(new LlmAttestationDecision(LlmAttestationVerdict.Refuse, "counter", false), appleAgain);
    }

    // ---- Fake mode ----
    [Fact]
    public async Task FakeAcceptsOnlyAValidDevProof()
    {
        var hash = Body(install).Hash;
        var fake = Verifier(LlmAttestationMode.Fake);

        Assert.True((await fake.VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Ios, install, hash, new LlmDevProof(new Sensitive<string>(LlmAttestationVerifier.DevProof(DevKey, hash))), default)).Verified);
        Assert.Equal("hash_mismatch", (await fake.VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Ios, install, hash, new LlmDevProof(new Sensitive<string>(LlmAttestationVerifier.DevProof(new byte[32], hash))), default)).Reason);
        Assert.Equal("wrong_type", (await fake.VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash, Play(decoder.Issue(hash, Now)), default)).Reason);
        Assert.Equal("missing", (await fake.VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash, null, default)).Reason);
        Assert.Equal(0, decoder.Calls);
    }

    // ---- AC6: fixed codes in logs; no token, assertion, proof or body ----
    [Fact]
    public async Task LogsCarryFixedCodesOnlyAndNeverProofsOrQuestionText()
    {
        var hash = Body(install).Hash;
        const string token = "SECRETTOKEN-llm-attest-55aa";
        const string devProof = "SECRETDEVPROOF-77bb";
        await Verifier(LlmAttestationMode.Enforce).VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash, Play(token), default);
        await Verifier(LlmAttestationMode.Enforce).VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash, new LlmDevProof(new Sensitive<string>(devProof)), default);
        await Verifier(LlmAttestationMode.Fake).VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash, new LlmDevProof(new Sensitive<string>(devProof)), default);

        Assert.Equal(3, logger.Lines.Count);
        foreach (var line in logger.Lines)
        {
            Assert.StartsWith("llm_attestation_not_verified feature=ask mode=", line, StringComparison.Ordinal);
            Assert.DoesNotContain("SECRET", line, StringComparison.Ordinal);
            Assert.DoesNotContain("MARKER", line, StringComparison.Ordinal);
            Assert.DoesNotContain(install.Value.ToString(), line, StringComparison.Ordinal);
        }

        Assert.All(telemetry.Events, e => Assert.Contains(e.Reason, LlmAttestationReasons.All));
        Assert.Equal("LlmAttestationProof(play_integrity)", Play(token).ToString());
    }

    // ---- AC4 (negative proof 1, DI part): Production enforces whatever remote config, flags or reloaded config say ----
    [Fact]
    public async Task InProductionNoRemoteConfigFlagOrConfigReloadRelaxesEnforcement()
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>()).Build();
        using var provider = ProductionServices(configuration);
        foreach (var check in provider.GetServices<IHostedService>())
        {
            await check.StartAsync(default);
        }

        // Every closed remote_config key and every flag is set; then the configuration is changed after startup.
        Assert.Equal(RemoteConfigKeys.All.Count, (await provider.GetRequiredService<IRemoteConfigReader>().ListAsync(default)).Count);
        configuration[LlmAttestationSettings.ModeKey] = "ReportOnly";
        configuration[LlmAttestationSettings.DevProofKeyKey] = Convert.ToBase64String(DevKey);

        var verifier = provider.GetRequiredService<ILlmAttestationVerifier>();
        var hash = Body(install).Hash;
        Assert.Equal(LlmAttestationMode.Enforce, verifier.Mode);
        Assert.Equal(LlmAttestationVerdict.Refuse, (await verifier.VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash, null, default)).Verdict);
        Assert.Equal(LlmAttestationVerdict.Refuse, (await verifier.VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash,
            new LlmDevProof(new Sensitive<string>(LlmAttestationVerifier.DevProof(DevKey, hash))), default)).Verdict);

        // Nothing the verifier is built from can carry a remote value or a request header.
        var parameters = typeof(LlmAttestationVerifier).GetConstructors().Single().GetParameters().Select(p => p.ParameterType).ToList();
        Assert.DoesNotContain(parameters, t => t == typeof(IRemoteConfigService) || t == typeof(IRemoteConfigReader) || t == typeof(IFlagReader)
            || t == typeof(IConfiguration) || t.Name.Contains("HttpContext", StringComparison.Ordinal));
    }

    [Theory]
    [InlineData("ReportOnly", null)]
    [InlineData("Fake", "dev")]
    [InlineData("Enforce", "dev")]
    public async Task ProductionStartupRefusesARelaxedModeOrADevKey(string mode, string? devKey)
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            [LlmAttestationSettings.ModeKey] = mode,
            [LlmAttestationSettings.DevProofKeyKey] = devKey is null ? null : Convert.ToBase64String(DevKey),
        }).Build();
        using var provider = ProductionServices(configuration);
        var check = provider.GetServices<IHostedService>().Single(s => s.GetType().Name == "LlmAttestationStartupCheck");

        await Assert.ThrowsAsync<LlmAttestationConfigurationException>(() => check.StartAsync(default));
    }

    [Fact]
    public async Task ProductionStartupRefusesASubstitutedVerifier()
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>()).Build();
        using var provider = ProductionServices(configuration, services => services.AddSingleton<ILlmAttestationVerifier>(new AlwaysPass()));
        var check = provider.GetServices<IHostedService>().Single(s => s.GetType().Name == "LlmAttestationStartupCheck");

        await Assert.ThrowsAsync<LlmAttestationConfigurationException>(() => check.StartAsync(default));
    }

    [Fact]
    public void ReadinessFollowsTheStoreConfiguration()
    {
        var testing = new HostEnv("Testing");
        var none = GooglePlayOptions.Read(new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> { ["Purchases:Google:PackageName"] = "app.zaghlol" }).Build(), testing);
        var adc = GooglePlayOptions.Read(new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Purchases:Google:PackageName"] = "app.zaghlol",
            ["Purchases:Google:CredentialSource"] = "ApplicationDefault",
        }).Build(), testing);
        var placeholder = new AppAttestOptions { AppId = "TESTTEAM00.app.zaghlol" };
        var real = new AppAttestOptions { AppId = "ABCDE12345.app.zaghlol" };

        Assert.False(new StoreLlmAttestationReadiness(none, placeholder).IsConfigured(LlmAttestPlatform.Android));
        Assert.False(new StoreLlmAttestationReadiness(none, placeholder).IsConfigured(LlmAttestPlatform.Ios));
        Assert.True(new StoreLlmAttestationReadiness(adc, real).IsConfigured(LlmAttestPlatform.Android));
        Assert.True(new StoreLlmAttestationReadiness(adc, real).IsConfigured(LlmAttestPlatform.Ios));
        Assert.False(new StoreLlmAttestationReadiness(adc, new AppAttestOptions { AppId = "ABCDE12345." }).IsConfigured(LlmAttestPlatform.Ios));
    }

    // ---- helpers ----
    private async Task<(LlmAttestationProof? Proof, byte[] Hash, string Reason)> Case(string kind)
    {
        var hash = Body(install).Hash;
        switch (kind)
        {
            case "missing":
                return (null, hash, "missing");
            case "stale":
                return (Play(decoder.Issue(hash, Now.AddMinutes(-6))), hash, "stale");
            case "replayed":
                var token = decoder.Issue(hash, Now);
                await Verifier(LlmAttestationMode.Enforce).VerifyAsync(LlmFeature.Ask, LlmAttestPlatform.Android, install, hash, Play(token), default);
                return (Play(token), hash, "replayed");
            case "wrong_body":
                return (Play(decoder.Issue(Body(install, "another question").Hash, Now)), hash, "hash_mismatch");
            case "wrong_install":
                return (Play(decoder.Issue(Body(InstallId.FromGuid(Guid.NewGuid())).Hash, Now)), hash, "hash_mismatch");
            case "wrong_type":
                return (new LlmAppAttestProof(new byte[32], new byte[64], null), hash, "wrong_type");
            default:
                return (new LlmDevProof(new Sensitive<string>(LlmAttestationVerifier.DevProof(DevKey, hash))), hash, "wrong_type");
        }
    }

    private async Task RegisterAsync(AppAttestTestKey key)
    {
        var clientData = SHA256.HashData("registration"u8);
        Assert.True((await AppAttest().RegisterAttestationAsync(keys, install, key.KeyId, signer.Attest(key, clientData), clientData, default)).IsVerified);
    }

    private LlmAttestationVerifier Verifier(LlmAttestationMode mode)
    {
        var settings = mode switch
        {
            LlmAttestationMode.Fake => LlmAttestationSettings.Resolve("Fake", Convert.ToBase64String(DevKey), "Testing"),
            LlmAttestationMode.ReportOnly => LlmAttestationSettings.Resolve("ReportOnly", null, "Staging"),
            _ => LlmAttestationSettings.Resolve(null, null, "Production"),
        };
        return new LlmAttestationVerifier(settings, PlayVerifier(), AppAttest(), transactions, readiness, telemetry, logger);
    }

    private PlayIntegrityVerifier PlayVerifier() => new(
        decoder, replay, new PlayIntegrityOptions { PackageName = PlayWireMock.Package, BaseUrl = new Uri("http://127.0.0.1/") }, new ManualTime(Now), NullLogger<PlayIntegrityVerifier>.Instance);

    private AppAttestVerifier AppAttest() =>
        new(new AppAttestOptions { AppId = AppAttestTestSigner.AppId, TestRoot = signer.RootDer }, TimeProvider.System, NullLogger<AppAttestVerifier>.Instance);

    private ServiceProvider ProductionServices(IConfiguration configuration, Action<IServiceCollection>? extra = null)
    {
        var services = new ServiceCollection();
        services.AddSingleton(configuration);
        services.AddSingleton<IHostEnvironment>(new HostEnv("Production"));
        services.AddLogging();
        services.AddSingleton<IPlayIntegrityVerifier>(PlayVerifier());
        services.AddSingleton<IAppAttestVerifier>(AppAttest());
        services.AddSingleton<ISeatTransactionFactory>(transactions);
        services.AddSingleton<ILlmAttestationReadiness>(readiness);
        services.AddSingleton<IRemoteConfigReader>(new EverythingSet());
        services.AddSingleton<IFlagReader>(new EverythingSet());
        services.AddSingleton<IRemoteConfigService, RemoteConfigService>();
        extra?.Invoke(services);
        services.AddZaghlolLlmAttestation();
        return services.BuildServiceProvider();
    }

    private static LlmPlayIntegrityProof Play(string token) => new(new Sensitive<string>(token));

    private static BodyHashed Body(InstallId installId, string question = Question)
    {
        var json = JsonSerializer.Serialize(new { planVersion = 1, requestId = "01JD8Z3Q4F6R7T9V0W1X2Y3Z4A", q = question, lang = "en", attestation = new { type = "dev", proof = "ignored0" } });
        using var document = JsonDocument.Parse(json);
        return new BodyHashed(LlmBinding.BodyHash(LlmFeature.Ask, installId, document.RootElement)!);
    }

    private static byte[]? Hash(LlmFeature feature, InstallId installId, string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json, new JsonDocumentOptions { AllowDuplicateProperties = false });
            return LlmBinding.BodyHash(feature, installId, document.RootElement);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <summary>Google's decode call: each issued token decodes to a payload bound to the hash it was issued for.</summary>
    private sealed class IssuingDecoder : IPlayIntegrityDecoder
    {
        private readonly ConcurrentDictionary<string, (byte[] Hash, DateTimeOffset Issued)> issued = new();
        private int count;

        public bool Outage { get; set; }

        public int Calls => count;

        public string Issue(byte[] hash, DateTimeOffset at)
        {
            var token = "synthetic-play-token-" + Guid.NewGuid().ToString("N");
            issued[token] = (hash, at);
            return token;
        }

        public Task<PlayIntegrityDecode> DecodeAsync(Sensitive<string> token, CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref count);
            if (Outage)
            {
                return Task.FromResult(new PlayIntegrityDecode(PlayIntegrityDecodeStatus.Unavailable, null));
            }

            if (!issued.TryGetValue(token.Reveal(), out var entry))
            {
                return Task.FromResult(new PlayIntegrityDecode(PlayIntegrityDecodeStatus.Rejected, null));
            }

            var json = PlayIntegrityVerifierTests.Payload(requestHash: PlayIntegrityVerifier.Base64Url(entry.Hash), issued: entry.Issued).ToJsonString();
            var dto = JsonSerializer.Deserialize(json, PlayIntegrityJsonContext.Default.DecodeIntegrityTokenResponseDto)!;
            return Task.FromResult(new PlayIntegrityDecode(PlayIntegrityDecodeStatus.Decoded, dto.TokenPayloadExternal));
        }
    }

    private sealed record BodyHashed(byte[] Hash);

    private sealed class FakeReadiness : ILlmAttestationReadiness
    {
        public bool Android { get; set; } = true;

        public bool Ios { get; set; } = true;

        public bool IsConfigured(LlmAttestPlatform platform) => platform == LlmAttestPlatform.Android ? Android : Ios;
    }

    private sealed record Decided(LlmFeature Feature, LlmAttestationMode Mode, LlmAttestPlatform Platform, LlmAttestationVerdict Verdict, string Reason);

    private sealed class RecordingTelemetry : ILlmAttestationTelemetry
    {
        public ConcurrentQueue<Decided> Events { get; } = new();

        public void Decided(LlmFeature feature, LlmAttestationMode mode, LlmAttestPlatform platform, LlmAttestationVerdict verdict, string reason) =>
            Events.Enqueue(new Decided(feature, mode, platform, verdict, reason));
    }

    private sealed class LineLogger : ILogger<LlmAttestationVerifier>
    {
        public List<string> Lines { get; } = [];

        public IDisposable? BeginScope<TState>(TState state)
            where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
            Lines.Add(formatter(state, exception));
    }

    /// <summary>The in-memory key store as the transaction's store; counts commits.</summary>
    private sealed class MemoryTransactions(InMemoryAppAttestKeyStore keys) : ISeatTransactionFactory
    {
        public int Commits { get; private set; }

        public Task<ISeatTransaction> BeginAsync(SeatLogin login, CancellationToken cancellationToken) => Task.FromResult<ISeatTransaction>(new Transaction(this, keys));

        private sealed class Transaction(MemoryTransactions owner, InMemoryAppAttestKeyStore keys) : ISeatTransaction
        {
            public ISeatStore Seats => throw new NotSupportedException();

            public IAppAttestKeyStore AppAttestKeys => keys;

            public Task CommitAsync(CancellationToken cancellationToken)
            {
                owner.Commits++;
                return Task.CompletedTask;
            }

            public ValueTask DisposeAsync() => ValueTask.CompletedTask;
        }
    }

    /// <summary>Every closed remote_config key set (to a relaxing-looking value) and every flag on.</summary>
    private sealed class EverythingSet : IRemoteConfigReader, IFlagReader
    {
        public Task<IReadOnlyList<RemoteConfigRow>> ListAsync(CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<RemoteConfigRow>>([.. RemoteConfigKeys.All.Select(d => new RemoteConfigRow(d.Key, "ReportOnly", 9, Now))]);

        Task<IReadOnlyList<FlagState>> IFlagReader.ListAsync(CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<FlagState>>([.. FlagKeys.Known.Select(k => new FlagState(k, true, FlagRules.None, 9, Now))]);
    }

    private sealed class AlwaysPass : ILlmAttestationVerifier
    {
        public LlmAttestationMode Mode => LlmAttestationMode.Enforce;

        public Task<LlmAttestationDecision> VerifyAsync(LlmFeature feature, LlmAttestPlatform platform, InstallId installId, ReadOnlyMemory<byte> bodyHash, LlmAttestationProof? proof, CancellationToken cancellationToken) =>
            Task.FromResult(new LlmAttestationDecision(LlmAttestationVerdict.Pass, "ok", true));
    }

    private sealed class HostEnv(string name) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = name;

        public string ApplicationName { get; set; } = "t";

        public string ContentRootPath { get; set; } = "/";

        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = null!;
    }
}
