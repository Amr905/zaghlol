using Zaghlol.Application.Accounts;
using Zaghlol.Application.Seats;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Accounts;

internal sealed class FakeAccountStore : IAccountStore
{
    public string? Platform { get; set; } = "android";

    public List<(Guid Account, Guid Install)> Unlinked { get; } = [];

    public AccountForDelete? ForDelete { get; set; }

    public List<Guid> Deleted { get; } = [];

    public Task<string?> ReadInstallPlatformAsync(Guid installId, CancellationToken cancellationToken) => Task.FromResult(Platform);

    public Task UnlinkInstallAsync(Guid accountId, Guid installId, CancellationToken cancellationToken)
    {
        Unlinked.Add((accountId, installId));
        return Task.CompletedTask;
    }

    public Task<AccountForDelete?> ReadForDeleteAsync(Guid accountId, CancellationToken cancellationToken) => Task.FromResult(ForDelete);

    public Task DeleteAccountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        Deleted.Add(accountId);
        return Task.CompletedTask;
    }
}

internal sealed class ScriptedIdTokenVerifier(IdTokenResult result) : IIdTokenVerifier
{
    public int Calls { get; private set; }

    public ValueTask<IdTokenResult> VerifyAsync(AccountProvider provider, Sensitive<string> idToken, CancellationToken cancellationToken)
    {
        Calls++;
        return ValueTask.FromResult(result);
    }
}

internal sealed class SetReplayGuard : IIdTokenReplayGuard
{
    public HashSet<string> Used { get; } = [];

    public Task<bool> TryUseAsync(AccountProvider provider, ReadOnlyMemory<byte> nonceClaimHash, DateTimeOffset expiresAt, CancellationToken cancellationToken) =>
        Task.FromResult(Used.Add(Convert.ToHexString(nonceClaimHash.Span)));
}

internal sealed class RecordingApple : IAppleAccountClient
{
    public int Exchanges { get; private set; }

    public List<AppleRefreshToken> Revoked { get; } = [];

    public AppleRevokeOutcome Outcome { get; set; } = AppleRevokeOutcome.Revoked;

    public Task<AppleRefreshToken?> ExchangeCodeAsync(Sensitive<string> code, string clientId, string expectedSubject, CancellationToken cancellationToken)
    {
        Exchanges++;
        return Task.FromResult<AppleRefreshToken?>(new AppleRefreshToken(clientId, new Sensitive<string>("rt")));
    }

    public Task<AppleRevokeOutcome> RevokeAsync(AppleRefreshToken token, CancellationToken cancellationToken)
    {
        if (Outcome == AppleRevokeOutcome.Revoked)
        {
            Revoked.Add(token);
        }

        return Task.FromResult(Outcome);
    }
}

internal sealed class IdentityVault : IAppleTokenVault
{
    public Task<byte[]> SealAsync(string subject, AppleRefreshToken token, CancellationToken cancellationToken) =>
        Task.FromResult(System.Text.Encoding.UTF8.GetBytes(token.ClientId + "\n" + token.Token.Reveal()));

    public Task<AppleRefreshToken?> OpenAsync(string subject, ReadOnlyMemory<byte> sealedToken, CancellationToken cancellationToken)
    {
        var text = System.Text.Encoding.UTF8.GetString(sealedToken.Span).Split('\n');
        return Task.FromResult<AppleRefreshToken?>(new AppleRefreshToken(text[0], new Sensitive<string>(text[1])));
    }
}

/// <summary>Opening a transaction is itself the failure: the refusals under test must happen before any database work.</summary>
internal sealed class NoTransactions : IAccountTransactionFactory
{
    public int Begun { get; private set; }

    public Task<IAccountTransaction> BeginAsync(CancellationToken cancellationToken)
    {
        Begun++;
        throw new InvalidOperationException("No transaction may be opened.");
    }
}

internal sealed class NullSeatTelemetry : ISeatTelemetry
{
    public void Changed(string channel, string kind)
    {
    }

    public void RebindOverCap(Guid purchaseId)
    {
    }
}
