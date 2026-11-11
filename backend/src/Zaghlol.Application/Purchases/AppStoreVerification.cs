using System.Text.RegularExpressions;
using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>
/// iOS verify (backend-api §4.3, T-131 design note §3). Each step runs only if the previous one passed, and nothing is written
/// before the upsert: a forged or malformed JWS, another app's or product's transaction, a sandbox purchase while sandbox is off,
/// another install's binding, a family-shared purchase and a state outside the table never touch the database. The app's JWS only
/// names the transaction: state, revocation and the binding come from Apple's API copies, validated at now. Store failures throw
/// <see cref="StoreUnavailableException"/> and grant nothing.
/// </summary>
public sealed partial class AppStoreVerification(
    IAppleJwsVerifier jws,
    IAppStoreServerApi apple,
    AppStoreCatalog catalog,
    IPurchaseWriter writer,
    IAppleVerifyLimiter limiter,
    IPurchaseTelemetry telemetry,
    TimeProvider clock) : IStoreVerification
{
    private readonly AppleSubscriptionReader reader = new(jws, apple, catalog, telemetry);

    /// <summary><c>Retry-After</c> for an Apple failure that carries none.</summary>
    public const int DefaultRetryAfterSeconds = 30;

    /// <summary>
    /// Apple's eventual consistency right after a purchase: <c>4040010</c> within this time of the JWS <c>signedDate</c> is an outage
    /// the app retries; after it, the transaction doesn't exist (T-131 §3 "Apple answers").
    /// </summary>
    public static readonly TimeSpan NotFoundGrace = TimeSpan.FromMinutes(10);

    /// <summary>Transaction identifiers: digits only, checked before any call (they go into the request path).</summary>
    public const string TransactionIdPattern = @"^[0-9]{1,32}\z";

    public PurchaseStore Store => PurchaseStore.AppStore;

    public async Task<StoreVerificationResult> VerifyAsync(
        StorePurchaseRef purchase,
        InstallId caller,
        BindingCheck binding,
        CancellationToken cancellationToken)
    {
        if (purchase is not AppStorePurchaseRef appStore)
        {
            throw new ArgumentException("The App Store verifier takes only an App Store purchase.", nameof(purchase));
        }

        // 1. The app's JWS: chain, OIDs and signature at its own signedDate. Any failure is final, with no Apple call.
        var now = clock.GetUtcNow();
        AppleTransaction app;
        try
        {
            app = jws.VerifyTransaction(appStore.SignedTransaction, JwsSource.App, now);
            telemetry.AppleJwsChecked(JwsSource.App, null);
        }
        catch (AppleJwsException error)
        {
            telemetry.AppleJwsChecked(JwsSource.App, error.Reason);
            return StoreVerificationResult.Rejected(ErrorCodes.PurchaseTokenInvalid);
        }

        // 2. The app JWS's claims against the server's table. No Apple call for any of these.
        if (!string.Equals(app.BundleId, catalog.BundleId, StringComparison.Ordinal)
            || catalog.BundleId.Length == 0
            || !catalog.TryGet(app.ProductId, out var product)
            || product.Type != app.Type)
        {
            return StoreVerificationResult.Rejected(ErrorCodes.PurchaseWrongApp);
        }

        if (EnvironmentOf(app.Environment) is not { } environment
            || (environment == PurchaseEnvironment.Sandbox && !catalog.AllowSandbox)
            || !IsTransactionId(app.TransactionId)
            || !IsTransactionId(app.OriginalTransactionId))
        {
            return StoreVerificationResult.Rejected(ErrorCodes.PurchaseTokenInvalid, product.Plan);
        }

        if (binding == BindingCheck.RequireCaller && !limiter.TryAcquire(caller))
        {
            throw new StoreUnavailableException(StoreFailureKind.Budget, 600);
        }

        // Restore (T-185) spends the restore lane, which the Apple budget denies first.
        var lane = binding == BindingCheck.RequireCaller ? StoreLane.Verify : StoreLane.Restore;

        // 3. Apple's reads, routed by the signed environment only (no production-to-sandbox fallback). readAt comes first, so a
        // slower read never overwrites a newer one.
        var readAt = clock.GetUtcNow();
        var transactionId = app.TransactionId!.Value;
        var originalTransactionId = app.OriginalTransactionId!.Value.Reveal();
        Sensitive<string> signed;
        try
        {
            signed = await apple.GetTransactionInfoAsync(environment, transactionId, lane, cancellationToken);
        }
        catch (AppStoreApiException error)
        {
            if (error.IsInvalidTransactionId || (error.IsTransactionNotFound && readAt - app.SignedDate > NotFoundGrace))
            {
                return StoreVerificationResult.Rejected(ErrorCodes.PurchaseTokenInvalid, product.Plan);
            }

            throw Unavailable(error);
        }

        var current = VerifyApiCopy(signed, readAt);
        if (!SameTransaction(current, app))
        {
            throw Contradiction();
        }

        // 4. The binding, on Apple's copy: this install's StoreBindingRef, and a purchase the user bought themselves.
        string? boundRef = null;
        if (binding == BindingCheck.RequireCaller)
        {
            if (!StoreBindingRef.MatchesAppAccountToken(current.AppAccountToken?.Reveal(), caller) || current.OwnershipType != AppleOwnershipType.Purchased)
            {
                return StoreVerificationResult.Rejected(ErrorCodes.PurchaseNotOwned, product.Plan);
            }
        }

        if (StoreBindingRef.TryCanonicalUuid(current.AppAccountToken?.Reveal(), out var canonical))
        {
            boundRef = canonical;
        }

        // 5. The state, from Apple's API copies only.
        string latestProductId;
        GoldPlan plan;
        MappedAppleState mapped;
        if (product.Type == AppleProductType.NonConsumable)
        {
            latestProductId = app.ProductId!;
            plan = product.Plan;
            mapped = AppStoreStateMapping.MapLifetime(current);
        }
        else
        {
            (latestProductId, plan, mapped) = await ReadSubscriptionAsync(environment, transactionId, originalTransactionId, lane, readAt, cancellationToken);
        }

        if (!mapped.IsKnown)
        {
            // Never grant on doubt: a state outside the table is an outage of understanding, not the user's fault.
            throw Doubt();
        }

        // 6. Upsert keyed by originalTransactionId, with the new-payment rule in the same transaction (§4).
        DateTimeOffset? newPaymentAt = null;
        if (binding == BindingCheck.RequireCaller && current.Reason == AppleTransactionReason.Purchase)
        {
            newPaymentAt = current.PurchaseDate ?? throw Contradiction();
        }

        var stored = await writer.UpsertAsync(
            new PurchaseUpsert(
                PurchaseStore.AppStore,
                latestProductId,
                plan,
                new Sensitive<string>(originalTransactionId),
                null,
                binding == BindingCheck.RequireCaller ? caller : null,
                mapped.State!.Value,
                mapped.ExpiresAt,
                true,
                environment,
                boundRef,
                readAt,
                mapped.KeepStoredExpiry,
                newPaymentAt),
            "verify",
            cancellationToken);
        telemetry.EnvironmentSeen(PurchaseTags.AppStore, environment);

        // 7. The result; the endpoint's grant gate applies.
        return new StoreVerificationResult(
            PlayStateMapping.StatusOf(stored.State),
            null,
            stored.PurchaseId,
            plan,
            stored.ExpiresAt,
            environment,
            null,
            true,
            stored.IsNewPayment);
    }

    internal static PurchaseEnvironment? EnvironmentOf(AppleEnvironment environment) => environment switch
    {
        AppleEnvironment.Production => PurchaseEnvironment.Production,
        AppleEnvironment.Sandbox => PurchaseEnvironment.Sandbox,
        _ => null,
    };

    internal static bool IsTransactionId(Sensitive<string>? id) => id?.Reveal() is { } text && TransactionId().IsMatch(text);

    /// <summary>Anything but an explicit final answer is an outage: 502, or 503 for our own budget.</summary>
    internal static StoreUnavailableException Unavailable(AppStoreApiException error)
    {
        var kind = error.Outcome == AppStoreCallOutcome.BudgetDenied ? StoreFailureKind.Budget : StoreFailureKind.Store;
        var retryAfter = error.RetryAfter is { } delay ? (int)Math.Ceiling(delay.TotalSeconds) : DefaultRetryAfterSeconds;
        return new StoreUnavailableException(kind, Math.Clamp(retryAfter, 1, 300), error);
    }

    private static StoreUnavailableException Doubt() => new(StoreFailureKind.Store, DefaultRetryAfterSeconds);

    /// <summary>Apple's verified answers contradict each other or the app's copy: 502, counted as an <c>api</c> payload failure (alerted).</summary>
    private StoreUnavailableException Contradiction()
    {
        telemetry.AppleJwsChecked(JwsSource.Api, AppleJwsFailure.Payload);
        return Doubt();
    }

    private static bool SameTransaction(AppleTransaction api, AppleTransaction app) =>
        string.Equals(api.TransactionId?.Reveal(), app.TransactionId?.Reveal(), StringComparison.Ordinal)
        && string.Equals(api.OriginalTransactionId?.Reveal(), app.OriginalTransactionId?.Reveal(), StringComparison.Ordinal)
        && string.Equals(api.BundleId, app.BundleId, StringComparison.Ordinal)
        && string.Equals(api.ProductId, app.ProductId, StringComparison.Ordinal)
        && api.Type == app.Type
        && api.Environment == app.Environment;

    /// <summary>
    /// The subscription read, shared with the notification worker (<see cref="AppleSubscriptionReader"/>, T-134 §2 step 3). An API
    /// failure is an outage (502, or 503 for our budget); anything else Apple answered is doubt (502; the reader already counted a
    /// JWS failure or contradiction as an alerted <c>api</c> failure).
    /// </summary>
    private async Task<(string ProductId, GoldPlan Plan, MappedAppleState Mapped)> ReadSubscriptionAsync(
        PurchaseEnvironment environment,
        Sensitive<string> transactionId,
        string originalTransactionId,
        StoreLane lane,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        try
        {
            var read = await reader.ReadSubscriptionAsync(environment, transactionId, originalTransactionId, lane, now, cancellationToken);
            return (read.ProductId, read.Plan, read.Mapped);
        }
        catch (AppleReadException error) when (error.ApiError is { } api)
        {
            // Get Transaction Info already found this transaction: nothing here is a final answer about it.
            throw Unavailable(api);
        }
        catch (AppleReadException)
        {
            throw Doubt();
        }
    }

    /// <summary>An Apple API JWS, validated at now. A failure is Apple contradicting itself: 502 and the <c>api</c> alert.</summary>
    private AppleTransaction VerifyApiCopy(Sensitive<string> signed, DateTimeOffset now)
    {
        try
        {
            var transaction = jws.VerifyTransaction(signed, JwsSource.Api, now);
            telemetry.AppleJwsChecked(JwsSource.Api, null);
            return transaction;
        }
        catch (AppleJwsException error)
        {
            telemetry.AppleJwsChecked(JwsSource.Api, error.Reason);
            throw Doubt();
        }
    }

    [GeneratedRegex(TransactionIdPattern, RegexOptions.CultureInvariant)]
    private static partial Regex TransactionId();
}
