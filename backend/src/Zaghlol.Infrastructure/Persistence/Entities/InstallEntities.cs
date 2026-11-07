namespace Zaghlol.Infrastructure.Persistence.Entities;

// backend-schema.md section 2, "Installs" and "Optional accounts". Hash and ciphertext columns are plain bytes: they are
// computed by the owning handler (SHA256.HashData, IKeyedHasher, IEnvelopeCipher), never by the database or a converter.

/// <summary><c>installs</c> (FR-BE-01). No OS version (FU-013), no device identifier.</summary>
public sealed class Install
{
    public Guid Id { get; set; }

    /// <summary>SHA-256 of the install token.</summary>
    public required byte[] TokenHash { get; set; }

    public Platform Platform { get; set; }

    public required string AppVersion { get; set; }

    public int CatalogVersion { get; set; }

    public DateTimeOffset FirstSeenAt { get; set; }

    public DateTimeOffset LastSeenAt { get; set; }

    public DateTimeOffset? DeletedAt { get; set; }

    /// <summary>SHA-256(Idempotency-Key) of the registration (R3-6).</summary>
    public byte[]? RegistrationKeyHash { get; set; }

    public byte[]? RegistrationBodySha256 { get; set; }

    /// <summary>HMAC-SHA256(K_seat, ...) of the registered seat key (R4-1(1)); set once, never replaced.</summary>
    public byte[]? SeatKeyHash { get; set; }

    /// <summary>Only false -> true, and only by an App Attest-covered request (R5-2).</summary>
    public bool SeatKeyTrusted { get; set; }
}

/// <summary><c>accounts</c> (FR-ACCT, FR-BE-09).</summary>
public sealed class Account
{
    public Guid Id { get; set; }

    public AccountProvider Provider { get; set; }

    public required string ProviderSubject { get; set; }

    public string? Email { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset? LastSignInAt { get; set; }

    /// <summary>Envelope-encrypted by <c>IEnvelopeCipher</c> (T-123).</summary>
    public byte[]? AppleRefreshTokenEnc { get; set; }
}

/// <summary><c>account_installs</c>.</summary>
public sealed class AccountInstall
{
    public Guid AccountId { get; set; }

    public Guid InstallId { get; set; }

    public DateTimeOffset LinkedAt { get; set; }
}
