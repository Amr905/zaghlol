using System.Collections.Concurrent;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Purchases;

/// <summary>
/// The JWS verifier stand-in: a "JWS" is a key into <see cref="Transactions"/> / <see cref="Renewals"/>, or into
/// <see cref="Failures"/> for one that fails verification. The real verifier has its own tests (Infrastructure, test PKI).
/// </summary>
internal sealed class FakeAppleJwsVerifier : IAppleJwsVerifier
{
    public Dictionary<string, AppleTransaction> Transactions { get; } = new(StringComparer.Ordinal);

    public Dictionary<string, AppleRenewalInfo> Renewals { get; } = new(StringComparer.Ordinal);

    public Dictionary<string, AppleJwsFailure> Failures { get; } = new(StringComparer.Ordinal);

    public ConcurrentQueue<(string Jws, JwsSource Source)> Calls { get; } = new();

    public AppleTransaction VerifyTransaction(Sensitive<string> jws, JwsSource source, DateTimeOffset now)
    {
        var key = jws.Reveal();
        Calls.Enqueue((key, source));
        if (Failures.TryGetValue(key, out var failure))
        {
            throw new AppleJwsException(failure);
        }

        return Transactions.TryGetValue(key, out var transaction) ? transaction : throw new AppleJwsException(AppleJwsFailure.Malformed);
    }

    public AppleRenewalInfo VerifyRenewalInfo(Sensitive<string> jws, DateTimeOffset now)
    {
        var key = jws.Reveal();
        Calls.Enqueue((key, JwsSource.Api));
        if (Failures.TryGetValue(key, out var failure))
        {
            throw new AppleJwsException(failure);
        }

        return Renewals.TryGetValue(key, out var renewal) ? renewal : throw new AppleJwsException(AppleJwsFailure.Malformed);
    }
}

/// <summary>The App Store Server API stand-in: answers by (environment, transaction ID) or order ID, or throws the scripted error.</summary>
internal sealed class FakeAppStoreServerApi : IAppStoreServerApi
{
    public Dictionary<(PurchaseEnvironment, string), string> TransactionInfo { get; } = [];

    public Dictionary<(PurchaseEnvironment, string), List<AppleLastTransaction>> Statuses { get; } = [];

    public Dictionary<string, AppleOrderLookupResult> Lookups { get; } = new(StringComparer.Ordinal);

    public Dictionary<AppStoreApi, AppStoreApiException> Errors { get; } = [];

    public ConcurrentQueue<(AppStoreApi Api, PurchaseEnvironment Environment, string Subject, StoreLane Lane)> Calls { get; } = new();

    public int CallsTo(AppStoreApi api) => Calls.Count(c => c.Api == api);

    public Task<Sensitive<string>> GetTransactionInfoAsync(PurchaseEnvironment environment, Sensitive<string> transactionId, StoreLane lane, CancellationToken cancellationToken)
    {
        Record(AppStoreApi.TransactionInfo, environment, transactionId.Reveal(), lane);
        return TransactionInfo.TryGetValue((environment, transactionId.Reveal()), out var signed)
            ? Task.FromResult(new Sensitive<string>(signed))
            : throw new AppStoreApiException(AppStoreApi.TransactionInfo, AppStoreCallOutcome.ClientError, 404, AppStoreApiException.TransactionIdNotFound);
    }

    public Task<IReadOnlyList<AppleLastTransaction>> GetAllSubscriptionStatusesAsync(PurchaseEnvironment environment, Sensitive<string> transactionId, StoreLane lane, CancellationToken cancellationToken)
    {
        Record(AppStoreApi.SubscriptionStatuses, environment, transactionId.Reveal(), lane);
        return Statuses.TryGetValue((environment, transactionId.Reveal()), out var items)
            ? Task.FromResult<IReadOnlyList<AppleLastTransaction>>(items)
            : throw new AppStoreApiException(AppStoreApi.SubscriptionStatuses, AppStoreCallOutcome.ClientError, 404, AppStoreApiException.TransactionIdNotFound);
    }

    public Task<AppleOrderLookupResult> LookUpOrderIdAsync(Sensitive<string> orderId, StoreLane lane, CancellationToken cancellationToken)
    {
        Record(AppStoreApi.OrderLookup, PurchaseEnvironment.Production, orderId.Reveal(), lane);
        return Lookups.TryGetValue(orderId.Reveal(), out var lookup)
            ? Task.FromResult(lookup)
            : Task.FromResult(new AppleOrderLookupResult(1, []));
    }

    private void Record(AppStoreApi api, PurchaseEnvironment environment, string subject, StoreLane lane)
    {
        Calls.Enqueue((api, environment, subject, lane));
        if (Errors.TryGetValue(api, out var error))
        {
            throw error;
        }
    }
}

