using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>Who spends an outbound store call (T-130 design note §2). Restore is limited first.</summary>
public enum StoreLane
{
    Verify,
    Ack,
    Rtdn,
    Support,
    Restore,
}

/// <summary>The shared outbound budget for Play and App Store calls (backend-api §1 "Rate limits").</summary>
public interface IStoreCallBudget
{
    /// <summary>True when the lane may make one call now. A denied call must not be made.</summary>
    bool TryAcquire(StoreLane lane);
}

/// <summary>The Play Developer API calls the server makes. The v1 <c>products.get</c> and <c>subscriptions.get</c> are not here.</summary>
public enum PlayApi
{
    SubscriptionGet,
    ProductGet,
    SubscriptionAcknowledge,
    ProductAcknowledge,
    OrderGet,
}

/// <summary>How a Play call ended (<c>zaghlol.store.call{outcome}</c>).</summary>
public enum PlayCallOutcome
{
    Ok,

    /// <summary>400, 404, 410 or another 4xx Play attributes to the request: the token (or order) is not valid.</summary>
    ClientError,

    /// <summary>401 or 403: our credential or permission is wrong. Never the user's fault (alerted).</summary>
    AuthError,
    RateLimited,
    ServerError,
    Timeout,
    CircuitOpen,
    BudgetDenied,
}

/// <summary>
/// A Play call that did not return a usable answer. The message is a constant: the response body, the URL, the token and the
/// order ID are never put in it (D-57).
/// </summary>
public sealed class PlayApiException : SafeException
{
    public const string DefaultMessage = "A Google Play Developer API call failed.";

    public PlayApiException()
        : base(DefaultMessage)
    {
    }

    public PlayApiException(PlayApi api, PlayCallOutcome outcome, int? httpStatus = null, TimeSpan? retryAfter = null)
        : base(DefaultMessage)
    {
        Api = api;
        Outcome = outcome;
        HttpStatus = httpStatus;
        RetryAfter = retryAfter;
    }

    public PlayApiException(string message)
        : base(message)
    {
    }

    public PlayApiException(string message, Exception innerException)
        : base(message, innerException)
    {
    }

    public PlayApi Api { get; }

    public PlayCallOutcome Outcome { get; }

    public int? HttpStatus { get; }

    public TimeSpan? RetryAfter { get; }

    /// <summary>Play says the token (or order) doesn't exist or isn't ours: a final answer, not an outage.</summary>
    public bool IsFinalRejection => Outcome == PlayCallOutcome.ClientError;
}

/// <summary><c>SubscriptionPurchaseV2.subscriptionState</c>; anything Play adds later is <see cref="Unknown"/>.</summary>
public enum PlaySubscriptionState
{
    Unknown,
    Pending,
    Active,
    Paused,
    InGracePeriod,
    OnHold,
    Canceled,
    Expired,
    PendingPurchaseCanceled,
}

/// <summary><c>ProductPurchaseV2.purchaseStateContext.purchaseState</c>.</summary>
public enum PlayProductState
{
    Unknown,
    Purchased,
    Cancelled,
    Pending,
}

/// <summary><c>Order.state</c>.</summary>
public enum PlayOrderState
{
    Unknown,
    Pending,
    Processed,
    Canceled,
    PendingRefund,
    PartiallyRefunded,
    Refunded,
}

/// <summary>One <c>lineItems[]</c> element: only the fields the server reads. The deprecated <c>latestOrderId</c> is not one.</summary>
public sealed record PlayLineItem(string? ProductId, DateTimeOffset? ExpiryTime, Sensitive<string>? LatestSuccessfulOrderId);

/// <summary>The read fields of <c>purchases.subscriptionsv2.get</c>.</summary>
public sealed record PlaySubscription(
    PlaySubscriptionState State,
    IReadOnlyList<PlayLineItem> LineItems,
    Sensitive<string>? LinkedPurchaseToken,
    bool Acknowledged,
    bool TestPurchase,
    string? ObfuscatedExternalAccountId,
    DateTimeOffset? StartTime);

/// <summary>The read fields of <c>purchases.productsv2.getproductpurchasev2</c>.</summary>
public sealed record PlayProduct(
    IReadOnlyList<string> ProductIds,
    PlayProductState State,
    bool TestPurchase,
    Sensitive<string>? OrderId,
    string? ObfuscatedExternalAccountId,
    bool Acknowledged,
    DateTimeOffset? PurchaseCompletionTime);

/// <summary>The read fields of <c>orders.get</c>.</summary>
public sealed record PlayOrder(Sensitive<string>? PurchaseToken, PlayOrderState State);

/// <summary>
/// The Google Play Developer API (T-130). Every call takes the package from configuration, never from a request, escapes the
/// token or order ID into the path, draws on <see cref="IStoreCallBudget"/> for <paramref name="lane"/> and throws
/// <see cref="PlayApiException"/> on anything but a usable 2xx.
/// </summary>
public interface IPlayDeveloperApi
{
    Task<PlaySubscription> GetSubscriptionAsync(Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken);

    Task<PlayProduct> GetProductAsync(Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken);

    /// <param name="productId">The product ID Play returned for the token (never the request's).</param>
    Task AcknowledgeSubscriptionAsync(string productId, Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken);

    /// <param name="productId">The product ID Play returned for the token (never the request's).</param>
    Task AcknowledgeProductAsync(string productId, Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken);

    Task<PlayOrder> GetOrderAsync(Sensitive<string> orderId, StoreLane lane, CancellationToken cancellationToken);
}

/// <summary>Subscription or one-time product (selects the Play endpoint).</summary>
public enum PlayProductKind
{
    Subscription,
    OneTime,
}

public sealed record PlayProductDefinition(PlayProductKind Kind, GoldPlan Plan);

/// <summary>
/// The server's product table (<c>Purchases:Google:*</c>): the package name and exactly the Gold product IDs. The package name
/// never comes from a request.
/// </summary>
public sealed class PlayProductCatalog(string packageName, IReadOnlyDictionary<string, PlayProductDefinition> products)
{
    public string PackageName { get; } = packageName;

    public IReadOnlyDictionary<string, PlayProductDefinition> Products { get; } = products;

    public bool TryGet(string productId, out PlayProductDefinition definition) =>
        Products.TryGetValue(productId, out definition!);
}
