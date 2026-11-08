namespace Zaghlol.Infrastructure.Persistence.Entities;

/// <summary><c>replay_guard</c>: single-use proofs, hashes only, until <see cref="ExpiresAt"/>.</summary>
public sealed class ReplayGuardEntry
{
    /// <summary>SHA-256 of the nonce claim or of the Play Integrity token.</summary>
    public required byte[] KeyHash { get; set; }

    public ReplayGuardKind Kind { get; set; }

    public DateTimeOffset ExpiresAt { get; set; }
}

/// <summary><c>idempotency_records</c> (R2-8, R3-6): verify and sign-in only.</summary>
public sealed class IdempotencyRecord
{
    /// <summary>From the install token; deliberately no FK (rows are deleted with the install by the API).</summary>
    public Guid InstallId { get; set; }

    public IdempotentOperation OperationId { get; set; }

    /// <summary>The 26-character ULID from the Idempotency-Key header.</summary>
    public required string IdempotencyKey { get; set; }

    public required byte[] BodySha256 { get; set; }

    public int Status { get; set; }

    /// <summary>Envelope-encrypted by <c>IEnvelopeCipher</c> (T-123); holds tokens.</summary>
    public required byte[] ResponseBodyEnc { get; set; }

    public Guid? AccountId { get; set; }

    public DateTimeOffset ExpiresAt { get; set; }
}
