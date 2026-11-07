namespace Zaghlol.Infrastructure.Persistence.Entities;

// Text enums of backend-schema.md section 2. Each is stored as `text` with an `IN (...)` CHECK; the C# <-> DB strings are
// mapped explicitly in DbEnumMaps (never by ordinal, never by enum name).

/// <summary><c>installs.platform</c>.</summary>
public enum Platform
{
    Android,
    Ios,
}

/// <summary><c>accounts.provider</c>.</summary>
public enum AccountProvider
{
    Google,
    Apple,
}

/// <summary><c>purchases.store</c>.</summary>
public enum Store
{
    GooglePlay,
    AppStore,
}

/// <summary><c>purchases.plan</c>.</summary>
public enum Plan
{
    Monthly,
    Yearly,
    Lifetime,
}

/// <summary><c>purchases.state</c>.</summary>
public enum PurchaseState
{
    Pending,
    Active,
    InGrace,
    OnHold,
    Paused,
    CanceledActive,
    Expired,
    Refunded,
    Revoked,
}

/// <summary><c>purchases.environment</c>, <c>store_notifications.environment</c>.</summary>
public enum StoreEnvironment
{
    Production,
    Sandbox,
}

/// <summary><c>purchases.account_linked_by</c>.</summary>
public enum AccountLinkSource
{
    SignIn,
    Support,
}

/// <summary><c>purchase_seats.proof</c>.</summary>
public enum SeatProof
{
    Binding,
    Attested,
    Basic,
    Account,
    Support,
    Device,
}

/// <summary><c>seat_claimants.channel</c>.</summary>
public enum ClaimantChannel
{
    Restore,
    SignIn,
    Verify,
}

/// <summary><c>app_attest_keys.environment</c>.</summary>
public enum AttestEnvironment
{
    Production,
    Development,
}

/// <summary><c>replay_guard.kind</c>.</summary>
public enum ReplayGuardKind
{
    SignInGoogle,
    SignInApple,
    PlayIntegrity,
}

/// <summary><c>idempotency_records.operation_id</c> (OpenAPI operation IDs).</summary>
public enum IdempotentOperation
{
    VerifyPurchase,
    SignIn,
}

/// <summary><c>contribution_aggregates.status</c>.</summary>
public enum AggregateStatus
{
    Collecting,
    ReadyForReview,
    Promoted,
    Rejected,
}

/// <summary><c>bank_requests.channel</c>.</summary>
public enum BankRequestChannel
{
    Sms,
    Notification,
}
