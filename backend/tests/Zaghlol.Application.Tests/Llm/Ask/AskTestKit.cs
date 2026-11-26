using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Zaghlol.Application.Config;
using Zaghlol.Application.Entitlements;
using Zaghlol.Application.Flags;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Ask;
using Zaghlol.Application.Llm.Attestation;
using Zaghlol.Application.Llm.Plans;
using Zaghlol.Application.Llm.Prompts;
using Zaghlol.Application.Llm.Quota;
using Zaghlol.Application.Llm.Spend;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Llm.Ask;

/// <summary>The fakes of the Ask pipeline tests: every gate is scripted and counts its calls, so order and "never reached" are assertions.</summary>
internal sealed class AskTestKit
{
    public static readonly InstallId Install = InstallId.Parse("00000000-0000-4000-8000-0000000000a1");
    public static readonly DateTimeOffset Now = new(2026, 11, 26, 12, 0, 0, TimeSpan.Zero);
    public const string Question = "how much did I spend on ⟦CARD_1⟧ this month";
    public const string SpendPlan = """{"v":1,"plan":"PL-SPEND","p":{"period":{"k":"cycle","o":0,"n":null,"m":null,"y":null},"filter":{"slug":null,"ref":"⟦CARD_1⟧","mention":null,"currency":null}},"t":null}""";
    public const string InvestPlan = """{"v":1,"plan":"PL-INVEST","p":{"source":{"kind":"savedLastPeriod","whatIf":null,"amount":null},"instruments":["gold"],"horizonMonths":12},"t":null}""";

    public List<string> Order { get; } = [];

    public ScriptedFlags Flags { get; } = new();

    public ScriptedProvider Provider { get; } = new();

    public ScriptedVerifier Verifier { get; }

    public ScriptedQuota Quota { get; }

    public ScriptedLimiter Limiter { get; }

    public ScriptedRegistry Registry { get; }

    public ScriptedKeys Keys { get; } = new();

    public ScriptedAccounts Accounts { get; } = new();

    public MemoryLedger Ledger { get; } = new();

    public RecordingMetrics Metrics { get; } = new();

    public SpendGuard Spend { get; }

    public AskPlanService Service { get; }

    public CapturingLogger Logs { get; } = new();

    public LlmGateChain Chain { get; }

    public AskTestKit()
    {
        Verifier = new ScriptedVerifier(Order);
        Quota = new ScriptedQuota(Order);
        Limiter = new ScriptedLimiter(Order);
        Registry = new ScriptedRegistry(Provider);
        Flags.Order = Order;
        Spend = new SpendGuard(Ledger, new Config(), new Prices(), new Alerts(), Metrics, new Clock(), NullLogger<SpendGuard>.Instance);
        Chain = new LlmGateChain(Flags, new OrderedSpend(Spend, Order), Registry, Keys, Accounts, Limiter, Verifier, Quota, Metrics, new Clock());
        Service = new AskPlanService(Chain, Flags, Registry, new EmbeddedLlmPromptCatalog(), Spend, new PlanValidator(), Quota, Metrics, Logs);
    }

    public static LlmGateRequest Gate(string requestId = "01JD8Z3Q4F6R7T9V0W1X2Y3Z4A", string provider = "p1", int version = 1, string? account = null, LlmAttestationProof? proof = null) => new(
        LlmFeature.Ask, Install, "android", "1.0.0", account is null ? null : new Sensitive<string>(account), "10.0.0.0/24", provider, version, requestId,
        new byte[32], proof);

    public static AskPlanRequest Request(string question = Question, string lang = "en") =>
        new("01JD8Z3Q4F6R7T9V0W1X2Y3Z4A", new LlmSensitive<string>(question), lang, "p1", 1, null, false);

    public Task<AskPlanResult> RunAsync(string question = Question, string lang = "en", LlmGateRequest? gate = null, CancellationToken ct = default) =>
        Service.PlanAsync(gate ?? Gate(), Request(question, lang), ct);

    public static string Text(AskPlanResult result) => Encoding.UTF8.GetString(result.Answer!.PlanJson.Reveal());

    public static string PlanName(AskPlanResult result) => JsonDocument.Parse(result.Answer!.PlanJson.Reveal()).RootElement.GetProperty("plan").GetString()!;

