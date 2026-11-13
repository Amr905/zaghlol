using Zaghlol.Application.Entitlements;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Seats;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Entitlements;

internal static class EntitlementTestKit
{
    public static readonly InstallId Caller = InstallId.Parse("00000000-0000-4000-8000-000000000001");
    public static readonly DateTimeOffset Now = new(2026, 11, 13, 9, 30, 15, 400, TimeSpan.Zero);
    public static readonly Guid Account = Guid.Parse("00000000-0000-4000-8000-0000000000aa");

    public static HeldPurchase Held(
        GoldPlan plan = GoldPlan.Yearly,
        StoredPurchaseState state = StoredPurchaseState.Active,
        DateTimeOffset? expiresAt = null,
        Guid? account = null,
        SeatProofKind proof = SeatProofKind.Binding,
        DateTimeOffset? nextMoveAt = null,
        PurchaseStore store = PurchaseStore.GooglePlay) =>
        new(
            Guid.NewGuid(),
            store,
            "zaghlol_gold_" + EntitlementWire.Plan(plan),
            plan,
            state,
            plan == GoldPlan.Lifetime ? null : expiresAt ?? Now.AddDays(20),
            account,
            proof,
            nextMoveAt);

    public static EntitlementFacts Facts(params HeldPurchase[] held) => new(held, []);

    public static EntitlementClaims Build(EntitlementFacts facts, Guid? account = null, DateTimeOffset? now = null) =>
        EntitlementRules.Build(Caller, facts, account, now ?? Now);
}

internal sealed class ManualClock(DateTimeOffset now) : TimeProvider
{
    public DateTimeOffset Now { get; set; } = now;

    public override DateTimeOffset GetUtcNow() => Now;
}

internal sealed class FakeEntitlementSigner : IEntitlementSigner
{
    public List<EntitlementClaims> Entitlements { get; } = [];

    public List<AccountTokenClaims> AccountTokens { get; } = [];

    public Task<string> SignEntitlementAsync(EntitlementClaims claims, CancellationToken cancellationToken)
    {
        Entitlements.Add(claims);
        return Task.FromResult("ent." + Entitlements.Count);
    }

    public Task<string> SignAccountTokenAsync(AccountTokenClaims claims, CancellationToken cancellationToken)
    {
        AccountTokens.Add(claims);
        return Task.FromResult("acct." + AccountTokens.Count);
    }
}

internal sealed class FakeAccountValidator(ValidatedAccountToken? result) : IAccountTokenValidator
{
    public Task<ValidatedAccountToken?> ValidateAsync(Sensitive<string>? token, InstallId caller, DateTimeOffset now, CancellationToken cancellationToken) =>
        Task.FromResult(token is null ? null : result);
}

/// <summary>The notice bookkeeping with the same semantics as the SQL (R5-7), over one purchase.</summary>
internal sealed class FakeEntitlementStore : IEntitlementStore
{
    public EntitlementFacts Facts { get; set; } = EntitlementFacts.Empty;

    public bool Pending { get; set; }

    public DateTimeOffset? NoticeIat { get; set; }

    public bool Changed { get; set; }

    public int Reads { get; private set; }

    public Task<EntitlementFacts> ReadFactsAsync(InstallId install, DateTimeOffset now, CancellationToken cancellationToken)
    {
        Reads++;
        return Task.FromResult(Facts);
    }

    public Task<bool> SupportNoticePendingAsync(InstallId install, CancellationToken cancellationToken) => Task.FromResult(Pending);

    public Task RecordSupportNoticeIatAsync(InstallId install, DateTimeOffset iat, CancellationToken cancellationToken)
    {
        if (Pending && (NoticeIat is null || NoticeIat < iat))
        {
            NoticeIat = iat;
        }

        return Task.CompletedTask;
    }

    public Task ClearDeliveredSupportNoticeAsync(InstallId install, DateTimeOffset issuedAt, CancellationToken cancellationToken)
    {
        if (Pending && NoticeIat is { } iat && iat <= issuedAt)
        {
            Pending = false;
        }

        return Task.CompletedTask;
    }

    public Task<bool> ChangedSinceAsync(InstallId install, DateTimeOffset since, CancellationToken cancellationToken) => Task.FromResult(Changed);
}