/// <summary>A per-install limiter the tests open or close.</summary>
internal sealed class FakeVerifyLimiter : IAppleVerifyLimiter
{
    public bool Allow { get; set; } = true;

    public int Calls { get; private set; }

    public bool TryAcquire(InstallId install)
    {
        Calls++;
        return Allow;
    }
}

/// <summary>
/// Common App Store fixtures. A purchase is scripted as: the app's JWS (key <c>app:{tx}</c>), Apple's Get Transaction Info copy
/// (<c>api:{tx}</c>) and, for subscriptions, the status item (<c>latest:{orig}</c>, <c>renewal:{orig}</c>).
/// </summary>
internal sealed class AppleScript
{
    public const string Bundle = "app.zaghlol";
    public const string Monthly = "zaghlol_gold_monthly";
    public const string Yearly = "zaghlol_gold_yearly";
    public const string Lifetime = "zaghlol_gold_lifetime";

    public static readonly DateTimeOffset Now = new(2026, 11, 11, 12, 0, 0, TimeSpan.Zero);

    private static long sequence = 2000000000000000;

    public FakeAppleJwsVerifier Jws { get; } = new();

    public FakeAppStoreServerApi Api { get; } = new();

    public static AppStoreCatalog Catalog(bool allowSandbox = true) => new(Bundle, new Dictionary<string, AppStoreProductDefinition>(StringComparer.Ordinal)
    {
        [Monthly] = new(AppleProductType.AutoRenewable, GoldPlan.Monthly),
        [Yearly] = new(AppleProductType.AutoRenewable, GoldPlan.Yearly),
        [Lifetime] = new(AppleProductType.NonConsumable, GoldPlan.Lifetime),
    }, allowSandbox);

    public static string NewId() => Interlocked.Increment(ref sequence).ToString(System.Globalization.CultureInfo.InvariantCulture);

    public static AppleTransaction Tx(
        string transactionId,
        string originalTransactionId,
        InstallId? boundTo,
        string productId = Yearly,
        AppleEnvironment environment = AppleEnvironment.Production,
        AppleProductType type = AppleProductType.AutoRenewable,
        AppleOwnershipType ownership = AppleOwnershipType.Purchased,
        AppleTransactionReason reason = AppleTransactionReason.Purchase,
        DateTimeOffset? purchaseDate = null,
        DateTimeOffset? expiresDate = null,
        DateTimeOffset? revocationDate = null,
        int? revocationReason = null,
        string bundleId = Bundle,
        DateTimeOffset? signedDate = null,
        string? appAccountToken = null) =>
        new(
            bundleId,
            environment,
            productId,
            type,
            new Sensitive<string>(transactionId),
            new Sensitive<string>(originalTransactionId),
            (appAccountToken ?? (boundTo is { } id ? StoreBindingRef.Compute(id) : null)) is { } token ? new Sensitive<string>(token) : null,
            ownership,
            reason,
            purchaseDate ?? Now.AddMinutes(-2),
            type == AppleProductType.AutoRenewable ? expiresDate ?? Now.AddDays(30) : expiresDate,
            revocationDate,
            revocationReason,
            signedDate ?? Now.AddMinutes(-1));

    /// <summary>The app's JWS and Apple's identical Get Transaction Info copy; returns the app JWS key.</summary>
    public string Purchase(AppleTransaction transaction, AppleTransaction? apiCopy = null)
    {
        var id = transaction.TransactionId!.Value.Reveal();
        var environment = transaction.Environment == AppleEnvironment.Sandbox ? PurchaseEnvironment.Sandbox : PurchaseEnvironment.Production;
        Jws.Transactions["app:" + id] = transaction;
        Jws.Transactions["api:" + id] = apiCopy ?? transaction;
        Api.TransactionInfo[(environment, id)] = "api:" + id;
        return "app:" + id;
    }

    /// <summary>Apple's status item for the subscription <paramref name="latest"/> belongs to.</summary>
    public void Status(AppleTransaction latest, int status = 1, int? autoRenew = 1, DateTimeOffset? grace = null, string? forTransactionId = null)
    {
        var original = latest.OriginalTransactionId!.Value.Reveal();
        var environment = latest.Environment == AppleEnvironment.Sandbox ? PurchaseEnvironment.Sandbox : PurchaseEnvironment.Production;
        Jws.Transactions["latest:" + original] = latest;
        Jws.Renewals["renewal:" + original] = new AppleRenewalInfo(latest.OriginalTransactionId, latest.Environment, autoRenew, grace);
        var item = new AppleLastTransaction(status, latest.OriginalTransactionId, new Sensitive<string>("latest:" + original), new Sensitive<string>("renewal:" + original));
        Api.Statuses[(environment, forTransactionId ?? latest.TransactionId!.Value.Reveal())] = [item];
    }
}