    internal sealed class Clock : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => Now;
    }

    internal sealed class Config : IRemoteConfigService
    {
        public Task<RemoteConfigSnapshot> GetAsync(CancellationToken cancellationToken) => Task.FromResult(RemoteConfigService.Build([]));
    }

    internal sealed class Alerts : IOpsAlertSink
    {
        public Task<bool> SendAsync(string message, CancellationToken cancellationToken) => Task.FromResult(true);
    }

    internal sealed class Prices : ILlmPriceList
    {
        public bool TryGet(string providerId, out LlmPriceEntry entry)
        {
            entry = new LlmPriceEntry("model-x", new LlmPrices(1m, 0.5m, 4m));
            return providerId == "p1";
        }
    }

    internal sealed class MemoryLedger : ISpendLedgerStore
    {
        public List<SpendRecord> Rows { get; } = [];

        public Task RecordAsync(SpendRecord record, CancellationToken cancellationToken)
        {
            Rows.Add(record);
            return Task.CompletedTask;
        }

        public Task<decimal> TotalAsync(DateOnly fromInclusive, DateOnly untilExclusive, CancellationToken cancellationToken) =>
            Task.FromResult(Rows.Where(r => r.Day >= fromInclusive && r.Day < untilExclusive).Sum(r => r.CostUsd));

        public Task<bool> TryClaimAlertAsync(LlmFeature feature, DateOnly monthStart, CancellationToken cancellationToken) => Task.FromResult(true);
    }

    /// <summary>Records that the spend pause was consulted, then delegates to the real guard.</summary>
    internal sealed class OrderedSpend(SpendGuard inner, List<string> order) : ISpendGuard
    {
        public Task<bool> IsPausedAsync(CancellationToken cancellationToken)
        {
            order.Add("spend");
            return inner.IsPausedAsync(cancellationToken);
        }

        public Task<SpendReservation> ReserveAsync(LlmFeature feature, string providerId, int maxOutputTokens, CancellationToken cancellationToken) =>
            inner.ReserveAsync(feature, providerId, maxOutputTokens, cancellationToken);
    }
}

/// <summary>Everything the service writes to its logger, formatted, with exception text.</summary>
internal sealed class CapturingLogger : ILogger<AskPlanService>
{
    public List<string> Lines { get; } = [];

    public IDisposable? BeginScope<TState>(TState state)
        where TState : notnull => null;

    public bool IsEnabled(LogLevel logLevel) => true;

    public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
        Lines.Add(formatter(state, exception) + exception);
}

internal sealed class ScriptedFlags : ILlmFeatureGate
{
    public HashSet<LlmGateFeature> On { get; } = [LlmGateFeature.Ask, LlmGateFeature.AskInvest];

    public List<string>? Order { get; set; }

    public Task<bool> IsOnAsync(LlmGateFeature feature, InstallId installId, string platform, string appVersion, CancellationToken cancellationToken)
    {
        Order?.Add("flag:" + feature);
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(On.Contains(feature));
    }
}

internal sealed class ScriptedProvider : ILlmProvider
{
    public string Id => "p1";

    public int Calls { get; private set; }

    public LlmCall? Last { get; private set; }

    public Func<LlmCall, CancellationToken, Task<LlmResult>> Reply { get; set; } = (_, _) => Task.FromResult(Ok(AskTestKit.SpendPlan));

    public static LlmResult Ok(string json) => new(LlmOutcome.Ok, new LlmSensitive<byte[]>(Encoding.UTF8.GetBytes(json)), new LlmUsage(900, 800, 120));

    public Task<LlmResult> CompleteAsync(LlmCall request, CancellationToken cancellationToken)
    {
        Calls++;
        Last = request;
        return Reply(request, cancellationToken);
    }
}

internal sealed class ScriptedRegistry(ScriptedProvider provider) : ILlmProviderRegistry
{
    public string Active { get; set; } = "p1";

    public ValueTask<string> ActiveIdAsync(CancellationToken cancellationToken) => ValueTask.FromResult(Active);

    public ValueTask<ILlmProvider> ActiveAsync(CancellationToken cancellationToken) => ValueTask.FromResult<ILlmProvider>(provider);

    public ILlmProvider Resolve(string id) => id == provider.Id ? provider : throw new LlmConfigurationException("unknown");
}

internal sealed class ScriptedKeys : ILlmApiKeyProvider
{
    public bool Has { get; set; } = true;

    public bool HasKey(string providerId) => Has;

