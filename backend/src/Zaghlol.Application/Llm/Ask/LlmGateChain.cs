using Zaghlol.Application.Entitlements;
using Zaghlol.Application.Llm.Attestation;
using Zaghlol.Application.Llm.Quota;
using Zaghlol.Application.Llm.Spend;
using Zaghlol.Domain;

namespace Zaghlol.Application.Llm.Ask;

/// <summary>The consent terms the phone's sheet shows: the provider id plus this version (bumped when the sheet text changes, T-343 mirrors it).</summary>
public static class LlmConsentTerms
{
    public const int Version = 1;
}

/// <summary>One bucket decision (<see cref="Bucket"/> is a fixed name: install, account, network, global).</summary>
public sealed record LlmRateDecision(bool Allowed, string Bucket, int RetryAfterSeconds)
{
    public static LlmRateDecision Ok { get; } = new(true, string.Empty, 0);
}

/// <summary>The in-process buckets of ask-llm §4.3 (install 3/min and 20/day, the same per account, /24 30/min, global per minute). The key is memory only.</summary>
public interface ILlmRateLimiter
{
    /// <summary>
    /// <see cref="LlmRateStage.Owner"/> draws the install and account buckets (the cheap pre-check before attestation, FU-432);
    /// <see cref="LlmRateStage.Shared"/> draws the /24 and global buckets and runs only after attestation passed, so an unattested caller can't drain them.
    /// </summary>
    LlmRateDecision TryAcquire(LlmFeature feature, InstallId install, Guid? account, string networkKey, LlmRateStage stage);
}

public enum LlmRateStage
{
    Owner,
    Shared,
}

public enum LlmGateOutcome
{
    /// <summary>Every gate passed; <see cref="LlmGateResult.ProviderId"/> and <see cref="LlmGateResult.Quota"/> are set.</summary>
    Admitted,

    /// <summary><c>503 LLM_SERVICE_PAUSED</c>.</summary>
    Paused,

    /// <summary><c>409 LLM_CONSENT_REQUIRED</c> with <see cref="LlmGateResult.ProviderId"/>.</summary>
    ConsentRequired,

    /// <summary><c>429 RATE_LIMITED</c> with <see cref="LlmGateResult.Bucket"/> and <see cref="LlmGateResult.RetryAfterSeconds"/>.</summary>
    RateLimited,

    /// <summary><c>422 DEVICE_ATTESTATION_FAILED</c>.</summary>
    AttestationFailed,

    /// <summary><c>503 UPSTREAM_UNAVAILABLE</c>: the attestation service is out or not configured.</summary>
    AttestationUnavailable,

    /// <summary><c>403 LLM_QUOTA_EXHAUSTED</c> with <see cref="LlmGateResult.Quota"/>.</summary>
    QuotaExhausted,
}

public sealed record LlmGateRequest(
    LlmFeature Feature,
    InstallId Install,
    string Platform,
    string AppVersion,
    Sensitive<string>? AccountToken,
    string NetworkKey,
    string ConsentProvider,
    int ConsentVersion,
    string RequestId,
    ReadOnlyMemory<byte> BodyHash,
    LlmAttestationProof? Proof);

public sealed record LlmGateResult(
    LlmGateOutcome Outcome,
    string ProviderId = "",
    Guid? Account = null,
    LlmQuotaCheck? Quota = null,
    string Bucket = "",
    int RetryAfterSeconds = 0)
{
    public bool IsAdmitted => Outcome == LlmGateOutcome.Admitted;
}

