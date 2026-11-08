using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Persistence;

/// <summary>
/// The text value of every enum member, exactly as listed in the CHECK constraints of backend-schema.md section 2.
/// A test asserts that each map's values equal the values in its column's CHECK.
/// </summary>
public static class DbEnumMaps
{
    public static EnumMap<Platform> Platforms { get; } = new(
        (Platform.Android, "android"),
        (Platform.Ios, "ios"));

    public static EnumMap<AccountProvider> AccountProviders { get; } = new(
        (AccountProvider.Google, "google"),
        (AccountProvider.Apple, "apple"));

    public static EnumMap<Store> Stores { get; } = new(
        (Store.GooglePlay, "google_play"),
        (Store.AppStore, "app_store"));

    public static EnumMap<Plan> Plans { get; } = new(
        (Plan.Monthly, "monthly"),
        (Plan.Yearly, "yearly"),
        (Plan.Lifetime, "lifetime"));

    public static EnumMap<PurchaseState> PurchaseStates { get; } = new(
        (PurchaseState.Pending, "pending"),
        (PurchaseState.Active, "active"),
        (PurchaseState.InGrace, "in_grace"),
        (PurchaseState.OnHold, "on_hold"),
        (PurchaseState.Paused, "paused"),
        (PurchaseState.CanceledActive, "canceled_active"),
        (PurchaseState.Expired, "expired"),
        (PurchaseState.Refunded, "refunded"),
        (PurchaseState.Revoked, "revoked"));

    public static EnumMap<StoreEnvironment> StoreEnvironments { get; } = new(
        (StoreEnvironment.Production, "production"),
        (StoreEnvironment.Sandbox, "sandbox"));

    public static EnumMap<AccountLinkSource> AccountLinkSources { get; } = new(
        (AccountLinkSource.SignIn, "signin"),
        (AccountLinkSource.Support, "support"));

    public static EnumMap<SeatProof> SeatProofs { get; } = new(
        (SeatProof.Binding, "binding"),
        (SeatProof.Attested, "attested"),
        (SeatProof.Basic, "basic"),
        (SeatProof.Account, "account"),
        (SeatProof.Support, "support"),
        (SeatProof.Device, "device"));

    public static EnumMap<ClaimantChannel> ClaimantChannels { get; } = new(
        (ClaimantChannel.Restore, "restore"),
        (ClaimantChannel.SignIn, "signin"),
        (ClaimantChannel.Verify, "verify"));

    public static EnumMap<AttestEnvironment> AttestEnvironments { get; } = new(
        (AttestEnvironment.Production, "production"),
        (AttestEnvironment.Development, "development"));

    public static EnumMap<ReplayGuardKind> ReplayGuardKinds { get; } = new(
        (ReplayGuardKind.SignInGoogle, "signin_google"),
        (ReplayGuardKind.SignInApple, "signin_apple"),
        (ReplayGuardKind.PlayIntegrity, "play_integrity"));

    public static EnumMap<IdempotentOperation> IdempotentOperations { get; } = new(
        (IdempotentOperation.VerifyPurchase, "verifyPurchase"),
        (IdempotentOperation.SignIn, "signIn"));

    public static EnumMap<AggregateStatus> AggregateStatuses { get; } = new(
        (AggregateStatus.Collecting, "collecting"),
        (AggregateStatus.ReadyForReview, "ready_for_review"),
        (AggregateStatus.Promoted, "promoted"),
        (AggregateStatus.Rejected, "rejected"));

    public static EnumMap<BankRequestChannel> BankRequestChannels { get; } = new(
        (BankRequestChannel.Sms, "sms"),
        (BankRequestChannel.Notification, "notification"));
}
