using System.Security.Cryptography;
using System.Text;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Purchases;

/// <summary>
/// T-134 design note §1 steps 3-6: the ingest's order of checks, what it stores, and the 200-not-stored cases. The JWS verifier is
/// the fake (its pipeline has its own tests with the test PKI); nothing here can call Apple.
/// </summary>
public class AppleNotificationIngestTests
{
    private static readonly DateTimeOffset Now = AppleScript.Now;

    private readonly FakeAppleJwsVerifier jws = new();
    private readonly FakeInbox inbox = new();
    private readonly RecordingPurchaseTelemetry purchaseTelemetry = new();
    private readonly RecordingNotificationTelemetry telemetry = new();

    [Fact]
    public async Task AReconcileSetNotificationStoresExactlyTheExtractedColumns()
    {
        var (payload, original) = Script("REFUND", null, out var uuid);

        var outcome = await Ingest().IngestAsync(new Sensitive<string>(payload), CancellationToken.None);

        Assert.Equal(AppleIngestOutcome.Stored, outcome);
        var row = Assert.Single(inbox.Rows.Values);
        Assert.Equal(7, row.Id.Version);
        Assert.Equal(PurchaseStore.AppStore, row.Store);
        Assert.Equal(uuid.ToString("D"), row.ExternalId);
        Assert.Equal("REFUND", row.Type);
        Assert.Null(row.Subtype);
        Assert.Equal(AppleScript.Yearly, row.ProductId);
        Assert.Equal(original, row.StoreKey?.Reveal());
        Assert.Equal(PurchaseEnvironment.Production, row.Environment);
        Assert.Equal(Now.AddMinutes(-2), row.EventTime);
        Assert.Equal(SHA256.HashData(Encoding.UTF8.GetBytes(payload)), row.PayloadDigest);
        Assert.False(row.Processed);
        Assert.Null(row.LastError);
        Assert.Contains((AssnTags.EnvProduction, AssnTags.Stored), telemetry.Ingests);
        Assert.All(purchaseTelemetry.Jws, j => Assert.Equal(JwsSource.Notification, j.Source));
        Assert.Equal(3, purchaseTelemetry.Jws.Count);
    }

    [Fact]
    public async Task AnUpperCaseUuidIsStoredCanonicalAndTheSameUuidTwiceIsADuplicate()
    {
        var (payload, _) = Script("DID_RENEW", null, out var uuid, uuidText: g => g.ToString("D").ToUpperInvariant());
        var ingest = Ingest();

        Assert.Equal(AppleIngestOutcome.Stored, await ingest.IngestAsync(new Sensitive<string>(payload), CancellationToken.None));
        Assert.Equal(AppleIngestOutcome.Duplicate, await ingest.IngestAsync(new Sensitive<string>(payload), CancellationToken.None));

        Assert.Equal(uuid.ToString("D"), Assert.Single(inbox.Rows.Values).ExternalId);
        Assert.Contains((AssnTags.EnvProduction, AssnTags.Duplicate), telemetry.Ingests);
    }

    [Fact]
    public async Task ATestNotificationIsStoredAlreadyProcessed()
    {
        var (payload, _) = Script("TEST", null, out _, withTransaction: false);

        Assert.Equal(AppleIngestOutcome.Stored, await Ingest().IngestAsync(new Sensitive<string>(payload), CancellationToken.None));

        var row = Assert.Single(inbox.Rows.Values);
        Assert.True(row.Processed);
        Assert.Null(row.LastError);
        Assert.Null(row.StoreKey);
    }

    [Theory]
    [InlineData("CONSUMPTION_REQUEST")]
    [InlineData("PRICE_INCREASE")]
    [InlineData("SOMETHING_APPLE_ADDS")]
    public async Task ATypeOutsideTheReconcileSetIsStoredProcessedAndIgnored(string type)
    {
        var (payload, _) = Script(type, null, out _);

        Assert.Equal(AppleIngestOutcome.Stored, await Ingest().IngestAsync(new Sensitive<string>(payload), CancellationToken.None));
        Assert.True(Assert.Single(inbox.Rows.Values).Processed);
    }

    [Fact]
    public async Task AReconcileSetRowWithoutATransactionIsStoredProcessedWithNoTransaction()
    {
        var (payload, _) = Script("EXPIRED", "VOLUNTARY", out _, withTransaction: false);

        Assert.Equal(AppleIngestOutcome.Stored, await Ingest().IngestAsync(new Sensitive<string>(payload), CancellationToken.None));

        var row = Assert.Single(inbox.Rows.Values);
        Assert.True(row.Processed);
        Assert.Equal(AppleNotificationIngest.NoTransaction, row.LastError);
    }

