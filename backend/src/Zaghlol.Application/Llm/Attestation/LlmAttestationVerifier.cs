using System.Security.Cryptography;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Purchases.Attestation;
using Zaghlol.Application.Seats;
using Zaghlol.Domain;

namespace Zaghlol.Application.Llm.Attestation;

/// <summary>The calling app's platform, from <c>Zaghlol-App</c>; decides which proof type is acceptable.</summary>
public enum LlmAttestPlatform
{
    Android,
    Ios,
}

/// <summary>What the endpoint does with the request.</summary>
public enum LlmAttestationVerdict
{
    /// <summary>Continue (verified, or ReportOnly).</summary>
    Pass,

    /// <summary><c>422 DEVICE_ATTESTATION_FAILED</c>, not counted.</summary>
    Refuse,

    /// <summary><c>503 UPSTREAM_UNAVAILABLE</c>, not counted: verifier unconfigured or the attestation service is out.</summary>
    Unavailable,
}

/// <summary>
/// The decision for one request. <see cref="Reason"/> is a fixed code (<see cref="LlmAttestationReasons.All"/>);
/// <see cref="Verified"/> is false for every ReportOnly pass that did not verify.
/// </summary>
public sealed record LlmAttestationDecision(LlmAttestationVerdict Verdict, string Reason, bool Verified);

/// <summary>The fixed reason codes of LLM attestation (logs and the metric).</summary>
public static class LlmAttestationReasons
{
    public const string Ok = "ok";
    public const string Missing = "missing";
    public const string WrongType = "wrong_type";
    public const string NotConfigured = "not_configured";
    public const string Unavailable = "unavailable";

    public static IReadOnlyList<string> All { get; } = [Ok, Missing, WrongType, NotConfigured, Unavailable, .. AttestationCodes.All];
}

/// <summary>Body-bound device attestation for <c>/v1/ask/plan</c> and <c>/v1/categorise</c> (FR-LLM-14, T-336).</summary>
public interface ILlmAttestationVerifier
{
    LlmAttestationMode Mode { get; }

    /// <param name="bodyHash">From <see cref="LlmBinding.BodyHash(LlmFeature, InstallId, System.Text.Json.JsonElement)"/> (32 bytes).</param>
    /// <param name="proof">The parsed <c>attestation</c> member, or <c>null</c> when the body has none.</param>
    Task<LlmAttestationDecision> VerifyAsync(
        LlmFeature feature,
        LlmAttestPlatform platform,
        InstallId installId,
        ReadOnlyMemory<byte> bodyHash,
        LlmAttestationProof? proof,
        CancellationToken cancellationToken);
}

/// <summary>Whether the store verifier of a platform has real configuration (credential, package, Team ID, bundle).</summary>
public interface ILlmAttestationReadiness
{
    bool IsConfigured(LlmAttestPlatform platform);
}

/// <summary>Counts each decision by fixed tags.</summary>
public interface ILlmAttestationTelemetry
{
    void Decided(LlmFeature feature, LlmAttestationMode mode, LlmAttestPlatform platform, LlmAttestationVerdict verdict, string reason);
}

