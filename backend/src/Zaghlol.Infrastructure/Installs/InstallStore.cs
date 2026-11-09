using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Installs;

/// <summary>What <see cref="IInstallStore.RegisterAsync"/> did (backend-api §4.1, R3-6).</summary>
public enum RegistrationOutcome
{
    /// <summary>A new install row: answer <c>201</c>.</summary>
    Created,

    /// <summary>Same key and body within 24 h, before any authenticated call: the token hash was replaced; answer <c>201</c>.</summary>
    Reissued,

    /// <summary>Same key, different body, still in the window: <c>409 IDEMPOTENCY_KEY_REUSED</c>.</summary>
    KeyReused,

    /// <summary>Anything else (another key, after the first authenticated call, after 24 h, tombstoned): <c>409 INSTALL_EXISTS</c>.</summary>
    Exists,
}

/// <summary>An install found by its token hash.</summary>
/// <param name="InstallId">The install the token belongs to.</param>
/// <param name="RegistrationPending">True until its first authenticated call clears the registration columns.</param>
public sealed record AuthenticatedInstall(InstallId InstallId, bool RegistrationPending);

/// <summary>
/// The <c>installs</c> rows the <c>/v1</c> API writes: registration, token lookup, first-use, rotation and tombstone. Only
/// hashes are stored (backend-api §3): <c>token_hash = SHA-256(token)</c>, <c>registration_key_hash = SHA-256(key)</c>,
/// <c>registration_body_sha256 = SHA-256(body bytes)</c>. Every time comes from the caller's <see cref="TimeProvider"/>,
/// never the database clock, so tests can freeze it.
/// </summary>
public interface IInstallStore
{
    /// <summary>The R3-6 registration in one transaction; no response holding a token is ever stored.</summary>
    Task<RegistrationOutcome> RegisterAsync(
        InstallId installId,
        Platform platform,
        string appVersion,
        byte[] tokenHash,
        byte[] keyHash,
        byte[] bodySha256,
        DateTimeOffset now,
        CancellationToken cancellationToken);

    /// <summary>The live (not tombstoned) install holding this token hash, or <c>null</c>.</summary>
    Task<AuthenticatedInstall?> FindByTokenHashAsync(byte[] tokenHash, CancellationToken cancellationToken);

    /// <summary>
    /// The install's first authenticated call: clears both registration columns in one UPDATE that also requires the token
    /// hash, so it races safely with a registration replay (exactly one wins). False when the token no longer belongs to a
    /// live install (a replay replaced it, or the install was deleted).
    /// </summary>
    Task<bool> ConfirmFirstUseAsync(InstallId installId, byte[] tokenHash, CancellationToken cancellationToken);

    /// <summary>Replaces the token hash in one UPDATE (<c>rotateInstallToken</c>); false when the current token is no longer valid.</summary>
    Task<bool> RotateTokenAsync(InstallId installId, byte[] currentTokenHash, byte[] newTokenHash, CancellationToken cancellationToken);

    /// <summary>
    /// Tombstones the install (<c>deleted_at</c>, registration columns cleared) and deletes its <c>idempotency_records</c>
    /// rows in one transaction (backend-api §4.7, F13). Its tokens stop working at once.
    /// </summary>
    Task DeleteAsync(InstallId installId, DateTimeOffset now, CancellationToken cancellationToken);
}

internal sealed class InstallStore(IAppDbContextFactory contexts) : IInstallStore
{
    /// <summary>A registration replay is honoured for this long after the install was created (R3-6).</summary>
    public static readonly TimeSpan RegistrationWindow = TimeSpan.FromHours(24);

    public async Task<RegistrationOutcome> RegisterAsync(
        InstallId installId,
        Platform platform,
        string appVersion,
        byte[] tokenHash,
        byte[] keyHash,
        byte[] bodySha256,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(appVersion);
        ArgumentNullException.ThrowIfNull(tokenHash);
        ArgumentNullException.ThrowIfNull(keyHash);
        ArgumentNullException.ThrowIfNull(bodySha256);

        var id = installId.Value;
        var platformText = DbEnumMaps.Platforms.ToDb(platform);
        var cutoff = now - RegistrationWindow;

        await using var db = contexts.CreateDbContext();
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);

