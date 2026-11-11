using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>Why an App Store re-read gave no usable answer (<see cref="AppleReadException"/>).</summary>
public enum AppleReadFailure
{
    /// <summary>The App Store Server API call failed; <see cref="AppleReadException.ApiError"/> says how.</summary>
    Api,

    /// <summary>A JWS in Apple's own answer failed verification (counted as an <c>api</c> JWS failure, alerted).</summary>
    Jws,

    /// <summary>Apple's verified answers contradict each other or the stored purchase (counted as an <c>api</c> payload failure).</summary>
    Contradiction,

    /// <summary>The latest product isn't one of ours (our configuration is behind Apple).</summary>
    UnknownProduct,
}

/// <summary>An App Store re-read failed. The message is a constant; nothing from Apple is in it.</summary>
public sealed class AppleReadException : SafeException
{
    public const string DefaultMessage = "An App Store re-read gave no usable answer.";

    public AppleReadException()
        : base(DefaultMessage)
    {
    }

    public AppleReadException(AppleReadFailure failure, AppStoreApiException? apiError = null)
        : base(DefaultMessage, apiError!)
    {
        Failure = failure;
        ApiError = apiError;
    }

    public AppleReadException(string message)
        : base(message)
    {
    }

    public AppleReadException(string message, Exception innerException)
        : base(message, innerException)
    {
    }

    public AppleReadFailure Failure { get; }

    public AppStoreApiException? ApiError { get; }
}

/// <summary>A re-read mapped to what Zaghlol stores: the latest product, its plan and the state.</summary>
public readonly record struct AppleStoreRead(string ProductId, GoldPlan Plan, MappedAppleState Mapped);

/// <summary>
/// The App Store reads that verify (T-131 §3 step 5) and the notification worker (T-134 design note §2 step 3) share, so both apply
/// the same state table to the same calls. Only Apple's API copies are mapped, each validated at <c>now</c>. Every failure is an
/// <see cref="AppleReadException"/>; the caller decides what it means (verify: 502; worker: a retry code).
/// </summary>
public sealed class AppleSubscriptionReader(IAppleJwsVerifier jws, IAppStoreServerApi apple, AppStoreCatalog catalog, IPurchaseTelemetry telemetry)
{
    /// <summary>
    /// <c>Get All Subscription Statuses</c> for <paramref name="transactionId"/> (any transaction of the subscription), the item of
    /// <paramref name="originalTransactionId"/>, both its JWSs verified at <paramref name="now"/>, cross-checked and mapped.
    /// </summary>
    public async Task<AppleStoreRead> ReadSubscriptionAsync(
        PurchaseEnvironment environment,
        Sensitive<string> transactionId,
        string originalTransactionId,
        StoreLane lane,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        IReadOnlyList<AppleLastTransaction> items;
        try
        {
            items = await apple.GetAllSubscriptionStatusesAsync(environment, transactionId, lane, cancellationToken);
        }
        catch (AppStoreApiException error)
        {
            throw new AppleReadException(AppleReadFailure.Api, error);
        }

        var ours = items.Where(i => string.Equals(i.OriginalTransactionId?.Reveal(), originalTransactionId, StringComparison.Ordinal)).ToList();
        if (ours.Count != 1 || ours[0].SignedTransactionInfo is not { } signedLatest || ours[0].SignedRenewalInfo is not { } signedRenewal)
        {
            throw Contradiction();
        }

        var latest = VerifyApiCopy(signedLatest, now);
        AppleRenewalInfo renewal;
        try
        {
            renewal = jws.VerifyRenewalInfo(signedRenewal, JwsSource.Api, now);
            telemetry.AppleJwsChecked(JwsSource.Api, null);
        }
        catch (AppleJwsException error)
        {
            telemetry.AppleJwsChecked(JwsSource.Api, error.Reason);
            throw new AppleReadException(AppleReadFailure.Jws);
        }

        var expectedEnvironment = Expected(environment);
        if (!string.Equals(latest.OriginalTransactionId?.Reveal(), originalTransactionId, StringComparison.Ordinal)
            || !string.Equals(latest.BundleId, catalog.BundleId, StringComparison.Ordinal)
            || latest.Environment != expectedEnvironment
            || (renewal.OriginalTransactionId is { } renewalOriginal && !string.Equals(renewalOriginal.Reveal(), originalTransactionId, StringComparison.Ordinal))
            || (renewal.Environment != AppleEnvironment.Unknown && renewal.Environment != expectedEnvironment))
        {
            throw Contradiction();
        }

        // The latest transaction's product must be one of ours (our configuration is behind Apple otherwise).
        if (!catalog.TryGet(latest.ProductId, out var latestProduct) || latestProduct.Type != AppleProductType.AutoRenewable)
        {
            throw new AppleReadException(AppleReadFailure.UnknownProduct);
        }

        return new AppleStoreRead(latest.ProductId!, latestProduct.Plan, AppStoreStateMapping.MapSubscription(ours[0].Status, latest, renewal));
    }

