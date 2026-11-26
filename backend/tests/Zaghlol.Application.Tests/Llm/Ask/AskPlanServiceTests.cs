using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Ask;
using Zaghlol.Application.Llm.Attestation;
using Zaghlol.Application.Llm.Prompts;
using Zaghlol.Application.Llm.Quota;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Llm.Ask;

/// <summary>T-349: the gate order, what is counted per outcome, and "never reaches the provider" (negative proof 2).</summary>
public class AskPlanServiceTests
{
    // AC 1 (order): flag -> spend pause -> (consent, key) -> limiter -> attestation -> quota pre-check -> provider -> commit.
    [Fact]
    public async Task TheGatesRunCheapFirstAndTheQuotaIsCommittedLast()
    {
        var kit = new AskTestKit();

        var result = await kit.RunAsync();

        Assert.Equal(AskPlanKind.Answered, result.Kind);
        Assert.Equal(["flag:Ask", "spend", "limiter", "attestation", "quota-precheck", "quota-commit"], kit.Order);
        Assert.Equal(1, kit.Provider.Calls);
        Assert.True(result.Answer!.Counted);
        Assert.Equal(new LlmQuotaView(5, 3, 2, ScriptedQuota.Resets), result.Answer.Quota);
        Assert.Equal("PL-SPEND", AskTestKit.PlanName(result));
    }

    // AC 2: a flag turned off wins before anything else is consulted; the spend cap pauses the same way.
    [Fact]
    public async Task AFlagOffAnswersPausedBeforeAnyOtherGate()
    {
        var kit = new AskTestKit();
        kit.Flags.On.Clear();

        var result = await kit.RunAsync();

        Assert.Equal(LlmGateOutcome.Paused, result.Gate.Outcome);
        Assert.Equal(["flag:Ask"], kit.Order);
        Assert.Equal(0, kit.Provider.Calls);
    }

    [Fact]
    public async Task TheSpendCapAnswersPausedBeforeConsentAttestationAndQuota()
    {
        var kit = new AskTestKit();
        kit.Ledger.Rows.Add(new Zaghlol.Application.Llm.Spend.SpendRecord(DateOnly.FromDateTime(AskTestKit.Now.UtcDateTime), LlmFeature.Ask, "p1", "model-x", 1, 0, 0, 0, 10m));

        var result = await kit.RunAsync();

        Assert.Equal(LlmGateOutcome.Paused, result.Gate.Outcome);
        Assert.DoesNotContain("attestation", kit.Order);
        Assert.Equal(0, kit.Provider.Calls);
    }

    // Negative proof 2 (AC 4): every refusal leaves the provider call count at 0, and the later gates unconsulted.
    [Fact]
    public async Task EveryGateRefusalNeverReachesTheProvider()
    {
        var cases = new Dictionary<string, (Action<AskTestKit> Arrange, LlmGateOutcome Expected)>
        {
            ["missing or invalid attestation"] = (k => k.Verifier.Verdict = LlmAttestationVerdict.Refuse, LlmGateOutcome.AttestationFailed),
            ["attestation service out"] = (k => k.Verifier.Verdict = LlmAttestationVerdict.Unavailable, LlmGateOutcome.AttestationUnavailable),
            ["quota exhausted"] = (k => k.Quota.Check = new LlmQuotaCheck(LlmQuotaCheckKind.Exhausted, 5, 5, 0, ScriptedQuota.Resets), LlmGateOutcome.QuotaExhausted),
            ["cairo zone unavailable"] = (k => k.Quota.Check = new LlmQuotaCheck(LlmQuotaCheckKind.Unavailable, 0, 0, 0, ScriptedQuota.Resets), LlmGateOutcome.Paused),
            ["no provider key"] = (k => k.Keys.Has = false, LlmGateOutcome.Paused),
            ["no active provider"] = (k => k.Registry.Active = string.Empty, LlmGateOutcome.Paused),
            ["flag off"] = (k => k.Flags.On.Clear(), LlmGateOutcome.Paused),
            ["rate limited"] = (k => k.Limiter.Next = new LlmRateDecision(false, "install", 20), LlmGateOutcome.RateLimited),
        };

        foreach (var (name, (arrange, expected)) in cases)
        {
            var kit = new AskTestKit();
            arrange(kit);

            var result = await kit.RunAsync();

            Assert.True(expected == result.Gate.Outcome, name);
            Assert.True(kit.Provider.Calls == 0, name + ": provider calls");
            Assert.True(kit.Quota.Commits == 0, name + ": commits");
        }
    }

