using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>Where an Apple JWS came from, which decides its validation time (T-131 design note §2 step 6).</summary>
public enum JwsSource
{
    /// <summary>The app's StoreKit copy: validated at its own <c>signedDate</c> (bounded by now + 5 min).</summary>
    App,

    /// <summary>Freshly signed by Apple for one of our App Store Server API calls: validated at now.</summary>
    Api,

    /// <summary>
    /// An App Store Server Notification V2 (the outer payload and its nested JWSs, T-134 design note §1 step 3): validated at its own
    /// <c>signedDate</c> (bounded by now + 5 min), like <see cref="App"/>, because Apple's retries and history entries keep their
    /// original signature. Safe because a notification is only a trigger: the worker re-reads the state from Apple's API.
    /// </summary>
    Notification,
}

/// <summary>Why an Apple JWS was refused (<c>zaghlol.purchase.jws{outcome}</c>).</summary>
public enum AppleJwsFailure
{
    /// <summary>Size, segments, base64url, JSON or duplicate members.</summary>
    Malformed,

    /// <summary><c>alg</c> isn't exactly ES256, or <c>jku</c>, <c>jwk</c>, <c>x5u</c>, <c>kid</c> or <c>crit</c> is present.</summary>
    Alg,

    /// <summary>The <c>x5c</c> chain doesn't build offline to the pinned root with exactly three certificates.</summary>
    Chain,

    /// <summary>The leaf or intermediate lacks Apple's marker extension, or the leaf key isn't EC P-256.</summary>
    Oid,

    /// <summary>The ES256 signature (64-byte IEEE P1363 only) doesn't verify with the leaf key.</summary>
    Signature,

    /// <summary>The payload's fields can't be read, its <c>signedDate</c> is missing or in the future, or (verify) Apple's copy contradicts the app's.</summary>
    Payload,
}

/// <summary>An Apple JWS failed verification. The message is a constant: the JWS and its contents are never in it.</summary>
public sealed class AppleJwsException : SafeException
{
    public const string DefaultMessage = "An Apple signed payload failed verification.";

    public AppleJwsException()
        : base(DefaultMessage)
    {
    }

    public AppleJwsException(AppleJwsFailure reason)
        : base(DefaultMessage)
    {
        Reason = reason;
    }

    public AppleJwsException(string message)
        : base(message)
    {
    }

    public AppleJwsException(string message, Exception innerException)
        : base(message, innerException)
    {
    }

    public AppleJwsFailure Reason { get; } = AppleJwsFailure.Malformed;
}

/// <summary>The signed <c>environment</c>; <see cref="Unknown"/> for <c>Xcode</c>, <c>LocalTesting</c> or anything Apple adds.</summary>
public enum AppleEnvironment
{
    Unknown,
    Production,
    Sandbox,
}

/// <summary>The payload <c>type</c>; only the two Gold kinds are named.</summary>
public enum AppleProductType
{
    Other,
    AutoRenewable,
    NonConsumable,
}

/// <summary><c>inAppOwnershipType</c>: only <see cref="Purchased"/> may pass the verify binding (PO question 5).</summary>
public enum AppleOwnershipType
{
    Other,
    Purchased,
    FamilyShared,
}

/// <summary><c>transactionReason</c>: only <see cref="Purchase"/> can be a new payment.</summary>
public enum AppleTransactionReason
{
    Other,
    Purchase,
    Renewal,
}

/// <summary>
/// The read fields of a verified <c>JWSTransactionDecodedPayload</c> (T-131 §3 step 2). Identifiers are <see cref="Sensitive{T}"/>:
/// never logged.
/// </summary>
public sealed record AppleTransaction(
    string? BundleId,
    AppleEnvironment Environment,
    string? ProductId,
    AppleProductType Type,
    Sensitive<string>? TransactionId,
    Sensitive<string>? OriginalTransactionId,
    Sensitive<string>? AppAccountToken,
    AppleOwnershipType OwnershipType,
    AppleTransactionReason Reason,
    DateTimeOffset? PurchaseDate,
    DateTimeOffset? ExpiresDate,
    DateTimeOffset? RevocationDate,
    int? RevocationReason,
    DateTimeOffset SignedDate);

/// <summary>The read fields of a verified <c>JWSRenewalInfoDecodedPayload</c>.</summary>
public sealed record AppleRenewalInfo(
    Sensitive<string>? OriginalTransactionId,
    AppleEnvironment Environment,
    int? AutoRenewStatus,
    DateTimeOffset? GracePeriodExpiresDate);

/// <summary>
/// The <c>data</c> object of a verified <c>responseBodyV2DecodedPayload</c>: the read fields only (T-134 design note §1 step 4).
/// The two nested JWSs are still unverified here.
/// </summary>
/// <param name="Environment">The raw signed value; the ingest maps it (anything but <c>Production</c>/<c>Sandbox</c> is refused).</param>
public sealed record AppleNotificationData(
    string? BundleId,
    string? Environment,
    int? Status,
    Sensitive<string>? SignedTransactionInfo,
    Sensitive<string>? SignedRenewalInfo);

