using System.Collections.Concurrent;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Api.Tests.Purchases;

/// <summary>
/// A grant step that always issues an entitlement for the installs a test opted in (others get <see cref="VerifyGrantResult.None"/>,
/// like <see cref="NullVerifyGrant"/>), and records every call. It proves the endpoint itself withholds Gold from non-active
/// purchases (T-130 review finding 1): with this fake, only the endpoint's gate stands between a pending purchase and a token.
/// </summary>
public sealed class GrantingVerifyGrant : IVerifyGrant
{
    public const string Token = "test-entitlement-token";

    private readonly ConcurrentDictionary<Guid, byte> granting = new();

    public ConcurrentQueue<(Guid Install, VerifyStatus Status)> Calls { get; } = new();

    /// <summary>Every verification result the grant step saw (T-133: <c>IsNewPayment</c> after a notification-first purchase).</summary>
    public ConcurrentQueue<StoreVerificationResult> Results { get; } = new();

    public void AlwaysGrantFor(string installId) => granting[Guid.Parse(installId)] = 0;

    public Task<VerifyGrantResult> ComposeAsync(StoreVerificationResult verification, VerifyContext context, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(verification);
        ArgumentNullException.ThrowIfNull(context);

        Calls.Enqueue((context.Install.Value, verification.Status));
        Results.Enqueue(verification);
        return Task.FromResult(granting.ContainsKey(context.Install.Value)
            ? new VerifyGrantResult(new Sensitive<string>(Token), false, false, null)
            : VerifyGrantResult.None);
    }
}