    [Fact]
    public async Task AConsentForAnotherProviderOrVersionIs409WithTheActiveProviderAndNeverReachesTheProvider()
    {
        foreach (var gate in new[] { AskTestKit.Gate(provider: "other"), AskTestKit.Gate(version: 2) })
        {
            var kit = new AskTestKit();

            var result = await kit.RunAsync(gate: gate);

            Assert.Equal(LlmGateOutcome.ConsentRequired, result.Gate.Outcome);
            Assert.Equal("p1", result.Gate.ProviderId);
            Assert.Equal(0, kit.Provider.Calls);
            Assert.DoesNotContain("limiter", kit.Order);
        }
    }

    [Fact]
    public async Task ARateLimitedCallDoesNotReachAttestationAndCountsOnTheMetric()
    {
        var kit = new AskTestKit();
        kit.Limiter.Next = new LlmRateDecision(false, "global", 7);

        var result = await kit.RunAsync();

        Assert.Equal(7, result.Gate.RetryAfterSeconds);
        Assert.Equal("global", result.Gate.Bucket);
        Assert.Equal(0, kit.Verifier.Calls);
        Assert.Contains("429:global", kit.Metrics.Events);
    }

    // The attestation verifier receives a missing member as null (422 missing, not 400).
    [Fact]
    public async Task AMissingAttestationReachesTheVerifierAsNull()
    {
        var kit = new AskTestKit();

        await kit.RunAsync(gate: AskTestKit.Gate(proof: null));

        Assert.Equal(1, kit.Verifier.Calls);
        Assert.Null(kit.Verifier.LastProof);
    }

    [Fact]
    public async Task OnlyAValidatedAccountIsPassedToTheBucketsAndTheQuota()
    {
        var kit = new AskTestKit();
        await kit.RunAsync(gate: AskTestKit.Gate(account: "valid"));
        Assert.Equal(ScriptedAccounts.Account, kit.Limiter.LastAccount);

        kit = new AskTestKit();
        var result = await kit.RunAsync(gate: AskTestKit.Gate(account: "expired-or-forged"));
        Assert.Null(kit.Limiter.LastAccount);
        Assert.Equal(AskPlanKind.Answered, result.Kind);
    }

    // AC 5 (FR-LLM-34): the provider request carries the system prompt id, the sent text and the language, and nothing else.
    [Fact]
    public async Task TheProviderRequestCarriesOnlyThePromptTheSentTextAndTheLanguage()
    {
        var kit = new AskTestKit();

        await kit.RunAsync("how much did I spend on ⟦CARD_1⟧; call me on 01001234567 or a@b.com", "en");

        var call = kit.Provider.Last!;
        Assert.Equal(LlmPromptIds.AskPlanV1, call.PromptId);
        Assert.Equal(LlmFeature.Ask, call.Feature);
        Assert.Equal("en", call.Lang);
        Assert.Equal(300, call.MaxOutputTokens);
        Assert.Equal("how much did I spend on ⟦CARD_1⟧; call me on ⟦PHONE⟧ or ⟦EMAIL⟧", call.UserText.Reveal());
        Assert.Equal(["Feature", "PromptId", "UserText", "Lang", "OutputSchema", "MaxOutputTokens"], typeof(LlmCall).GetProperties().Select(p => p.Name).Where(n => n != "EqualityContract").ToArray());
        Assert.Contains("ask-plan/1", call.OutputSchema.GetRawText(), StringComparison.Ordinal);
    }

    // AC 1: counted or not per outcome.
    [Theory]
    [InlineData("""{"v":1,"plan":"PL-FALLBACK","p":{"reason":"ambiguous"},"t":null}""", "PL-FALLBACK", true)]
    [InlineData("""{"v":1,"plan":"PL-REFUSE","p":{"reason":"offTopic","selfHarm":false},"t":null}""", "PL-REFUSE", true)]
    [InlineData(AskTestKit.SpendPlan, "PL-SPEND", true)]
    [InlineData("""{"v":1,"plan":"PL-SPEND","p":{"period":{"k":"cycle","o":0,"n":null,"m":null,"y":null},"filter":{"slug":null,"ref":"⟦CARD_9⟧","mention":null,"currency":null}},"t":null}""", "PL-FALLBACK", false)]
    [InlineData("not json", "PL-FALLBACK", false)]
    [InlineData("""{"v":1,"plan":"PL-SPEND"}""", "PL-FALLBACK", false)]
    public async Task OnlyAValidPlanIncludingFallbackAndRefuseIsCounted(string reply, string expectedPlan, bool counted)
    {
        var kit = new AskTestKit();
        kit.Provider.Reply = (_, _) => Task.FromResult(ScriptedProvider.Ok(reply));

        var result = await kit.RunAsync();

        Assert.Equal(AskPlanKind.Answered, result.Kind);
        Assert.Equal(expectedPlan, AskTestKit.PlanName(result));
        Assert.Equal(counted, result.Answer!.Counted);
        Assert.Equal(counted ? 1 : 0, kit.Quota.Commits);
        Assert.Equal(1, kit.Provider.Calls);
        Assert.Single(kit.Ledger.Rows); // every provider call is in the spend ledger, counted or not
    }

