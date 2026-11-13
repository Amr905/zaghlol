using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases.Attestation;

/// <summary>
/// Why a device attestation was refused (error-handling §3.2). The only value ever logged for a failure; the endpoint maps every
/// one of them to <c>422 DEVICE_ATTESTATION_FAILED</c>.
/// </summary>
public enum AttestationFailure
{
    /// <summary>The proof is bound to another body or install: Play <c>requestHash</c>, App Attest nonce or assertion signature.</summary>
    HashMismatch,

    /// <summary>Play Integrity <c>timestampMillis</c> older than 5 min (or in the future), the only "expired" case (D-53).</summary>
    Stale,

    /// <summary>A Play Integrity token already used.</summary>
    Replayed,

    /// <summary>Not our app: package name, <c>PLAY_RECOGNIZED</c>, App ID (RP ID hash) or the App Attest environment.</summary>
    AppUnrecognized,

    /// <summary>Play Integrity: neither <c>MEETS_DEVICE_INTEGRITY</c> nor <c>MEETS_BASIC_INTEGRITY</c>.</summary>
    NoIntegrity,

    /// <summary>App Attest counter: not 0 on attestation, not strictly increasing on assertion.</summary>
    Counter,

    /// <summary>No App Attest key for this install, a different key ID, or a key ID registered to another install.</summary>
    KeyUnknown,

    /// <summary>Malformed or unverifiable proof: certificate chain, CBOR/ASN.1 structure, key identity, or a token Google rejects.</summary>
    Chain,
}

/// <summary>Play Integrity device verdict level of a verified token (R-19).</summary>
public enum ProofLevel
{
    Device,
    Basic,
}

/// <summary>Outcome kind of an attestation check.</summary>
public enum AttestationOutcome
{
    Verified,

    /// <summary>The proof is invalid: <see cref="AttestationResult.Failure"/> says why. <c>422 DEVICE_ATTESTATION_FAILED</c>.</summary>
    Failed,

    /// <summary>An upstream outage, timeout or quota: never a verification failure. <c>503 UPSTREAM_UNAVAILABLE</c>.</summary>
    Unavailable,
}

/// <summary>The result of one attestation check. Carries no proof material.</summary>
public sealed record AttestationResult
{
    private AttestationResult(AttestationOutcome outcome, AttestationFailure? failure, ProofLevel? level)
    {
        Outcome = outcome;
        Failure = failure;
        Level = level;
    }

    public AttestationOutcome Outcome { get; }

    public AttestationFailure? Failure { get; }

    /// <summary>Play Integrity only: <see cref="ProofLevel.Device"/> or <see cref="ProofLevel.Basic"/>; App Attest: <see cref="ProofLevel.Device"/>.</summary>
    public ProofLevel? Level { get; }

    public bool IsVerified => Outcome == AttestationOutcome.Verified;

    public static AttestationResult Verified(ProofLevel level) => new(AttestationOutcome.Verified, null, level);

    public static AttestationResult Failed(AttestationFailure failure) => new(AttestationOutcome.Failed, failure, null);

    public static AttestationResult Unavailable { get; } = new(AttestationOutcome.Unavailable, null, null);

    /// <summary>The §3.2 reason code (<c>hash_mismatch</c> …), or <c>unavailable</c> / <c>ok</c>.</summary>
    public string Code => Outcome switch
    {
        AttestationOutcome.Verified => "ok",
        AttestationOutcome.Unavailable => "unavailable",
        _ => AttestationCodes.Of(Failure!.Value),
    };
}

/// <summary>The fixed reason-code set (error-handling §3.2).</summary>
public static class AttestationCodes
{
    public static IReadOnlyList<string> All { get; } =
        ["hash_mismatch", "stale", "replayed", "app_unrecognized", "no_integrity", "counter", "key_unknown", "chain"];