    [Fact]
    public async Task NoDataIsTwoHundredAndNotStored()
    {
        jws.Notifications["nodata"] = new AppleNotification("RENEWAL_EXTENSION", "SUMMARY", Guid.NewGuid().ToString("D"), "2.0", Now, null);

        Assert.Equal(AppleIngestOutcome.IgnoredNoData, await Ingest().IngestAsync(new Sensitive<string>("nodata"), CancellationToken.None));
        Assert.Equal(0, inbox.Calls);
        Assert.Contains((AssnTags.EnvNone, AssnTags.IgnoredNoData), telemetry.Ingests);
    }

    [Fact]
    public async Task ASandboxNotificationWhileSandboxIsOffIsTwoHundredAndNotStored()
    {
        var (payload, _) = Script("SUBSCRIBED", "INITIAL_BUY", out _, environment: "Sandbox");

        Assert.Equal(AppleIngestOutcome.IgnoredSandbox, await Ingest(allowSandbox: false).IngestAsync(new Sensitive<string>(payload), CancellationToken.None));
        Assert.Equal(0, inbox.Calls);
        Assert.Contains((AssnTags.EnvSandbox, AssnTags.IgnoredSandbox), telemetry.Ingests);
    }

    [Fact]
    public async Task ASandboxNotificationWhileSandboxIsOnIsStoredAsSandbox()
    {
        var (payload, _) = Script("SUBSCRIBED", "INITIAL_BUY", out _, environment: "Sandbox");

        Assert.Equal(AppleIngestOutcome.Stored, await Ingest(allowSandbox: true).IngestAsync(new Sensitive<string>(payload), CancellationToken.None));
        Assert.Equal(PurchaseEnvironment.Sandbox, Assert.Single(inbox.Rows.Values).Environment);
    }

    [Fact]
    public async Task AProductOutsideTheAllowListIsTwoHundredNotStoredAndCounted()
    {
        var (payload, _) = Script("DID_RENEW", null, out _, productId: "some_other_product");

        Assert.Equal(AppleIngestOutcome.IgnoredProduct, await Ingest().IngestAsync(new Sensitive<string>(payload), CancellationToken.None));
        Assert.Equal(0, inbox.Calls);
        Assert.Contains((AssnTags.EnvProduction, AssnTags.IgnoredProduct), telemetry.Ingests);
    }

    [Fact]
    public async Task ExactlyTenDaysOldIsAcceptedAndOneMinuteMoreIsNot()
    {
        var (fresh, _) = Script("DID_RENEW", null, out _, signedDate: Now - AppleNotificationIngest.MaxAge);
        var (stale, _) = Script("DID_RENEW", null, out _, signedDate: Now - AppleNotificationIngest.MaxAge - TimeSpan.FromMinutes(1));

        Assert.Equal(AppleIngestOutcome.Stored, await Ingest().IngestAsync(new Sensitive<string>(fresh), CancellationToken.None));
        Assert.Equal(AppleIngestOutcome.Unauthorized, await Ingest().IngestAsync(new Sensitive<string>(stale), CancellationToken.None));
    }

    [Fact]
    public void TheAcceptanceWindowIsShorterThanTheRetention()
    {
        // T-134 §1 step 4 invariant: every acceptable replay still hits the dedupe key.
        Assert.True(AppleNotificationIngest.MaxAge < AppleNotificationIngest.Retention);
        Assert.True(AppleNotificationIngest.MaxAge > AppleNotificationHistoryJob.LookBack);
    }

    public static TheoryData<string> Forgeries => new()
    {
        "outer_signature", "version", "uuid", "uuid_braces", "type_lower", "type_long", "subtype_bad", "bundle", "bundle_everywhere", "env_xcode", "env_missing",
        "tx_signature", "tx_env", "tx_bundle", "tx_id", "tx_original_id", "renewal_signature", "renewal_original", "renewal_env",
    };

    [Theory]
    [MemberData(nameof(Forgeries))]
    public async Task EveryFailedCheckIsUnauthorizedWithNothingStored(string forgery)
    {
        var payload = Forge(forgery);

        Assert.Equal(AppleIngestOutcome.Unauthorized, await Ingest().IngestAsync(new Sensitive<string>(payload), CancellationToken.None));
        Assert.Equal(0, inbox.Calls);
        Assert.Contains(telemetry.Ingests, i => i.Outcome == AssnTags.Unauthorized);
    }

    [Fact]
    public async Task AnEmptyBundleConfigurationAcceptsNothing()
    {
        var (payload, _) = Script("REFUND", null, out _);
        var catalog = new AppStoreCatalog(string.Empty, AppleScript.Catalog().Products, true);
        var ingest = new AppleNotificationIngest(jws, catalog, inbox, purchaseTelemetry, telemetry, new FixedClock(Now));

        Assert.Equal(AppleIngestOutcome.Unauthorized, await ingest.IngestAsync(new Sensitive<string>(payload), CancellationToken.None));
    }