/// <summary>
/// The mode-aware verifier (design note in <c>docs/04-tasks/tasks/T-336.md</c>). Its mode comes only from
/// <see cref="LlmAttestationSettings"/> built at startup; it reads no header, flag or remote config.
/// </summary>
public sealed partial class LlmAttestationVerifier(
    LlmAttestationSettings settings,
    IPlayIntegrityVerifier playIntegrity,
    IAppAttestVerifier appAttest,
    ISeatTransactionFactory transactions,
    ILlmAttestationReadiness readiness,
    ILlmAttestationTelemetry telemetry,
    ILogger<LlmAttestationVerifier> logger) : ILlmAttestationVerifier
{
    public LlmAttestationMode Mode => settings.Mode;

    public async Task<LlmAttestationDecision> VerifyAsync(
        LlmFeature feature,
        LlmAttestPlatform platform,
        InstallId installId,
        ReadOnlyMemory<byte> bodyHash,
        LlmAttestationProof? proof,
        CancellationToken cancellationToken)
    {
        if (bodyHash.Length != LlmBinding.HashLength)
        {
            throw new ArgumentException("bodyHash must be 32 bytes.", nameof(bodyHash));
        }

        var (outcome, reason) = settings.Mode == LlmAttestationMode.Fake
            ? VerifyDev(bodyHash.Span, proof)
            : await VerifyStoreAsync(feature, platform, installId, bodyHash, proof, cancellationToken).ConfigureAwait(false);
        reason ??= outcome.Code;

        var verdict = outcome.Outcome switch
        {
            AttestationOutcome.Verified => LlmAttestationVerdict.Pass,
            _ when settings.Mode == LlmAttestationMode.ReportOnly => LlmAttestationVerdict.Pass,
            AttestationOutcome.Unavailable => LlmAttestationVerdict.Unavailable,
            _ => LlmAttestationVerdict.Refuse,
        };

        telemetry.Decided(feature, settings.Mode, platform, verdict, reason);
        if (!outcome.IsVerified)
        {
            var featureTag = FeatureTag(feature);
            var modeTag = ModeTag(settings.Mode);
            var verdictTag = VerdictTag(verdict);
            LogNotVerified(logger, featureTag, modeTag, reason, verdictTag);
        }

        return new LlmAttestationDecision(verdict, reason, outcome.IsVerified);
    }

    public static string FeatureTag(LlmFeature feature) => feature == LlmFeature.Ask ? "ask" : "cat";

    public static string ModeTag(LlmAttestationMode mode) => mode switch
    {
        LlmAttestationMode.Fake => "fake",
        LlmAttestationMode.ReportOnly => "report_only",
        _ => "enforce",
    };

    public static string VerdictTag(LlmAttestationVerdict verdict) => verdict switch
    {
        LlmAttestationVerdict.Pass => "pass",
        LlmAttestationVerdict.Refuse => "refuse",
        _ => "unavailable",
    };

    private async Task<(AttestationResult Outcome, string? Reason)> VerifyStoreAsync(
        LlmFeature feature,
        LlmAttestPlatform platform,
        InstallId installId,
        ReadOnlyMemory<byte> bodyHash,
        LlmAttestationProof? proof,
        CancellationToken cancellationToken)
    {
        // Unconfigured verifier: 503 before the proof is looked at, so every request of that platform is 503 (ask-llm §5 stage 2).
        if (!readiness.IsConfigured(platform))
        {
            return (AttestationResult.Unavailable, LlmAttestationReasons.NotConfigured);
        }

        switch (proof)
        {
            case null:
                return (AttestationResult.Failed(AttestationFailure.Chain), LlmAttestationReasons.Missing);

            case LlmPlayIntegrityProof play when platform == LlmAttestPlatform.Android:
                return (await playIntegrity.VerifyAsync(play.Token, bodyHash, cancellationToken).ConfigureAwait(false), null);

            case LlmAppAttestProof apple when platform == LlmAttestPlatform.Ios:
                return (await VerifyAppAttestAsync(feature, installId, bodyHash, apple, cancellationToken).ConfigureAwait(false), null);

            default:
                // A dev proof outside Fake, or a proof of the other platform.
                return (AttestationResult.Failed(AttestationFailure.Chain), LlmAttestationReasons.WrongType);
        }
    }

    /// <summary>
    /// One App-login transaction: the optional first-use registration, then the assertion over <c>clientDataHash</c>. Commits only
    /// when verified, so the raised counter (the replay guard) and a new key stay; any refusal rolls both back.
    /// </summary>
    private async Task<AttestationResult> VerifyAppAttestAsync(
        LlmFeature feature, InstallId installId, ReadOnlyMemory<byte> bodyHash, LlmAppAttestProof proof, CancellationToken cancellationToken)
    {
        var clientDataHash = LlmBinding.ClientDataHash(feature, bodyHash.Span);
        var transaction = await transactions.BeginAsync(SeatLogin.App, cancellationToken).ConfigureAwait(false);
        await using (transaction.ConfigureAwait(false))
        {
            if (proof.AttestationObject is { } attestationObject)
            {
                var registered = await appAttest.RegisterAttestationAsync(
                    transaction.AppAttestKeys, installId, proof.KeyId, attestationObject, clientDataHash, cancellationToken).ConfigureAwait(false);
                if (!registered.IsVerified)
                {
                    return registered;
                }
            }

            var assertion = await appAttest.VerifyAssertionAsync(
                transaction.AppAttestKeys, installId, proof.KeyId, proof.Assertion, clientDataHash, cancellationToken).ConfigureAwait(false);
            if (assertion.IsVerified)
            {
                await transaction.CommitAsync(cancellationToken).ConfigureAwait(false);
            }

            return assertion;
        }
    }

    /// <summary>Fake mode: only <c>dev</c> with <c>base64url(HMAC-SHA256(devKey, bodyHash))</c>, compared in fixed time.</summary>
    private (AttestationResult Outcome, string? Reason) VerifyDev(ReadOnlySpan<byte> bodyHash, LlmAttestationProof? proof)
    {
        if (proof is null)
        {
            return (AttestationResult.Failed(AttestationFailure.Chain), LlmAttestationReasons.Missing);
        }

        if (proof is not LlmDevProof dev || settings.DevProofKey() is not { } key)
        {
            return (AttestationResult.Failed(AttestationFailure.Chain), LlmAttestationReasons.WrongType);
        }

        try
        {
            var expected = System.Text.Encoding.ASCII.GetBytes(DevProof(key, bodyHash));
            var actual = System.Text.Encoding.ASCII.GetBytes(dev.Proof.Reveal() ?? string.Empty);
            return CryptographicOperations.FixedTimeEquals(expected, actual)
                ? (AttestationResult.Verified(ProofLevel.Device), null)
                : (AttestationResult.Failed(AttestationFailure.HashMismatch), null);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(key);
        }
    }

    /// <summary>The dev proof text for <paramref name="bodyHash"/> (debug builds and tests compute the same).</summary>
    public static string DevProof(ReadOnlySpan<byte> key, ReadOnlySpan<byte> bodyHash) =>
        Convert.ToBase64String(HMACSHA256.HashData(key, bodyHash)).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    [LoggerMessage(Level = LogLevel.Information, Message = "llm_attestation_not_verified feature={feature} mode={mode} reason={reason} verdict={verdict}")]
    private static partial void LogNotVerified(ILogger logger, string feature, string mode, string reason, string verdict);
}