    public static string Of(AttestationFailure failure) => failure switch
    {
        AttestationFailure.HashMismatch => "hash_mismatch",
        AttestationFailure.Stale => "stale",
        AttestationFailure.Replayed => "replayed",
        AttestationFailure.AppUnrecognized => "app_unrecognized",
        AttestationFailure.NoIntegrity => "no_integrity",
        AttestationFailure.Counter => "counter",
        AttestationFailure.KeyUnknown => "key_unknown",
        _ => "chain",
    };
}

/// <summary>
/// Play Integrity standard-request verification (backend-api §4.3 restore step 2, T-181 design note §2–§3). Single use: a token
/// that passes takes a <c>replay_guard</c> row, committed on its own.
/// </summary>
public interface IPlayIntegrityVerifier
{
    /// <param name="token">The integrity token from the app. Never logged.</param>
    /// <param name="bodyHash">The 32-byte install-bound restore <c>bodyHash</c>; the token's <c>requestHash</c> must be its base64url.</param>
    Task<AttestationResult> VerifyAsync(Sensitive<string> token, ReadOnlyMemory<byte> bodyHash, CancellationToken cancellationToken);
}

/// <summary>
/// App Attest attestation and assertion verification (in-house, T-181 design note §4–§5). Every database step runs in the
/// caller's transaction through <paramref name="keys"/>; nothing here commits.
/// </summary>
public interface IAppAttestVerifier
{
    /// <summary>
    /// Validates an <c>attestationObject</c> made over <paramref name="clientDataHash"/> and registers its key to
    /// <paramref name="installId"/> (one key per install; a key of another install is refused; the same key is kept as is).
    /// </summary>
    Task<AttestationResult> RegisterAttestationAsync(
        IAppAttestKeyStore keys,
        InstallId installId,
        ReadOnlyMemory<byte> keyId,
        ReadOnlyMemory<byte> attestationObject,
        ReadOnlyMemory<byte> clientDataHash,
        CancellationToken cancellationToken);

    /// <summary>
    /// Verifies an assertion with this install's registered key over exactly <paramref name="clientDataHash"/>, and raises the
    /// stored counter in the caller's transaction.
    /// </summary>
    Task<AttestationResult> VerifyAssertionAsync(
        IAppAttestKeyStore keys,
        InstallId installId,
        ReadOnlyMemory<byte> keyId,
        ReadOnlyMemory<byte> assertion,
        ReadOnlyMemory<byte> clientDataHash,
        CancellationToken cancellationToken);
}

/// <summary>An install's registered App Attest key (<c>app_attest_keys</c>).</summary>
public sealed record AppAttestKeyRow(byte[] KeyId, byte[] PublicKey, long SignCount);

/// <summary>Outcome of <see cref="IAppAttestKeyStore.RegisterAsync"/>.</summary>
public enum AppAttestRegistration
{
    /// <summary>Stored as this install's key (replacing an older one).</summary>
    Registered,

    /// <summary>The same key was already this install's: kept unchanged, the counter is not reset.</summary>
    AlreadyRegistered,

    /// <summary>The key belongs to another install, or the install no longer exists.</summary>
    Refused,
}

/// <summary><c>app_attest_keys</c> inside a caller-owned transaction (<c>ISeatTransaction.AppAttestKeys</c>).</summary>
public interface IAppAttestKeyStore
{
    /// <summary>This install's key, row-locked until the caller's transaction ends; <c>null</c> when it has none.</summary>
    Task<AppAttestKeyRow?> LockAsync(InstallId installId, CancellationToken cancellationToken);

    /// <summary>Registers <paramref name="keyId"/> to the install (see <see cref="AppAttestRegistration"/>).</summary>
    Task<AppAttestRegistration> RegisterAsync(
        InstallId installId,
        byte[] keyId,
        byte[] publicKey,
        bool development,
        CancellationToken cancellationToken);

    /// <summary>Sets the counter of this install's key <paramref name="keyId"/>; false when the row is gone.</summary>
    Task<bool> UpdateCounterAsync(InstallId installId, byte[] keyId, long signCount, CancellationToken cancellationToken);
}
