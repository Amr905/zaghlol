using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>
/// Android verify (backend-api §4.3, T-130 design note §1). Each step runs only if the previous one passed, and nothing is
/// written before the upsert: an unknown product, a malformed token, a token Play rejects, another product's token, another
/// install's binding, a pending-purchase-cancelled read and an unknown state never touch the database. Store failures throw
/// <see cref="StoreUnavailableException"/> and grant nothing.
/// </summary>
public sealed class PlayVerification(
    IPlayDeveloperApi play,
    PlayProductCatalog catalog,
    IPurchaseWriter writer,
    IPurchaseTelemetry telemetry,
    TimeProvider clock) : IStoreVerification
{
    /// <summary><c>Retry-After</c> for a Play failure that carries none.</summary>
    public const int DefaultRetryAfterSeconds = 30;

    public PurchaseStore Store => PurchaseStore.GooglePlay;

    public async Task<StoreVerificationResult> VerifyAsync(
        StorePurchaseRef purchase,
        InstallId caller,
        BindingCheck binding,
        CancellationToken cancellationToken)
    {
        if (purchase is not PlayPurchaseRef google)
        {
            throw new ArgumentException("The Google Play verifier takes only a Google Play purchase.", nameof(purchase));
        }

        // 1-2. Request shape and the server's product table; no Play call for either.
        if (!catalog.TryGet(google.ProductId, out var product))
        {
            return StoreVerificationResult.Rejected(ErrorCodes.PurchaseWrongApp);
        }

        if (!PlayStateMapping.IsWellFormedToken(google.PurchaseToken))
        {
            return StoreVerificationResult.Rejected(ErrorCodes.PurchaseTokenInvalid, product.Plan);
        }

        // 3. Play read. readAt is taken first, so a slower read never overwrites a newer one.
        var readAt = clock.GetUtcNow();
        var read = product.Kind == PlayProductKind.Subscription
            ? await ReadSubscriptionAsync(google, readAt, cancellationToken)
            : await ReadProductAsync(google, cancellationToken);
        if (read.Rejection is { } rejection)
        {
            return StoreVerificationResult.Rejected(rejection, product.Plan);
        }

        // 4. Binding: the store value must be this install's StoreBindingRef (constant time). Absent or different: not owned.
        if (binding == BindingCheck.RequireCaller && !StoreBindingRef.Matches(read.ObfuscatedAccountId, caller))
        {
            return StoreVerificationResult.Rejected(ErrorCodes.PurchaseNotOwned, product.Plan);
        }

        switch (read.Mapped.Outcome)
        {
            case PlayReadOutcome.PendingPurchaseCanceled:
                return StoreVerificationResult.Rejected(ErrorCodes.PurchaseTokenInvalid, product.Plan);
            case PlayReadOutcome.Unknown:
                // Never grant on doubt: an unknown state is an outage of understanding, not the user's fault.
                throw new StoreUnavailableException(StoreFailureKind.Store, DefaultRetryAfterSeconds);
        }

        var environment = read.TestPurchase ? PurchaseEnvironment.Sandbox : PurchaseEnvironment.Production;

        // 5. Upsert (one short transaction). install_id on insert only, and only for the binding-checked caller.
        var stored = await writer.UpsertAsync(
            new PurchaseUpsert(
                PurchaseStore.GooglePlay,
                read.PlayProductId,
                product.Plan,
                google.PurchaseToken,
                read.LinkedPurchaseToken,
                binding == BindingCheck.RequireCaller ? caller : null,
                read.Mapped.State!.Value,
                read.ExpiresAt,
                read.Acknowledged,
                environment,
                read.ObfuscatedAccountId,
                readAt),
            "verify",
            cancellationToken);

        telemetry.EnvironmentSeen(PurchaseTags.GooglePlay, environment);

        // 6. Acknowledge an active purchase that isn't yet, outside any transaction; failure never withholds Gold.
        var status = PlayStateMapping.StatusOf(stored.State);
        var acknowledged = stored.Acknowledged;
        if (status == VerifyStatus.Active && !acknowledged)
        {
            acknowledged = await AcknowledgeAsync(product.Kind, read, google.PurchaseToken, stored.PurchaseId, cancellationToken);
        }

        return new StoreVerificationResult(
            status,
            null,
            stored.PurchaseId,
            product.Plan,
            stored.ExpiresAt,
            environment,
            stored.PredecessorPurchaseId,
            acknowledged,
            stored.Inserted && stored.PredecessorPurchaseId is not null);
    }

    /// <summary>
    /// Acknowledges with the Play-returned product ID. An error answer triggers a re-read, and <c>ACKNOWLEDGED</c> there counts
    /// as success. Any other failure is left to the sweeper.
    /// </summary>
    private async Task<bool> AcknowledgeAsync(
        PlayProductKind kind,
        PlayRead read,
        Sensitive<string> token,
        Guid purchaseId,
        CancellationToken cancellationToken)
    {
        try
        {
            if (kind == PlayProductKind.Subscription)
            {
                await play.AcknowledgeSubscriptionAsync(read.PlayProductId, token, StoreLane.Ack, cancellationToken);
            }
            else
            {
                await play.AcknowledgeProductAsync(read.PlayProductId, token, StoreLane.Ack, cancellationToken);
            }

            await writer.MarkAcknowledgedAsync(purchaseId, cancellationToken);
            telemetry.Acknowledged(PurchaseTags.ChannelVerify, PurchaseTags.AckAcked);
            if (read.PurchasedAt is { } purchasedAt)
            {
                telemetry.TimeToAck(clock.GetUtcNow() - purchasedAt);
            }

            return true;
        }
        catch (PlayApiException error) when (error.IsFinalRejection)
        {
            if (await AlreadyAcknowledgedAsync(kind, token, cancellationToken))
            {
                await writer.MarkAcknowledgedAsync(purchaseId, cancellationToken);
                telemetry.Acknowledged(PurchaseTags.ChannelVerify, PurchaseTags.AckAlready);
                return true;
            }

            telemetry.Acknowledged(PurchaseTags.ChannelVerify, PurchaseTags.AckFailed);
            return false;
        }
        catch (PlayApiException)
        {
            telemetry.Acknowledged(PurchaseTags.ChannelVerify, PurchaseTags.AckFailed);
            return false;
        }
    }

    private async Task<bool> AlreadyAcknowledgedAsync(PlayProductKind kind, Sensitive<string> token, CancellationToken cancellationToken)
    {
        try
        {
            return kind == PlayProductKind.Subscription
                ? (await play.GetSubscriptionAsync(token, StoreLane.Ack, cancellationToken)).Acknowledged
                : (await play.GetProductAsync(token, StoreLane.Ack, cancellationToken)).Acknowledged;
        }
        catch (PlayApiException)
        {
            return false;
        }
    }

    private async Task<PlayRead> ReadSubscriptionAsync(PlayPurchaseRef purchase, DateTimeOffset now, CancellationToken cancellationToken)
    {
        PlaySubscription subscription;
        try
        {
            subscription = await play.GetSubscriptionAsync(purchase.PurchaseToken, StoreLane.Verify, cancellationToken);
        }
        catch (PlayApiException error)
        {
            return Failed(error);
        }

        // The product ID Play returns must equal the request's (another product's token is not this purchase).
        var item = subscription.LineItems.FirstOrDefault(i => string.Equals(i.ProductId, purchase.ProductId, StringComparison.Ordinal));
        if (item is null)
        {
            return PlayRead.Reject(ErrorCodes.PurchaseTokenInvalid);
        }

        return new PlayRead(
            null,
            item.ProductId!,
            PlayStateMapping.Map(subscription.State, item.ExpiryTime, now),
            item.ExpiryTime,
            subscription.LinkedPurchaseToken,
            subscription.Acknowledged,
            subscription.TestPurchase,
            subscription.ObfuscatedExternalAccountId,
            subscription.StartTime);
    }

    private async Task<PlayRead> ReadProductAsync(PlayPurchaseRef purchase, CancellationToken cancellationToken)
    {
        PlayProduct product;
        try
        {
            product = await play.GetProductAsync(purchase.PurchaseToken, StoreLane.Verify, cancellationToken);
        }
        catch (PlayApiException error)
        {
            return Failed(error);
        }

        var productId = product.ProductIds.FirstOrDefault(id => string.Equals(id, purchase.ProductId, StringComparison.Ordinal));
        if (productId is null)
        {
            return PlayRead.Reject(ErrorCodes.PurchaseTokenInvalid);
        }

        return new PlayRead(
            null,
            productId,
            PlayStateMapping.Map(product.State),
            null,
            null,
            product.Acknowledged,
            product.TestPurchase,
            product.ObfuscatedExternalAccountId,
            product.PurchaseCompletionTime);
    }

    /// <summary>400/404/410: a final <c>PURCHASE_TOKEN_INVALID</c>. Anything else: an outage (502, or 503 for our budget).</summary>
    private static PlayRead Failed(PlayApiException error)
    {
        if (error.IsFinalRejection)
        {
            return PlayRead.Reject(ErrorCodes.PurchaseTokenInvalid);
        }

        var kind = error.Outcome == PlayCallOutcome.BudgetDenied ? StoreFailureKind.Budget : StoreFailureKind.Store;
        var retryAfter = error.RetryAfter is { } delay ? (int)Math.Ceiling(delay.TotalSeconds) : DefaultRetryAfterSeconds;
        throw new StoreUnavailableException(kind, Math.Clamp(retryAfter, 1, 300), error);
    }

    private sealed record PlayRead(
        string? Rejection,
        string PlayProductId,
        MappedPlayState Mapped,
        DateTimeOffset? ExpiresAt,
        Sensitive<string>? LinkedPurchaseToken,
        bool Acknowledged,
        bool TestPurchase,
        string? ObfuscatedAccountId,
        DateTimeOffset? PurchasedAt)
    {
        public static PlayRead Reject(string code) => new(code, string.Empty, default, null, null, false, false, null, null);
    }
}