/// <summary>
/// The read fields of a verified <c>responseBodyV2DecodedPayload</c> (T-134 design note §1 step 4). Nothing else of the payload is
/// read: not <c>appData</c>, <c>summary</c>, <c>externalPurchaseToken</c> or <c>unclaimInfo</c>. The values are still to be
/// validated by the ingest (version, UUID, type pattern, freshness, bundle, environment).
/// </summary>
/// <param name="Data"><c>null</c> when the payload has no <c>data</c> object (no Gold event).</param>
public sealed record AppleNotification(
    string? NotificationType,
    string? Subtype,
    string? NotificationUuid,
    string? Version,
    DateTimeOffset SignedDate,
    AppleNotificationData? Data);

/// <summary>
/// The in-house Apple JWS verifier (T-131 design note §2, T-134 §1): pure, synchronous, no I/O. The key comes only from
/// <c>x5c[0]</c>, whose chain must build offline to the pinned Apple Root CA G3. Every failure is an <see cref="AppleJwsException"/>.
/// </summary>
public interface IAppleJwsVerifier
{
    AppleTransaction VerifyTransaction(Sensitive<string> jws, JwsSource source, DateTimeOffset now);

    /// <summary>
    /// Renewal info from Apple's API (<see cref="JwsSource.Api"/>, validated at <paramref name="now"/>) or nested in a notification
    /// (<see cref="JwsSource.Notification"/>, validated at its own <c>signedDate</c>). <see cref="JwsSource.App"/> is refused.
    /// </summary>
    AppleRenewalInfo VerifyRenewalInfo(Sensitive<string> jws, JwsSource source, DateTimeOffset now);

    /// <summary>
    /// The outer <c>signedPayload</c> of an App Store Server Notification V2: at most 65 536 characters, validated at its own
    /// <c>signedDate</c> (at most now + 5 min). The nested JWSs are not verified here.
    /// </summary>
    AppleNotification VerifyNotification(Sensitive<string> signedPayload, DateTimeOffset now);
}

/// <summary>The App Store Server API calls the server makes.</summary>
public enum AppStoreApi
{
    TransactionInfo,
    SubscriptionStatuses,
    OrderLookup,

    /// <summary><c>Get Notification History</c> (T-134 reconciliation).</summary>
    NotificationHistory,
}

/// <summary>How an App Store Server API call ended (<c>zaghlol.store.call{outcome}</c>, the T-130 set).</summary>
public enum AppStoreCallOutcome
{
    Ok,

    /// <summary>A 4xx other than 401 and 429. Only <see cref="AppStoreApiException.IsInvalidTransactionId"/> and a fresh
    /// <see cref="AppStoreApiException.IsTransactionNotFound"/> mean anything about the purchase.</summary>
    ClientError,
    AuthError,
    RateLimited,
    ServerError,
    Timeout,
    CircuitOpen,
    BudgetDenied,
}

/// <summary>
/// An App Store Server API call that did not return a usable answer. The message is a constant: the URL, the transaction or
/// order ID and the response body are never in it (D-57).
/// </summary>
public sealed class AppStoreApiException : SafeException
{
    public const string DefaultMessage = "An App Store Server API call failed.";

    /// <summary>Apple's <c>InvalidTransactionIdError</c> (400).</summary>
    public const int InvalidTransactionId = 4000006;

    /// <summary>Apple's <c>TransactionIdNotFoundError</c> (404).</summary>
    public const int TransactionIdNotFound = 4040010;

    public AppStoreApiException()
        : base(DefaultMessage)
    {
    }

    public AppStoreApiException(AppStoreApi api, AppStoreCallOutcome outcome, int? httpStatus = null, int? errorCode = null, TimeSpan? retryAfter = null)
        : base(DefaultMessage)
    {
        Api = api;
        Outcome = outcome;
        HttpStatus = httpStatus;
        ErrorCode = errorCode;
        RetryAfter = retryAfter;
    }

    public AppStoreApiException(string message)
        : base(message)
    {
    }

    public AppStoreApiException(string message, Exception innerException)
        : base(message, innerException)
    {
    }

    public AppStoreApi Api { get; }

    public AppStoreCallOutcome Outcome { get; }

    public int? HttpStatus { get; }

    /// <summary>Apple's numeric <c>errorCode</c> from the error body, when it had one.</summary>
    public int? ErrorCode { get; }

    public TimeSpan? RetryAfter { get; }

    public bool IsInvalidTransactionId => HttpStatus == 400 && ErrorCode == InvalidTransactionId;

    public bool IsTransactionNotFound => HttpStatus == 404 && ErrorCode == TransactionIdNotFound;
}