    [Fact]
    public async Task AValidatorFailureShowsTheRemainingQuotaOfThePreCheckAndRecordsOnlyACode()
    {
        var kit = new AskTestKit();
        kit.Provider.Reply = (_, _) => Task.FromResult(ScriptedProvider.Ok("""{"v":1,"plan":"PL-NOPE","p":{},"t":null}"""));

        var result = await kit.RunAsync();

        Assert.False(result.Answer!.Counted);
        Assert.Equal(new LlmQuotaView(5, 2, 3, ScriptedQuota.Resets), result.Answer.Quota);
        Assert.Contains("validation:schema_invalid", kit.Metrics.Events);
        Assert.Contains("fallback", kit.Metrics.Events);
    }

    [Fact]
    public async Task AnInvestPlanWhileTheInvestFlagIsOffBecomesAnUncountedFallback()
    {
        var kit = new AskTestKit();
        kit.Flags.On.Remove(LlmGateFeature.AskInvest);
        kit.Provider.Reply = (_, _) => Task.FromResult(ScriptedProvider.Ok(AskTestKit.InvestPlan));

        var result = await kit.RunAsync("what could my savings buy in gold");

        Assert.Equal("PL-FALLBACK", AskTestKit.PlanName(result));
        Assert.False(result.Answer!.Counted);
        Assert.Equal(0, kit.Quota.Commits);

        kit.Flags.On.Add(LlmGateFeature.AskInvest);
        result = await kit.RunAsync("what could my savings buy in gold");
        Assert.Equal("PL-INVEST", AskTestKit.PlanName(result));
        Assert.True(result.Answer!.Counted);
    }

    [Theory]
    [InlineData(LlmOutcome.Timeout)]
    [InlineData(LlmOutcome.Upstream)]
    public async Task AProviderTimeoutOrFailureIs502AndNotCounted(LlmOutcome outcome)
    {
        var kit = new AskTestKit();
        kit.Provider.Reply = (_, _) => Task.FromResult(LlmResult.Failed(outcome));

        var result = await kit.RunAsync();

        Assert.Equal(AskPlanKind.Upstream, result.Kind);
        Assert.Equal(0, kit.Quota.Commits);
        Assert.Single(kit.Ledger.Rows);
    }

    [Fact]
    public async Task AProviderExceptionIsDroppedIs502AndNeverCountedNorQuotedInTheResult()
    {
        var kit = new AskTestKit();
        kit.Provider.Reply = (call, _) => throw new InvalidOperationException("boom " + call.UserText.Reveal());

        var result = await kit.RunAsync();

        Assert.Equal(AskPlanKind.Upstream, result.Kind);
        Assert.Equal(0, kit.Quota.Commits);
        Assert.DoesNotContain("⟦CARD_1⟧", result.ToString(), StringComparison.Ordinal);
        Assert.NotEmpty(kit.Logs.Lines);
        Assert.All(kit.Logs.Lines, line => Assert.DoesNotContain("CARD_1", line, StringComparison.Ordinal));
        Assert.All(kit.Logs.Lines, line => Assert.DoesNotContain("boom", line, StringComparison.Ordinal));
    }

    [Fact]
    public async Task AValidatorFailureLogsOnlyAReasonCode()
    {
        var kit = new AskTestKit();
        kit.Provider.Reply = (_, _) => Task.FromResult(ScriptedProvider.Ok("""{"v":1,"plan":"PL-BALANCE","p":{"ref":"⟦CARD_CANARY_1⟧"},"t":null}"""));

        await kit.RunAsync();

        Assert.Equal(["ask_plan_rejected SchemaInvalid"], kit.Logs.Lines);
    }

    [Fact]
    public async Task AProviderWithoutAKeyThatSlipsPastTheGateIsPausedNotUpstream()
    {
        var kit = new AskTestKit();
        kit.Provider.Reply = (_, _) => throw new LlmServicePausedException();

        var result = await kit.RunAsync();

        Assert.Equal(AskPlanKind.Paused, result.Kind);
        Assert.Equal(0, kit.Quota.Commits);
    }

