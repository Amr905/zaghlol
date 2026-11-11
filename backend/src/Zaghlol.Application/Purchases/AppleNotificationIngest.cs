using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases;

/// <summary>How one ASSN V2 <c>signedPayload</c> ended (the endpoint's answer and <c>zaghlol.assn.ingest{outcome}</c>).</summary>
public enum AppleIngestOutcome
{
    /// <summary>Inserted: 200.</summary>
    Stored,

    /// <summary>The <c>notificationUUID</c> was already stored: 200, nothing written.</summary>
    Duplicate,

    /// <summary>Any verification or claim check failed: 401, nothing written.</summary>
    Unauthorized,

    /// <summary>Authentic, but no <c>data</c> object (no Gold event): 200, not stored.</summary>
    IgnoredNoData,

    /// <summary>Authentic sandbox notification while <c>AllowSandbox</c> is off: 200, not stored.</summary>
    IgnoredSandbox,

    /// <summary>Authentic, but the transaction's product isn't in <c>Purchases:Apple:Products</c>: 200, not stored, alerted.</summary>
    IgnoredProduct,
}

/// <summary>
/// The ASSN V2 ingest (T-134 design note §1 steps 3-6), shared by <c>POST /v1/notifications/apple</c> and the daily
/// <c>Get Notification History</c> job so both dedupe on the same key. In order, each step only if the previous passed, and
/// nothing is written before step 6:
/// <list type="number">
/// <item>the outer JWS (pinned-root chain, ES256, at its own <c>signedDate</c> ≤ now + 5 min, ≤ 65 536 chars);</item>
/// <item>the claims: <c>version</c> "2.0", a UUID <c>notificationUUID</c>, type and subtype patterns, <c>signedDate</c> no older
/// than <see cref="MaxAge"/>; no <c>data</c> → <see cref="AppleIngestOutcome.IgnoredNoData"/>; <c>bundleId</c>; <c>environment</c>
/// (sandbox while <c>AllowSandbox</c> is off → <see cref="AppleIngestOutcome.IgnoredSandbox"/>);</item>
/// <item>the nested transaction and renewal JWSs the same way, which must agree with <c>data</c> on bundle, environment and
/// <c>originalTransactionId</c>; a product outside the allow-list → <see cref="AppleIngestOutcome.IgnoredProduct"/>;</item>
/// <item>the idempotent insert of the extracted columns.</item>
/// </list>
/// The ingest never calls Apple: a forged UUID can't spend our Apple budget.
/// </summary>
public sealed partial class AppleNotificationIngest(
    IAppleJwsVerifier jws,
    AppStoreCatalog catalog,
    IStoreNotificationInbox inbox,
    IPurchaseTelemetry purchaseTelemetry,
    IAppleNotificationTelemetry telemetry,
    TimeProvider clock)
{
    /// <summary>
    /// The oldest acceptable <c>signedDate</c>. Apple's last retry is about 6.5 days after the first attempt and the history job
    /// looks back 7 days. Invariant: shorter than the 90-day <c>store_notifications</c> retention, so every acceptable replay
    /// still hits the dedupe key.
    /// </summary>
    public static readonly TimeSpan MaxAge = TimeSpan.FromDays(10);

    /// <summary>The <c>store_notifications</c> retention (RetentionRules); <see cref="MaxAge"/> must stay below it.</summary>
    public static readonly TimeSpan Retention = TimeSpan.FromDays(90);

    /// <summary><c>notificationType</c> and <c>subtype</c> (the schema's CHECK pattern).</summary>
    public const string TypePattern = @"^[A-Z0-9_]{1,64}\z";

    /// <summary>The only ASSN version accepted.</summary>
    public const string Version = "2.0";

    /// <summary><c>last_error</c> of a reconcile-set row without a <c>signedTransactionInfo</c> (inserted processed).</summary>
    public const string NoTransaction = "NO_TRANSACTION";

    /// <summary>
    /// The types the worker re-reads (T-134 §2): the task's eight plus <c>REFUND_REVERSED</c>, <c>RENEWAL_EXTENDED</c>,
    /// <c>DID_CHANGE_RENEWAL_PREF</c>, <c>OFFER_REDEEMED</c> and <c>ONE_TIME_CHARGE</c>. Every other type (<c>TEST</c>,
    /// <c>CONSUMPTION_REQUEST</c>, ...) is recorded processed and ignored.
    /// <para>Provisional, PO to confirm (T-134 PO questions 3 and 4): <c>CONSUMPTION_REQUEST</c> is never answered (we never call
    /// <c>Send Consumption Information</c>, so no usage data leaves the server); <c>REFUND_REVERSED</c> is re-read like the others, and
    /// because the worker writes Apple's current answer (refunded/revoked are not sticky), Gold comes back automatically.</para>
    /// </summary>
    public static IReadOnlySet<string> ReconcileSet { get; } = new HashSet<string>(StringComparer.Ordinal)
    {
        "SUBSCRIBED", "DID_RENEW", "DID_FAIL_TO_RENEW", "EXPIRED", "GRACE_PERIOD_EXPIRED", "REFUND", "REVOKE",
        "DID_CHANGE_RENEWAL_STATUS", "REFUND_REVERSED", "RENEWAL_EXTENDED", "DID_CHANGE_RENEWAL_PREF", "OFFER_REDEEMED",
        "ONE_TIME_CHARGE",
    };

    public async Task<AppleIngestOutcome> IngestAsync(Sensitive<string> signedPayload, CancellationToken cancellationToken)
    {
        var (outcome, env, record) = Check(signedPayload, clock.GetUtcNow());
        if (record is not null)
        {
            outcome = await inbox.TryInsertAsync(record, cancellationToken) ? AppleIngestOutcome.Stored : AppleIngestOutcome.Duplicate;
        }

        telemetry.Ingested(env, Tag(outcome));
        return outcome;
    }

    public static string Tag(AppleIngestOutcome outcome) => outcome switch
    {
        AppleIngestOutcome.Stored => AssnTags.Stored,
        AppleIngestOutcome.Duplicate => AssnTags.Duplicate,
        AppleIngestOutcome.IgnoredNoData => AssnTags.IgnoredNoData,
        AppleIngestOutcome.IgnoredSandbox => AssnTags.IgnoredSandbox,
        AppleIngestOutcome.IgnoredProduct => AssnTags.IgnoredProduct,
        _ => AssnTags.Unauthorized,
    };

    /// <summary>SHA-256 of the UTF-8 <c>signedPayload</c> string (the history job computes the same value).</summary>
    public static byte[] Digest(string signedPayload) => SHA256.HashData(Encoding.UTF8.GetBytes(signedPayload));

    private (AppleIngestOutcome Outcome, string Env, StoreNotificationRecord? Record) Check(Sensitive<string> signedPayload, DateTimeOffset now)
    {
        var unauthorized = (AppleIngestOutcome.Unauthorized, AssnTags.EnvNone, (StoreNotificationRecord?)null);

        // 3. The outer JWS.
        AppleNotification notification;
        try
        {
            notification = jws.VerifyNotification(signedPayload, now);
            purchaseTelemetry.AppleJwsChecked(JwsSource.Notification, null);
        }
        catch (AppleJwsException error)
        {
            purchaseTelemetry.AppleJwsChecked(JwsSource.Notification, error.Reason);
            return unauthorized;
        }

        // 4. The notification's claims.
        if (!string.Equals(notification.Version, Version, StringComparison.Ordinal)
            || !Guid.TryParseExact(notification.NotificationUuid, "D", out var uuid)
            || notification.NotificationType is not { } type || !TypeRegex().IsMatch(type)
            || (notification.Subtype is { } subtype && !TypeRegex().IsMatch(subtype))
            || notification.SignedDate < now - MaxAge)
        {
            return unauthorized;
        }

        if (notification.Data is not { } data)
        {
            return (AppleIngestOutcome.IgnoredNoData, AssnTags.EnvNone, null);
        }

        if (catalog.BundleId.Length == 0 || !string.Equals(data.BundleId, catalog.BundleId, StringComparison.Ordinal))
        {
            return unauthorized;
        }

        var (environment, appleEnvironment, env) = data.Environment switch
        {
            "Production" => (PurchaseEnvironment.Production, AppleEnvironment.Production, AssnTags.EnvProduction),
            "Sandbox" => (PurchaseEnvironment.Sandbox, AppleEnvironment.Sandbox, AssnTags.EnvSandbox),
            _ => ((PurchaseEnvironment?)null, AppleEnvironment.Unknown, AssnTags.EnvNone),
        };
        if (environment is null)
        {
            return unauthorized;
        }

        if (environment == PurchaseEnvironment.Sandbox && !catalog.AllowSandbox)
        {
            return (AppleIngestOutcome.IgnoredSandbox, env, null);
        }

        // 5. The nested JWSs, validated the same way and bound to data.
        AppleTransaction? transaction = null;
        if (data.SignedTransactionInfo is { } signedTransaction)
        {
            try
            {
                transaction = jws.VerifyTransaction(signedTransaction, JwsSource.Notification, now);
                purchaseTelemetry.AppleJwsChecked(JwsSource.Notification, null);
            }
            catch (AppleJwsException error)
            {
                purchaseTelemetry.AppleJwsChecked(JwsSource.Notification, error.Reason);
                return (AppleIngestOutcome.Unauthorized, env, null);
            }

            if (!string.Equals(transaction.BundleId, data.BundleId, StringComparison.Ordinal)
                || transaction.Environment != appleEnvironment
                || !AppStoreVerification.IsTransactionId(transaction.OriginalTransactionId)
                || !AppStoreVerification.IsTransactionId(transaction.TransactionId))
            {
                return (AppleIngestOutcome.Unauthorized, env, null);
            }
        }

        if (data.SignedRenewalInfo is { } signedRenewal)
        {
            AppleRenewalInfo renewal;
            try
            {
                renewal = jws.VerifyRenewalInfo(signedRenewal, JwsSource.Notification, now);
                purchaseTelemetry.AppleJwsChecked(JwsSource.Notification, null);
            }
            catch (AppleJwsException error)
            {
                purchaseTelemetry.AppleJwsChecked(JwsSource.Notification, error.Reason);
                return (AppleIngestOutcome.Unauthorized, env, null);
            }

            // Without a transaction there is nothing to bind the renewal to; such a row is stored processed (NO_TRANSACTION).
            if ((renewal.OriginalTransactionId is { } renewalOriginal && transaction is not null
                    && !string.Equals(renewalOriginal.Reveal(), transaction.OriginalTransactionId!.Value.Reveal(), StringComparison.Ordinal))
                || (renewal.Environment != AppleEnvironment.Unknown && renewal.Environment != appleEnvironment))
            {
                return (AppleIngestOutcome.Unauthorized, env, null);
            }
        }

        if (transaction is not null && !catalog.TryGet(transaction.ProductId, out _))
        {
            return (AppleIngestOutcome.IgnoredProduct, env, null);
        }

        // 6. The extracted columns only.
        var reconcile = ReconcileSet.Contains(type);
        var record = new StoreNotificationRecord(
            Guid.CreateVersion7(),
            PurchaseStore.AppStore,
            uuid.ToString("D"),
            type,
            notification.Subtype,
            transaction?.ProductId,
            transaction?.OriginalTransactionId,
            environment.Value,
            notification.SignedDate,
            Digest(signedPayload.Reveal()),
            Processed: !reconcile || transaction is null,
            LastError: reconcile && transaction is null ? NoTransaction : null);
        return (AppleIngestOutcome.Stored, env, record);
    }

    [GeneratedRegex(TypePattern, RegexOptions.CultureInvariant)]
    private static partial Regex TypeRegex();
}