/// <summary>One <c>lastTransactions[]</c> item of <c>Get All Subscription Statuses</c> (signed parts still unverified).</summary>
public sealed record AppleLastTransaction(
    int? Status,
    Sensitive<string>? OriginalTransactionId,
    Sensitive<string>? SignedTransactionInfo,
    Sensitive<string>? SignedRenewalInfo);

/// <summary><c>Look Up Order ID</c>: <c>status</c> and the signed transactions (still unverified).</summary>
public sealed record AppleOrderLookupResult(int? Status, IReadOnlyList<Sensitive<string>> SignedTransactions);

/// <summary>One page of <c>Get Notification History</c>: the <c>signedPayload</c>s (still unverified), and where to continue.</summary>
/// <param name="PaginationToken">Apple's opaque continuation token; never logged.</param>
public sealed record AppleNotificationHistoryPage(IReadOnlyList<Sensitive<string>> SignedPayloads, bool HasMore, Sensitive<string>? PaginationToken);

/// <summary>
/// The App Store Server API (T-131 design note §6). The environment picks the base URL (production or sandbox; never a fallback
/// from one to the other). Each HTTP attempt, retries included, draws on the Apple call budget for <paramref name="lane"/>.
/// Everything but a usable 2xx throws <see cref="AppStoreApiException"/>.
/// </summary>
public interface IAppStoreServerApi
{
    /// <summary><c>GET /inApps/v1/transactions/{transactionId}</c>: the <c>signedTransactionInfo</c>.</summary>
    Task<Sensitive<string>> GetTransactionInfoAsync(PurchaseEnvironment environment, Sensitive<string> transactionId, StoreLane lane, CancellationToken cancellationToken);

    /// <summary><c>GET /inApps/v1/subscriptions/{transactionId}</c> (no status filter): every <c>lastTransactions[]</c> item.</summary>
    Task<IReadOnlyList<AppleLastTransaction>> GetAllSubscriptionStatusesAsync(PurchaseEnvironment environment, Sensitive<string> transactionId, StoreLane lane, CancellationToken cancellationToken);

    /// <summary><c>GET /inApps/v1/lookup/{orderId}</c> on production (the endpoint doesn't exist in sandbox).</summary>
    Task<AppleOrderLookupResult> LookUpOrderIdAsync(Sensitive<string> orderId, StoreLane lane, CancellationToken cancellationToken);

    /// <summary>
    /// <c>POST /inApps/v1/notifications/history</c> with <c>{startDate, endDate, onlyFailures: true}</c>, continued with
    /// <paramref name="paginationToken"/> when given (T-134 design note §4).
    /// </summary>
    Task<AppleNotificationHistoryPage> GetNotificationHistoryAsync(
        PurchaseEnvironment environment,
        DateTimeOffset startDate,
        DateTimeOffset endDate,
        Sensitive<string>? paginationToken,
        StoreLane lane,
        CancellationToken cancellationToken);
}

/// <summary>A per-install limit on verify calls that reach Apple (T-131 §6, FU-077 M-2: 10 an hour by default).</summary>
public interface IAppleVerifyLimiter
{
    /// <summary>False when this install has used up its verify allowance; the caller answers <c>503</c> without any Apple call.</summary>
    bool TryAcquire(InstallId install);
}

/// <summary>A Gold product's App Store kind.</summary>
public sealed record AppStoreProductDefinition(AppleProductType Type, GoldPlan Plan);

/// <summary>
/// The server's App Store table (<c>Purchases:Apple:*</c>): the bundle ID, exactly the three Gold products and whether sandbox
/// purchases are accepted. Nothing here ever comes from a request.
/// </summary>
public sealed class AppStoreCatalog(string bundleId, IReadOnlyDictionary<string, AppStoreProductDefinition> products, bool allowSandbox)
{
    public string BundleId { get; } = bundleId;

    public IReadOnlyDictionary<string, AppStoreProductDefinition> Products { get; } = products;

    /// <summary>PO question 4: App Review and TestFlight buy in sandbox against the production backend.</summary>
    public bool AllowSandbox { get; } = allowSandbox;

    public bool TryGet(string? productId, out AppStoreProductDefinition definition)
    {
        if (productId is null)
        {
            definition = null!;
            return false;
        }

        return Products.TryGetValue(productId, out definition!);
    }
}

/// <summary>The stored App Store purchase a support check is about.</summary>
public sealed record AppStoreOwnershipPurchase(Sensitive<string> OriginalTransactionId, PurchaseEnvironment Environment);

/// <summary>
/// The live App Store order-ID check of the audited support actions (D-57, backend-api §5.3; T-186 calls it). The order ID lives
/// only in this call: it is never stored, logged, traced, put in an exception message or made a metric tag.
/// </summary>
public interface IAppStoreOrderLookup
{
    Task<OwnershipOutcome> CheckAsync(Sensitive<string> orderId, AppStoreOwnershipPurchase purchase, CancellationToken cancellationToken);
}