    // FR-LLM-10: Stop before the provider answered is not counted.
    [Fact]
    public async Task AStopBeforeTheProviderAnsweredIsNotCounted()
    {
        var kit = new AskTestKit();
        using var cts = new CancellationTokenSource();
        kit.Provider.Reply = async (_, ct) =>
        {
            await cts.CancelAsync();
            ct.ThrowIfCancellationRequested();
            return ScriptedProvider.Ok(AskTestKit.SpendPlan);
        };

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => kit.RunAsync(ct: cts.Token));

        Assert.Equal(0, kit.Quota.Commits);
    }

    // A Stop that arrives after the reply was validated does not stop the commit (the token is not passed to it).
    [Fact]
    public async Task AStopAfterTheValidatedReplyStillCounts()
    {
        var kit = new AskTestKit();
        using var cts = new CancellationTokenSource();
        kit.Provider.Reply = async (_, _) =>
        {
            var reply = ScriptedProvider.Ok(AskTestKit.SpendPlan);
            await cts.CancelAsync();
            return reply;
        };

        var result = await kit.RunAsync(ct: cts.Token);

        Assert.True(result.Answer!.Counted);
        Assert.Equal(1, kit.Quota.Commits);
    }

    [Fact]
    public async Task AnExhaustedCommitWithholdsThePlan()
    {
        var kit = new AskTestKit();
        kit.Quota.Commit = new LlmQuotaCommit(LlmQuotaCheckKind.Exhausted, 0, 0, false);

        var result = await kit.RunAsync();

        Assert.Equal(AskPlanKind.QuotaExhausted, result.Kind);
        Assert.Null(result.Answer);
        Assert.Equal(new LlmQuotaView(5, 5, 0, ScriptedQuota.Resets), result.Quota);
    }

    [Fact]
    public async Task ARetryAtTheLimitCallsTheProviderAgainAndIsAnsweredWithoutCountingTwice()
    {
        var kit = new AskTestKit();
        kit.Quota.Check = new LlmQuotaCheck(LlmQuotaCheckKind.Allowed, 5, 5, 0, ScriptedQuota.Resets, IsRetry: true);
        kit.Quota.Commit = new LlmQuotaCommit(LlmQuotaCheckKind.Allowed, 0, 0, true);

        var result = await kit.RunAsync();

        Assert.Equal(AskPlanKind.Answered, result.Kind);
        Assert.Equal(1, kit.Provider.Calls);
        Assert.Equal(new LlmQuotaView(5, 5, 0, ScriptedQuota.Resets), result.Answer!.Quota);
    }

    [Fact]
    public async Task TheMetricsCarryThePromptHashPrefixAndNoQuestionText()
    {
        var kit = new AskTestKit();

        await kit.RunAsync();

        var prompt = kit.Metrics.Events.Single(e => e.StartsWith("prompt:", StringComparison.Ordinal));
        Assert.Matches("^prompt:[0-9a-f]{12}$", prompt);
        Assert.Equal(EmbeddedLlmPromptCatalog.HashPrefix(new EmbeddedLlmPromptCatalog().GetSystemPrompt(LlmPromptIds.AskPlanV1)), prompt["prompt:".Length..]);
        Assert.All(kit.Metrics.Events, e => Assert.DoesNotContain("CARD", e, StringComparison.Ordinal));
        Assert.Contains("plan:PL-SPEND", kit.Metrics.Events);
    }

    [Fact]
    public async Task ATemplateThatPassedTheGrammarIsKeptAndABadOneIsDropped()
    {
        const string cut = """{"v":1,"plan":"PL-WHATIF-CUT","p":{"target":{"slug":"dining","ref":null,"mention":null,"currency":null},"mode":{"kind":"percent","percent":50,"amount":null,"currency":null},"months":12},"t":{"lang":"en","text":"If you cut {target} {pct} you save about {monthly} a month."}}""";
        var kit = new AskTestKit();
        kit.Provider.Reply = (_, _) => Task.FromResult(ScriptedProvider.Ok(cut));
        var result = await kit.RunAsync("what if I cut dining by 50% for 12 months");
        Assert.Contains("\"t\":{\"lang\":\"en\"", AskTestKit.Text(result), StringComparison.Ordinal);

        kit.Provider.Reply = (_, _) => Task.FromResult(ScriptedProvider.Ok(cut.Replace("you save about {monthly}", "you save 500", StringComparison.Ordinal)));
        result = await kit.RunAsync("what if I cut dining by 50% for 12 months");
        Assert.Equal("PL-WHATIF-CUT", AskTestKit.PlanName(result));
        Assert.True(result.Answer!.Counted);
        Assert.EndsWith("\"t\":null}", AskTestKit.Text(result), StringComparison.Ordinal);
    }
}