    private AppleNotificationIngest Ingest(bool allowSandbox = true) =>
        new(jws, AppleScript.Catalog(allowSandbox), inbox, purchaseTelemetry, telemetry, new FixedClock(Now));

    private (string Payload, string Original) Script(
        string type,
        string? subtype,
        out Guid uuid,
        bool withTransaction = true,
        string environment = "Production",
        string productId = AppleScript.Yearly,
        DateTimeOffset? signedDate = null,
        Func<Guid, string>? uuidText = null,
        string version = "2.0",
        string bundle = AppleScript.Bundle,
        AppleEnvironment? transactionEnvironment = null,
        string? transactionBundle = null,
        string? transactionId = null,
        string? originalId = null,
        string? renewalOriginal = null,
        AppleEnvironment? renewalEnvironment = null)
    {
        uuid = Guid.NewGuid();
        var key = "n:" + uuid;
        var appleEnvironment = environment == "Sandbox" ? AppleEnvironment.Sandbox : AppleEnvironment.Production;
        var tx = transactionId ?? AppleScript.NewId();
        var original = originalId ?? AppleScript.NewId();
        Sensitive<string>? signedTransaction = null;
        Sensitive<string>? signedRenewal = null;
        if (withTransaction)
        {
            jws.Transactions["ntx:" + uuid] = AppleScript.Tx(
                tx,
                original,
                null,
                productId,
                transactionEnvironment ?? appleEnvironment,
                bundleId: transactionBundle ?? AppleScript.Bundle,
                signedDate: Now.AddMinutes(-2));
            jws.Renewals["nren:" + uuid] = new AppleRenewalInfo(new Sensitive<string>(renewalOriginal ?? original), renewalEnvironment ?? appleEnvironment, 1, null);
            signedTransaction = new Sensitive<string>("ntx:" + uuid);
            signedRenewal = new Sensitive<string>("nren:" + uuid);
        }

        jws.Notifications[key] = new AppleNotification(
            type,
            subtype,
            (uuidText ?? (g => g.ToString("D")))(uuid),
            version,
            signedDate ?? Now.AddMinutes(-2),
            new AppleNotificationData(bundle, environment, 1, signedTransaction, signedRenewal));
        return (key, original);
    }

    private string Forge(string forgery)
    {
        switch (forgery)
        {
            case "outer_signature":
                jws.Failures["forged"] = AppleJwsFailure.Signature;
                return "forged";
            case "version":
                return Script("REFUND", null, out _, version: "1.0").Payload;
            case "uuid":
                return Script("REFUND", null, out _, uuidText: _ => "not-a-uuid").Payload;
            case "uuid_braces":
                return Script("REFUND", null, out _, uuidText: g => g.ToString("B")).Payload;
            case "type_lower":
                return Script("refund", null, out _).Payload;
            case "type_long":
                return Script(new string('A', 65), null, out _).Payload;
            case "subtype_bad":
                return Script("REFUND", "bad subtype", out _).Payload;
            case "bundle":
                return Script("REFUND", null, out _, bundle: "com.other.app").Payload;
            case "bundle_everywhere":
                // Another app's genuine notification: data and transaction agree on the other bundle.
                return Script("REFUND", null, out _, bundle: "com.other.app", transactionBundle: "com.other.app").Payload;
            case "env_xcode":
                return Script("REFUND", null, out _, environment: "Xcode").Payload;
            case "env_missing":
                var (p, _) = Script("REFUND", null, out var u);
                var n = jws.Notifications[p];
                jws.Notifications[p] = n with { Data = n.Data! with { Environment = null } };
                return p;
            case "tx_signature":
                var (q, _) = Script("REFUND", null, out var v);
                jws.Failures["ntx:" + v] = AppleJwsFailure.Signature;
                return q;
            case "tx_env":
                return Script("REFUND", null, out _, transactionEnvironment: AppleEnvironment.Sandbox).Payload;
            case "tx_bundle":
                return Script("REFUND", null, out _, transactionBundle: "com.other.app").Payload;
            case "tx_id":
                return Script("REFUND", null, out _, transactionId: "12a4").Payload;
            case "tx_original_id":
                return Script("REFUND", null, out _, originalId: "٣٤٥٦٧").Payload;
            case "renewal_signature":
                var (r, _) = Script("REFUND", null, out var w);
                jws.Failures["nren:" + w] = AppleJwsFailure.Chain;
                return r;
            case "renewal_original":
                return Script("REFUND", null, out _, renewalOriginal: "2999999999999999").Payload;
            case "renewal_env":
                return Script("REFUND", null, out _, renewalEnvironment: AppleEnvironment.Sandbox).Payload;
            default:
                throw new ArgumentOutOfRangeException(nameof(forgery));
        }
    }
}