    /// <summary>
    /// A lifetime purchase (T-134 §2 step 3): <c>Get Transaction Info</c> of its <paramref name="originalTransactionId"/>, verified at
    /// <paramref name="now"/>, which must name the same purchase, bundle, environment and a non-consumable Gold product.
    /// </summary>
    public async Task<AppleStoreRead> ReadLifetimeAsync(
        PurchaseEnvironment environment,
        string originalTransactionId,
        StoreLane lane,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        Sensitive<string> signed;
        try
        {
            signed = await apple.GetTransactionInfoAsync(environment, new Sensitive<string>(originalTransactionId), lane, cancellationToken);
        }
        catch (AppStoreApiException error)
        {
            throw new AppleReadException(AppleReadFailure.Api, error);
        }

        var transaction = VerifyApiCopy(signed, now);
        if (!string.Equals(transaction.OriginalTransactionId?.Reveal(), originalTransactionId, StringComparison.Ordinal)
            || !string.Equals(transaction.BundleId, catalog.BundleId, StringComparison.Ordinal)
            || transaction.Environment != Expected(environment))
        {
            throw Contradiction();
        }

        if (!catalog.TryGet(transaction.ProductId, out var product) || product.Type != AppleProductType.NonConsumable
            || transaction.Type != AppleProductType.NonConsumable)
        {
            throw new AppleReadException(AppleReadFailure.UnknownProduct);
        }

        return new AppleStoreRead(transaction.ProductId!, product.Plan, AppStoreStateMapping.MapLifetime(transaction));
    }

    /// <summary>An Apple API JWS, validated at now. A failure is Apple contradicting itself: the <c>api</c> alert.</summary>
    public AppleTransaction VerifyApiCopy(Sensitive<string> signedTransaction, DateTimeOffset now)
    {
        try
        {
            var transaction = jws.VerifyTransaction(signedTransaction, JwsSource.Api, now);
            telemetry.AppleJwsChecked(JwsSource.Api, null);
            return transaction;
        }
        catch (AppleJwsException error)
        {
            telemetry.AppleJwsChecked(JwsSource.Api, error.Reason);
            throw new AppleReadException(AppleReadFailure.Jws);
        }
    }

    private static AppleEnvironment Expected(PurchaseEnvironment environment) =>
        environment == PurchaseEnvironment.Sandbox ? AppleEnvironment.Sandbox : AppleEnvironment.Production;

    /// <summary>Apple's verified answers contradict each other: counted as an <c>api</c> payload failure (alerted).</summary>
    private AppleReadException Contradiction()
    {
        telemetry.AppleJwsChecked(JwsSource.Api, AppleJwsFailure.Payload);
        return new AppleReadException(AppleReadFailure.Contradiction);
    }
}
