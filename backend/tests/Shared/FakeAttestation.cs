using System.Collections.Concurrent;
using Zaghlol.Application.Purchases.Attestation;
using Zaghlol.Domain;

namespace Zaghlol.Testing;

/// <summary>
/// Deterministic <see cref="IPlayIntegrityVerifier"/> for downstream tests (T-185, T-135): returns <see cref="Result"/> (default
/// verified, <c>device</c>) unless <see cref="ExpectedBodyHash"/> is set and differs (then <c>hash_mismatch</c>). Records calls,
/// never the token.
/// </summary>
public sealed class FakePlayIntegrityVerifier : IPlayIntegrityVerifier
{
    public AttestationResult Result { get; set; } = AttestationResult.Verified(ProofLevel.Device);

    public byte[]? ExpectedBodyHash { get; set; }

    public int Calls { get; private set; }

    public Task<AttestationResult> VerifyAsync(Sensitive<string> token, ReadOnlyMemory<byte> bodyHash, CancellationToken cancellationToken)
    {
        Calls++;
        if (ExpectedBodyHash is { } expected && !bodyHash.Span.SequenceEqual(expected))
        {
            return Task.FromResult(AttestationResult.Failed(AttestationFailure.HashMismatch));
        }

        return Task.FromResult(Result);
    }
}

/// <summary>
/// Deterministic <see cref="IAppAttestVerifier"/>: fixed outcomes for attestation and assertion (default verified). When
/// <see cref="ExpectedClientDataHash"/> is set, a different hash fails with <c>hash_mismatch</c>. On a verified assertion it
/// raises the counter through the given store, so a caller's rollback is observable as with the real verifier.
/// </summary>
public sealed class FakeAppAttestVerifier : IAppAttestVerifier
{
    public AttestationResult AttestationResult { get; set; } = AttestationResult.Verified(ProofLevel.Device);

    public AttestationResult AssertionResult { get; set; } = AttestationResult.Verified(ProofLevel.Device);

    public byte[]? ExpectedClientDataHash { get; set; }

    public int Attestations { get; private set; }

    public int Assertions { get; private set; }

    public async Task<AttestationResult> RegisterAttestationAsync(
        IAppAttestKeyStore keys,
        InstallId installId,
        ReadOnlyMemory<byte> keyId,
        ReadOnlyMemory<byte> attestationObject,
        ReadOnlyMemory<byte> clientDataHash,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(keys);
        Attestations++;
        if (ExpectedClientDataHash is { } expected && !clientDataHash.Span.SequenceEqual(expected))
        {
            return AttestationResult.Failed(AttestationFailure.HashMismatch);
        }

        if (!AttestationResult.IsVerified)
        {
            return AttestationResult;
        }

        var registered = await keys.RegisterAsync(installId, keyId.ToArray(), new byte[65], development: false, cancellationToken);
        return registered == AppAttestRegistration.Refused ? AttestationResult.Failed(AttestationFailure.KeyUnknown) : AttestationResult;
    }

    public async Task<AttestationResult> VerifyAssertionAsync(
        IAppAttestKeyStore keys,
        InstallId installId,
        ReadOnlyMemory<byte> keyId,
        ReadOnlyMemory<byte> assertion,
        ReadOnlyMemory<byte> clientDataHash,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(keys);
        Assertions++;
        if (ExpectedClientDataHash is { } expected && !clientDataHash.Span.SequenceEqual(expected))
        {
            return AttestationResult.Failed(AttestationFailure.HashMismatch);
        }

        if (!AssertionResult.IsVerified)
        {
            return AssertionResult;
        }

        if (await keys.LockAsync(installId, cancellationToken) is { } row)
        {
            await keys.UpdateCounterAsync(installId, row.KeyId, row.SignCount + 1, cancellationToken);
        }

        return AssertionResult;
    }
}

/// <summary>An in-memory <see cref="IAppAttestKeyStore"/> with the same registration rules as the Npgsql one (no transactions).</summary>
public sealed class InMemoryAppAttestKeyStore : IAppAttestKeyStore
{
    private readonly ConcurrentDictionary<Guid, AppAttestKeyRow> rows = new();

    public IReadOnlyDictionary<Guid, AppAttestKeyRow> Rows => rows;

    public HashSet<Guid> Installs { get; } = [];

    public Task<AppAttestKeyRow?> LockAsync(InstallId installId, CancellationToken cancellationToken) =>
        Task.FromResult(rows.TryGetValue(installId.Value, out var row) ? row : null);

    public Task<AppAttestRegistration> RegisterAsync(InstallId installId, byte[] keyId, byte[] publicKey, bool development, CancellationToken cancellationToken)
    {
        if (Installs.Count > 0 && !Installs.Contains(installId.Value))
        {
            return Task.FromResult(AppAttestRegistration.Refused);
        }

        foreach (var (install, row) in rows)
        {
            if (row.KeyId.AsSpan().SequenceEqual(keyId))
            {
                return Task.FromResult(install == installId.Value ? AppAttestRegistration.AlreadyRegistered : AppAttestRegistration.Refused);
            }
        }

        rows[installId.Value] = new AppAttestKeyRow(keyId, publicKey, 0);
        return Task.FromResult(AppAttestRegistration.Registered);
    }

    public Task<bool> UpdateCounterAsync(InstallId installId, byte[] keyId, long signCount, CancellationToken cancellationToken)
    {
        if (rows.TryGetValue(installId.Value, out var row) && row.KeyId.AsSpan().SequenceEqual(keyId))
        {
            rows[installId.Value] = row with { SignCount = signCount };
            return Task.FromResult(true);
        }

        return Task.FromResult(false);
    }
}