    public ValueTask<LlmSensitive<string>> GetKeyAsync(string providerId, CancellationToken cancellationToken) =>
        throw new NotSupportedException();
}

internal sealed class ScriptedAccounts : IAccountTokenValidator
{
    public static readonly Guid Account = Guid.Parse("00000000-0000-4000-8000-0000000000ac");

    public Task<ValidatedAccountToken?> ValidateAsync(Sensitive<string>? token, InstallId caller, DateTimeOffset now, CancellationToken cancellationToken) =>
        Task.FromResult<ValidatedAccountToken?>(token is not null && token.Value.Reveal() == "valid" ? new ValidatedAccountToken(Account, now.AddDays(1)) : null);
}

internal sealed class ScriptedLimiter(List<string> order) : ILlmRateLimiter
{
    public LlmRateDecision Next { get; set; } = LlmRateDecision.Ok;

    /// <summary>The stage <see cref="Next"/> applies to; the other stage always allows.</summary>
    public LlmRateStage RefuseAt { get; set; } = LlmRateStage.Owner;

    public Guid? LastAccount { get; private set; }

    public LlmRateDecision TryAcquire(LlmFeature feature, InstallId install, Guid? account, string networkKey, LlmRateStage stage)
    {
        order.Add("limiter:" + stage);
        LastAccount = account;
        return stage == RefuseAt ? Next : LlmRateDecision.Ok;
    }
}

internal sealed class ScriptedVerifier(List<string> order) : ILlmAttestationVerifier
{
    public LlmAttestationVerdict Verdict { get; set; } = LlmAttestationVerdict.Pass;

    public int Calls { get; private set; }

    public LlmAttestationProof? LastProof { get; private set; }

    public LlmAttestationMode Mode => LlmAttestationMode.Enforce;

    public Task<LlmAttestationDecision> VerifyAsync(LlmFeature feature, LlmAttestPlatform platform, InstallId installId, ReadOnlyMemory<byte> bodyHash, LlmAttestationProof? proof, CancellationToken cancellationToken)
    {
        order.Add("attestation");
        Calls++;
        LastProof = proof;
        return Task.FromResult(new LlmAttestationDecision(Verdict, Verdict == LlmAttestationVerdict.Pass ? "ok" : "missing", Verdict == LlmAttestationVerdict.Pass));
    }
}

internal sealed class ScriptedQuota(List<string> order) : ILlmQuotaStore
{
    public static readonly DateTimeOffset Resets = new(2026, 11, 30, 22, 0, 0, TimeSpan.Zero);

    public LlmQuotaCheck Check { get; set; } = new(LlmQuotaCheckKind.Allowed, 5, 2, 3, Resets);

    public LlmQuotaCommit Commit { get; set; } = new(LlmQuotaCheckKind.Allowed, 1, 2, false);

    public int PreChecks { get; private set; }

    public int Commits { get; private set; }

    public Task<LlmQuotaCheck> PreCheckAsync(LlmFeature feature, InstallId install, Guid? account, string requestId, CancellationToken cancellationToken)
    {
        order.Add("quota-precheck");
        PreChecks++;
        return Task.FromResult(Check);
    }

    public Task<LlmQuotaCommit> CommitAsync(LlmFeature feature, InstallId install, Guid? account, string requestId, int n, CancellationToken cancellationToken)
    {
        order.Add("quota-commit");
        Commits++;
        return Task.FromResult(Commit);
    }
}

internal sealed class RecordingMetrics : ILlmMetrics
{
    public List<string> Events { get; } = [];

    public void ProviderCall(LlmFeature feature, string providerId, LlmOutcome outcome, TimeSpan latency, LlmUsage usage, decimal costUsd) => Events.Add("call:" + outcome);

    public void Plan(LlmFeature feature, string planName) => Events.Add("plan:" + planName);

    public void Fallback(LlmFeature feature) => Events.Add("fallback");

    public void Refusal(LlmFeature feature, string reason) => Events.Add("refusal:" + reason);

    public void ValidationFailure(LlmFeature feature, string reason) => Events.Add("validation:" + reason);

    public void RateLimited(LlmFeature feature, string bucket) => Events.Add("429:" + bucket);

    public void QuotaHit(LlmFeature feature) => Events.Add("quota-hit");

    public void Prompt(LlmFeature feature, string promptHashPrefix) => Events.Add("prompt:" + promptHashPrefix);

    public void Paused(LlmFeature feature, string reason) => Events.Add("paused:" + reason);
}