        // 1. A new install.
        var inserted = await db.Database.ExecuteSqlAsync(
            $"""
            INSERT INTO zaghlol.installs
                (id, token_hash, platform, app_version, first_seen_at, last_seen_at, registration_key_hash, registration_body_sha256)
            VALUES ({id}, {tokenHash}, {platformText}, {appVersion}, {now}, {now}, {keyHash}, {bodySha256})
            ON CONFLICT (id) DO NOTHING
            """,
            cancellationToken);
        if (inserted == 1)
        {
            await transaction.CommitAsync(cancellationToken);
            return RegistrationOutcome.Created;
        }

        // 2. A replay of the same registration: one atomic UPDATE replaces the unused token's hash.
        var reissued = await db.Installs
            .Where(i => i.Id == id
                && i.DeletedAt == null
                && i.RegistrationKeyHash == keyHash
                && i.RegistrationBodySha256 == bodySha256
                && i.FirstSeenAt > cutoff)
            .ExecuteUpdateAsync(s => s.SetProperty(i => i.TokenHash, tokenHash), cancellationToken);
        if (reissued == 1)
        {
            await transaction.CommitAsync(cancellationToken);
            return RegistrationOutcome.Reissued;
        }

        // 3. Neither: tell "same key, other body" apart from everything else. No token either way.
        var row = await db.Installs
            .AsNoTracking()
            .Where(i => i.Id == id)
            .Select(i => new { i.DeletedAt, i.RegistrationKeyHash, i.FirstSeenAt })
            .SingleOrDefaultAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);

        var sameKey = row is { DeletedAt: null, RegistrationKeyHash: { } stored }
            && row.FirstSeenAt > cutoff
            && CryptographicOperations.FixedTimeEquals(stored, keyHash);
        return sameKey ? RegistrationOutcome.KeyReused : RegistrationOutcome.Exists;
    }

    public async Task<AuthenticatedInstall?> FindByTokenHashAsync(byte[] tokenHash, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(tokenHash);

        await using var db = contexts.CreateDbContext();
        var row = await db.Installs
            .AsNoTracking()
            .Where(i => i.TokenHash == tokenHash && i.DeletedAt == null)
            .Select(i => new { i.Id, Pending = i.RegistrationKeyHash != null })
            .SingleOrDefaultAsync(cancellationToken);
        return row is null ? null : new AuthenticatedInstall(InstallId.FromGuid(row.Id), row.Pending);
    }

    public async Task<bool> ConfirmFirstUseAsync(InstallId installId, byte[] tokenHash, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(tokenHash);

        var id = installId.Value;
        await using var db = contexts.CreateDbContext();
        var updated = await db.Installs
            .Where(i => i.Id == id && i.TokenHash == tokenHash && i.DeletedAt == null)
            .ExecuteUpdateAsync(
                s => s
                    .SetProperty(i => i.RegistrationKeyHash, (byte[]?)null)
                    .SetProperty(i => i.RegistrationBodySha256, (byte[]?)null),
                cancellationToken);
        return updated == 1;
    }

    public async Task<bool> RotateTokenAsync(InstallId installId, byte[] currentTokenHash, byte[] newTokenHash, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(currentTokenHash);
        ArgumentNullException.ThrowIfNull(newTokenHash);

        var id = installId.Value;
        await using var db = contexts.CreateDbContext();
        var updated = await db.Installs
            .Where(i => i.Id == id && i.TokenHash == currentTokenHash && i.DeletedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(i => i.TokenHash, newTokenHash), cancellationToken);
        return updated == 1;
    }

    public async Task DeleteAsync(InstallId installId, DateTimeOffset now, CancellationToken cancellationToken)
    {
        var id = installId.Value;
        await using var db = contexts.CreateDbContext();
        await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
        await db.Installs
            .Where(i => i.Id == id && i.DeletedAt == null)
            .ExecuteUpdateAsync(
                s => s
                    .SetProperty(i => i.DeletedAt, (DateTimeOffset?)now)
                    .SetProperty(i => i.RegistrationKeyHash, (byte[]?)null)
                    .SetProperty(i => i.RegistrationBodySha256, (byte[]?)null),
                cancellationToken);
        await db.IdempotencyRecords.Where(r => r.InstallId == id).ExecuteDeleteAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
    }
}