/// <summary>
/// The gate chain shared by <c>POST /v1/ask/plan</c> and <c>POST /v1/categorise</c> (T-349, reused by T-352), cheapest first and failing
/// closed (ask-llm §1): flag per install (read on every request, never from the app's cached copy) -> spend pause -> consent = the active
/// provider and consent version (a provider without a key is paused) -> account token validated once -> buckets -> attestation (a missing
/// proof is a refusal) -> quota pre-check (read only). It never calls a provider and commits nothing. A retry (same request id) passes the
/// pre-check at the limit (T-335). Every refusal counts on the LLM metrics with a fixed reason.
/// </summary>
public sealed class LlmGateChain(
    ILlmFeatureGate flags,
    ISpendGuard spend,
    ILlmProviderRegistry registry,
    ILlmApiKeyProvider keys,
    IAccountTokenValidator accounts,
    ILlmRateLimiter limiter,
    ILlmAttestationVerifier attestation,
    ILlmQuotaStore quota,
    ILlmMetrics metrics,
    TimeProvider clock)
{
    public async Task<LlmGateResult> AdmitAsync(LlmGateRequest request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        var feature = request.Feature;
        var gate = feature == LlmFeature.Ask ? LlmGateFeature.Ask : LlmGateFeature.Categorise;

        // 1. Flag per install: the kill switch works on the next request.
        if (!await flags.IsOnAsync(gate, request.Install, request.Platform, request.AppVersion, cancellationToken).ConfigureAwait(false))
        {
            metrics.Paused(feature, "flag_off");
            return new LlmGateResult(LlmGateOutcome.Paused);
        }

        // 2. Spend cap (cached 60 s; fails closed).
        if (await spend.IsPausedAsync(cancellationToken).ConfigureAwait(false))
        {
            metrics.Paused(feature, "spend_cap");
            return new LlmGateResult(LlmGateOutcome.Paused);
        }

        // 3. Consent = the active provider and the consent version.
        var providerId = await registry.ActiveIdAsync(cancellationToken).ConfigureAwait(false);
        if (providerId.Length == 0 || !keys.HasKey(providerId))
        {
            metrics.Paused(feature, "no_key");
            return new LlmGateResult(LlmGateOutcome.Paused);
        }

        if (!string.Equals(request.ConsentProvider, providerId, StringComparison.Ordinal) || request.ConsentVersion != LlmConsentTerms.Version)
        {
            return new LlmGateResult(LlmGateOutcome.ConsentRequired, providerId);
        }

        // 4. The account token (none or invalid = no account, never an error: BR-GOLD-06), then 5. the buckets.
        var now = clock.GetUtcNow();
        var validated = await accounts.ValidateAsync(request.AccountToken, request.Install, now, cancellationToken).ConfigureAwait(false);
        Guid? account = validated?.AccountId;
        var rate = limiter.TryAcquire(feature, request.Install, account, request.NetworkKey, LlmRateStage.Owner);
        if (!rate.Allowed)
        {
            metrics.RateLimited(feature, rate.Bucket);
            return new LlmGateResult(LlmGateOutcome.RateLimited, providerId, account, Bucket: rate.Bucket, RetryAfterSeconds: Math.Max(1, rate.RetryAfterSeconds));
        }

        // 6. Attestation, bound to the body and this install.
        var platform = string.Equals(request.Platform, "ios", StringComparison.Ordinal) ? LlmAttestPlatform.Ios : LlmAttestPlatform.Android;
        var decision = await attestation.VerifyAsync(feature, platform, request.Install, request.BodyHash, request.Proof, cancellationToken).ConfigureAwait(false);
        if (decision.Verdict == LlmAttestationVerdict.Refuse)
        {
            return new LlmGateResult(LlmGateOutcome.AttestationFailed, providerId, account);
        }

        if (decision.Verdict == LlmAttestationVerdict.Unavailable)
        {
            return new LlmGateResult(LlmGateOutcome.AttestationUnavailable, providerId, account);
        }

        // 6b. The shared /24 and global buckets, only for a caller that passed attestation (FU-432).
        rate = limiter.TryAcquire(feature, request.Install, account, request.NetworkKey, LlmRateStage.Shared);
        if (!rate.Allowed)
        {
            metrics.RateLimited(feature, rate.Bucket);
            return new LlmGateResult(LlmGateOutcome.RateLimited, providerId, account, Bucket: rate.Bucket, RetryAfterSeconds: Math.Max(1, rate.RetryAfterSeconds));
        }

        // 7. Tier and quota pre-check (read only; commit happens after a valid reply).
        var check = await quota.PreCheckAsync(feature, request.Install, account, request.RequestId, cancellationToken).ConfigureAwait(false);
        switch (check.Kind)
        {
            case LlmQuotaCheckKind.Unavailable:
                metrics.Paused(feature, "quota_unavailable");
                return new LlmGateResult(LlmGateOutcome.Paused, providerId, account);
            case LlmQuotaCheckKind.Exhausted when feature == LlmFeature.Categorise:
                // Categorise reports quota per merchant, never as 403: catalog and cache hits still arrive at 0 left (llm-categorise §3).
                return new LlmGateResult(LlmGateOutcome.Admitted, providerId, account, check);
            case LlmQuotaCheckKind.Exhausted:
                metrics.QuotaHit(feature);
                return new LlmGateResult(LlmGateOutcome.QuotaExhausted, providerId, account, check);
            default:
                return new LlmGateResult(LlmGateOutcome.Admitted, providerId, account, check);
        }
    }
}
