using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Purchases;

/// <summary>T-131 design note §3-4: the iOS verify procedure over a fake JWS verifier, a fake App Store API and an in-memory table.</summary>
public class AppStoreVerificationTests
{
    private readonly AppleScript apple = new();
    private readonly FakePurchaseWriter writer = new();
    private readonly RecordingPurchaseTelemetry telemetry = new();
    private readonly FakeVerifyLimiter limiter = new();
    private readonly FixedClock clock = new(AppleScript.Now);
    private AppStoreCatalog catalog = AppleScript.Catalog();

    private AppStoreVerification Verifier => new(apple.Jws, apple.Api, catalog, writer, limiter, telemetry, clock);

    // AC 1: a JWS that fails verification, or the wrong app, product or shape, is final and costs no Apple call.

    [Theory]
    [InlineData(AppleJwsFailure.Malformed)]
    [InlineData(AppleJwsFailure.Alg)]
    [InlineData(AppleJwsFailure.Chain)]
    [InlineData(AppleJwsFailure.Oid)]
    [InlineData(AppleJwsFailure.Signature)]
    [InlineData(AppleJwsFailure.Payload)]
    public async Task AnAppJwsThatFailsVerificationIsTokenInvalidWithNoAppleCallAndNoRow(AppleJwsFailure failure)
    {
        apple.Jws.Failures["forged"] = failure;

        var result = await VerifyAsync("forged", Install());

        Assert.Equal(ErrorCodes.PurchaseTokenInvalid, result.ProblemCode);
        Assert.Empty(apple.Api.Calls);
        Assert.Equal(0, writer.Upserts);
        Assert.Equal((JwsSource.App, (AppleJwsFailure?)failure), telemetry.Jws.Single());
    }

    [Fact]
    public async Task AnotherAppsProductsOrKindsAreWrongAppWithNoAppleCall()
    {
        var install = Install();
        var otherBundle = apple.Purchase(Tx(install, bundleId: "com.example.other"));
        var unknownProduct = apple.Purchase(Tx(install, productId: "zaghlol_gold_weekly"));
        var wrongKind = apple.Purchase(Tx(install, productId: AppleScript.Lifetime, type: AppleProductType.AutoRenewable));

        foreach (var jws in new[] { otherBundle, unknownProduct, wrongKind })
        {
            Assert.Equal(ErrorCodes.PurchaseWrongApp, (await VerifyAsync(jws, install)).ProblemCode);
        }

        Assert.Empty(apple.Api.Calls);
        Assert.Equal(0, writer.Upserts);
    }

    [Fact]
    public async Task AnUnconfiguredBundleNeverMatches()
    {
        catalog = new AppStoreCatalog(string.Empty, AppleScript.Catalog().Products, true);
        var install = Install();

        var result = await VerifyAsync(apple.Purchase(Tx(install, bundleId: string.Empty)), install);

        Assert.Equal(ErrorCodes.PurchaseWrongApp, result.ProblemCode);
    }

    [Theory]
    [InlineData("12a4")]
    [InlineData("")]
    [InlineData("123456789012345678901234567890123")]
    [InlineData("１２３")]
    public async Task ATransactionIdThatIsNotDigitsIsTokenInvalidWithNoAppleCall(string transactionId)
    {
        var install = Install();
        var transaction = AppleScript.Tx(transactionId, AppleScript.NewId(), install);
        apple.Jws.Transactions["odd"] = transaction;

        Assert.Equal(ErrorCodes.PurchaseTokenInvalid, (await VerifyAsync("odd", install)).ProblemCode);
        Assert.Empty(apple.Api.Calls);
    }

    [Fact]
    public async Task AnXcodeOrUnknownEnvironmentIsTokenInvalid()
    {
        var install = Install();
        var jws = apple.Purchase(Tx(install, environment: AppleEnvironment.Unknown));

        Assert.Equal(ErrorCodes.PurchaseTokenInvalid, (await VerifyAsync(jws, install)).ProblemCode);
        Assert.Empty(apple.Api.Calls);
    }

    [Fact]
    public async Task AnAppleApiCopyThatFailsVerificationIs502AndAlerted()
    {
        var install = Install();
        var transaction = Tx(install);
        var jws = apple.Purchase(transaction);
        apple.Jws.Failures["api:" + Id(transaction)] = AppleJwsFailure.Signature;

        var error = await Assert.ThrowsAsync<StoreUnavailableException>(() => VerifyAsync(jws, install));

        Assert.Equal(StoreFailureKind.Store, error.Kind);
        Assert.Contains((JwsSource.Api, (AppleJwsFailure?)AppleJwsFailure.Signature), telemetry.Jws);
        Assert.Equal(0, writer.Upserts);
    }

    // AC 2: routed by the signed environment only; sandbox gated; 4040010 never retried on the other environment.

    [Theory]
    [InlineData(AppleEnvironment.Production, PurchaseEnvironment.Production)]
    [InlineData(AppleEnvironment.Sandbox, PurchaseEnvironment.Sandbox)]
    public async Task EveryAppleCallGoesToTheSignedEnvironmentOnly(AppleEnvironment signedEnvironment, PurchaseEnvironment expected)
    {
        var install = Install();
        var transaction = Tx(install, environment: signedEnvironment);
        var jws = apple.Purchase(transaction);
        apple.Status(transaction);

        var result = await VerifyAsync(jws, install);

        Assert.Equal(VerifyStatus.Active, result.Status);
        Assert.Equal(expected, result.Environment);
        Assert.Equal(2, apple.Api.Calls.Count);
        Assert.All(apple.Api.Calls, c => Assert.Equal(expected, c.Environment));
        Assert.All(apple.Api.Calls, c => Assert.Equal(StoreLane.Verify, c.Lane));
        Assert.Equal((PurchaseTags.AppStore, expected), telemetry.Environments.Single());
        Assert.Equal(expected, writer.Rows.Values.Single().Environment);
    }

    [Fact]
    public async Task SandboxWhileSandboxIsOffIsTokenInvalidWithNoAppleCall()
    {
        catalog = AppleScript.Catalog(allowSandbox: false);
        var install = Install();
        var jws = apple.Purchase(Tx(install, environment: AppleEnvironment.Sandbox));

        Assert.Equal(ErrorCodes.PurchaseTokenInvalid, (await VerifyAsync(jws, install)).ProblemCode);
        Assert.Empty(apple.Api.Calls);
    }

    [Fact]
    public async Task AnEnvironmentMismatchBetweenTheAppAndApplesCopyIs502AndAlerted()
    {
        var install = Install();
        var transaction = Tx(install);
        var jws = apple.Purchase(transaction, transaction with { Environment = AppleEnvironment.Sandbox });

        await Assert.ThrowsAsync<StoreUnavailableException>(() => VerifyAsync(jws, install));

        Assert.Contains((JwsSource.Api, (AppleJwsFailure?)AppleJwsFailure.Payload), telemetry.Jws);
        Assert.Equal(0, writer.Upserts);
    }

    [Theory]
    [InlineData(5, true)]
    [InlineData(9, true)]
    [InlineData(11, false)]
    [InlineData(60, false)]
    public async Task NotFoundIs502WithinTenMinutesOfSigningAndThenTokenInvalidAndNeverTriesTheOtherEnvironment(int minutesSinceSigned, bool retryable)
    {
        var install = Install();
        var transaction = Tx(install, signedDate: AppleScript.Now.AddMinutes(-minutesSinceSigned));
        apple.Jws.Transactions["app:x"] = transaction;

        if (retryable)
        {
            var error = await Assert.ThrowsAsync<StoreUnavailableException>(() => VerifyAsync("app:x", install));
            Assert.Equal(StoreFailureKind.Store, error.Kind);
        }
        else
        {
            Assert.Equal(ErrorCodes.PurchaseTokenInvalid, (await VerifyAsync("app:x", install)).ProblemCode);
        }

        var call = Assert.Single(apple.Api.Calls);
        Assert.Equal(PurchaseEnvironment.Production, call.Environment);
        Assert.Equal(0, writer.Upserts);
    }

    [Fact]
    public async Task AnInvalidTransactionIdAnswerIsTokenInvalid()
    {
        var install = Install();
        var jws = apple.Purchase(Tx(install));
        apple.Api.Errors[AppStoreApi.TransactionInfo] = new AppStoreApiException(AppStoreApi.TransactionInfo, AppStoreCallOutcome.ClientError, 400, AppStoreApiException.InvalidTransactionId);

        Assert.Equal(ErrorCodes.PurchaseTokenInvalid, (await VerifyAsync(jws, install)).ProblemCode);
    }

    [Theory]
    [InlineData(AppStoreCallOutcome.AuthError, 401, null, StoreFailureKind.Store)]
    [InlineData(AppStoreCallOutcome.RateLimited, 429, null, StoreFailureKind.Store)]
    [InlineData(AppStoreCallOutcome.ServerError, 503, null, StoreFailureKind.Store)]
    [InlineData(AppStoreCallOutcome.Timeout, null, null, StoreFailureKind.Store)]
    [InlineData(AppStoreCallOutcome.CircuitOpen, null, null, StoreFailureKind.Store)]
    [InlineData(AppStoreCallOutcome.ClientError, 400, 4000005, StoreFailureKind.Store)]
    [InlineData(AppStoreCallOutcome.ClientError, 404, 4040001, StoreFailureKind.Store)]
    [InlineData(AppStoreCallOutcome.ClientError, 409, null, StoreFailureKind.Store)]
    [InlineData(AppStoreCallOutcome.BudgetDenied, null, null, StoreFailureKind.Budget)]
    public async Task EveryOtherAppleAnswerIsAnOutageNotARejection(AppStoreCallOutcome outcome, int? status, int? code, StoreFailureKind kind)
    {
        var install = Install();
        var jws = apple.Purchase(Tx(install));
        apple.Api.Errors[AppStoreApi.TransactionInfo] = new AppStoreApiException(AppStoreApi.TransactionInfo, outcome, status, code, TimeSpan.FromSeconds(42));

        var error = await Assert.ThrowsAsync<StoreUnavailableException>(() => VerifyAsync(jws, install));

        Assert.Equal(kind, error.Kind);
        Assert.Equal(42, error.RetryAfterSeconds);
        Assert.Equal(0, writer.Upserts);
    }

    [Fact]
    public async Task TheStatusCallFailingAfterTheTransactionWasFoundIsAnOutage()
    {
        var install = Install();
        var transaction = Tx(install);
        var jws = apple.Purchase(transaction);
        apple.Api.Errors[AppStoreApi.SubscriptionStatuses] = new AppStoreApiException(AppStoreApi.SubscriptionStatuses, AppStoreCallOutcome.ClientError, 404, AppStoreApiException.TransactionIdNotFound);

        await Assert.ThrowsAsync<StoreUnavailableException>(() => VerifyAsync(jws, install));
        Assert.Equal(0, writer.Upserts);
    }

    [Fact]
    public async Task ThePerInstallLimitIs503BeforeAnyAppleCallAndRestoreIsNotCounted()
    {
        var install = Install();
        var transaction = Tx(install);
        var jws = apple.Purchase(transaction);
        apple.Status(transaction);
        limiter.Allow = false;

        var error = await Assert.ThrowsAsync<StoreUnavailableException>(() => VerifyAsync(jws, install));

        Assert.Equal(StoreFailureKind.Budget, error.Kind);
        Assert.Empty(apple.Api.Calls);
        var restored = await Verifier.VerifyAsync(new AppStorePurchaseRef(new Sensitive<string>(jws)), Install(), BindingCheck.Skip, CancellationToken.None);
        Assert.Equal(VerifyStatus.Active, restored.Status);
        Assert.Equal(1, limiter.Calls);
    }

    // AC 3: the binding, checked on Apple's copy.

    [Fact]
    public async Task AnotherInstallsBindingNoneOrAFamilySharedPurchaseIsNotOwnedAndNothingIsWritten()
    {
        var buyer = Install();
        var caller = Install();
        var foreign = Tx(buyer);
        var unbound = Tx(boundTo: null);
        var shared = Tx(caller, ownership: AppleOwnershipType.FamilyShared);
        foreach (var transaction in new[] { foreign, unbound, shared })
        {
            apple.Status(transaction);
            Assert.Equal(ErrorCodes.PurchaseNotOwned, (await VerifyAsync(apple.Purchase(transaction), caller)).ProblemCode);
        }

        Assert.Equal(0, writer.Upserts);
        Assert.Equal(0, apple.Api.CallsTo(AppStoreApi.SubscriptionStatuses));
    }

    [Fact]
    public async Task TheBindingIsReadFromApplesCopyNotTheAppsJws()
    {
        var buyer = Install();
        var caller = Install();
        var appCopy = Tx(caller);
        var jws = apple.Purchase(appCopy, appCopy with { AppAccountToken = new Sensitive<string>(StoreBindingRef.Compute(buyer)) });
        apple.Status(appCopy);

        Assert.Equal(ErrorCodes.PurchaseNotOwned, (await VerifyAsync(jws, caller)).ProblemCode);
    }

    [Fact]
    public async Task AnUpperCaseAppAccountTokenIsTheSameUuidAndIsStoredCanonical()
    {
        var install = Install();
        var transaction = Tx(install, appAccountToken: StoreBindingRef.Compute(install).ToUpperInvariant());
        apple.Status(transaction);

        var result = await VerifyAsync(apple.Purchase(transaction), install);

        Assert.Equal(VerifyStatus.Active, result.Status);
        Assert.Equal(StoreBindingRef.Compute(install), writer.Rows.Values.Single().ObfuscatedInstallRef);
    }

    [Fact]
    public async Task RestoreSkipsOnlyTheBindingAndNeverSetsTheBuyingInstallOrANewPayment()
    {
        var transaction = Tx(Install());
        var jws = apple.Purchase(transaction);
        apple.Status(transaction);

        var result = await Verifier.VerifyAsync(new AppStorePurchaseRef(new Sensitive<string>(jws)), Install(), BindingCheck.Skip, CancellationToken.None);

        Assert.Equal(VerifyStatus.Active, result.Status);
        Assert.False(result.IsNewPayment);
        Assert.All(apple.Api.Calls, c => Assert.Equal(StoreLane.Restore, c.Lane));
        var row = writer.Rows.Values.Single();
        Assert.Null(row.InstallId);
        Assert.Null(row.LastPaymentAt);
        Assert.Null(writer.Seen.Single().NewPaymentAt);
    }

    // The state table (§3 step 5), from Apple's copies only.

    [Theory]
    [InlineData(1, 1, StoredPurchaseState.Active, VerifyStatus.Active)]
    [InlineData(1, 0, StoredPurchaseState.CanceledActive, VerifyStatus.Active)]
    [InlineData(3, 1, StoredPurchaseState.OnHold, VerifyStatus.Expired)]
    [InlineData(2, 0, StoredPurchaseState.Expired, VerifyStatus.Expired)]
    public async Task SubscriptionStatesMapRowByRow(int status, int autoRenew, StoredPurchaseState stored, VerifyStatus verify)
    {
        var install = Install();
        var expires = AppleScript.Now.AddDays(status == 2 ? -3 : 20);
        var transaction = Tx(install, expiresDate: expires);
        apple.Status(transaction, status, autoRenew);

        var result = await VerifyAsync(apple.Purchase(transaction), install);

        Assert.Equal(verify, result.Status);
        var row = writer.Rows.Values.Single();
        Assert.Equal(stored, row.State);
        Assert.Equal(expires, row.ExpiresAt);
        Assert.True(row.Acknowledged);
        Assert.Equal(StoreBindingRef.Compute(install), row.ObfuscatedInstallRef);
        Assert.Equal(install, row.InstallId);
    }

    [Fact]
    public async Task GraceUsesTheRenewalInfosGraceExpiry()
    {
        var install = Install();
        var grace = AppleScript.Now.AddDays(6);
        var transaction = Tx(install, expiresDate: AppleScript.Now.AddDays(-1));
        apple.Status(transaction, 4, 1, grace);

        var result = await VerifyAsync(apple.Purchase(transaction), install);

        Assert.Equal(VerifyStatus.Active, result.Status);
        Assert.Equal(StoredPurchaseState.InGrace, writer.Rows.Values.Single().State);
        Assert.Equal(grace, result.ExpiresAt);
    }

    [Theory]
    [InlineData(1, StoredPurchaseState.Refunded)]
    [InlineData(null, StoredPurchaseState.Revoked)]
    public async Task ARevokedSubscriptionIsRefundedOrRevokedAndKeepsTheStoredExpiry(int? reason, StoredPurchaseState expected)
    {
        var install = Install();
        var original = AppleScript.NewId();
        var first = AppleScript.Tx(AppleScript.NewId(), original, install, expiresDate: AppleScript.Now.AddDays(20));
        apple.Status(first);
        await VerifyAsync(apple.Purchase(first), install);
        var storedExpiry = writer.Rows.Values.Single().ExpiresAt;

        clock.Now = clock.Now.AddMinutes(1);
        var revoked = first with { RevocationDate = AppleScript.Now, RevocationReason = reason, ExpiresDate = AppleScript.Now.AddDays(99) };
        apple.Status(revoked, 5);
        apple.Purchase(revoked);
        var result = await VerifyAsync("app:" + Id(first), install);

        Assert.Equal(VerifyStatus.Refunded, result.Status);
        Assert.Equal(expected, writer.Rows.Values.Single().State);
        Assert.Equal(storedExpiry, writer.Rows.Values.Single().ExpiresAt);
        Assert.True(writer.Seen.Last().KeepStoredExpiry);
    }

    [Fact]
    public async Task LifetimeIsActiveWithoutExpiryOrRefundedWhenRevoked()
    {
        var install = Install();
        var active = Tx(install, productId: AppleScript.Lifetime, type: AppleProductType.NonConsumable);
        var refunded = Tx(install, productId: AppleScript.Lifetime, type: AppleProductType.NonConsumable, revocationDate: AppleScript.Now, revocationReason: 0);

        var a = await VerifyAsync(apple.Purchase(active), install);
        var r = await VerifyAsync(apple.Purchase(refunded), install);

        Assert.Equal(VerifyStatus.Active, a.Status);
        Assert.Equal(GoldPlan.Lifetime, a.Plan);
        Assert.Null(a.ExpiresAt);
        Assert.Equal(VerifyStatus.Refunded, r.Status);
        Assert.Equal(0, apple.Api.CallsTo(AppStoreApi.SubscriptionStatuses));
        Assert.Equal(2, apple.Api.CallsTo(AppStoreApi.TransactionInfo));
    }

    [Theory]
    [InlineData(1, 1, false)]
    [InlineData(1, null, true)]
    [InlineData(1, 7, true)]
    [InlineData(4, 1, true)]
    [InlineData(3, 1, false)]
    [InlineData(2, 1, false)]
    [InlineData(6, 1, true)]
    [InlineData(null, 1, true)]
    public async Task AnEntitlingRowWithoutItsExpiryOrAStatusOutsideTheTableIs502AndWritesNothing(int? status, int? autoRenew, bool withExpiry)
    {
        var install = Install();
        var transaction = Tx(install);
        if (!withExpiry && status is 1 or 2 or 3)
        {
            transaction = transaction with { ExpiresDate = null };
        }

        apple.Status(transaction, status ?? 0, autoRenew, AppleScript.Now.AddDays(3));
        if (status is null)
        {
            var original = transaction.OriginalTransactionId!.Value;
            apple.Api.Statuses[(PurchaseEnvironment.Production, Id(transaction))] =
                [new AppleLastTransaction(null, original, new Sensitive<string>("latest:" + original.Reveal()), new Sensitive<string>("renewal:" + original.Reveal()))];
        }

        if (status == 4)
        {
            // Billing grace without gracePeriodExpiresDate.
            apple.Jws.Renewals["renewal:" + transaction.OriginalTransactionId!.Value.Reveal()] = new AppleRenewalInfo(transaction.OriginalTransactionId, AppleEnvironment.Production, 1, null);
        }

        await Assert.ThrowsAsync<StoreUnavailableException>(() => VerifyAsync(apple.Purchase(transaction), install));
        Assert.Equal(0, writer.Upserts);
    }

    [Fact]
    public async Task AStatusAnswerWithoutOurSubscriptionOrWithAnotherAppsLatestTransactionIs502()
    {
        var install = Install();
        var transaction = Tx(install);
        var jws = apple.Purchase(transaction);
        apple.Api.Statuses[(PurchaseEnvironment.Production, Id(transaction))] = [];

        await Assert.ThrowsAsync<StoreUnavailableException>(() => VerifyAsync(jws, install));

        apple.Status(transaction with { BundleId = "com.example.other" }, forTransactionId: Id(transaction));
        await Assert.ThrowsAsync<StoreUnavailableException>(() => VerifyAsync(jws, install));

        apple.Status(transaction with { ProductId = "zaghlol_gold_weekly" }, forTransactionId: Id(transaction));
        await Assert.ThrowsAsync<StoreUnavailableException>(() => VerifyAsync(jws, install));
        Assert.Equal(0, writer.Upserts);
    }

    [Fact]
    public async Task AnUpgradeRePlansTheRowFromTheLatestTransaction()
    {
        var install = Install();
        var original = AppleScript.NewId();
        var monthly = AppleScript.Tx(AppleScript.NewId(), original, install, AppleScript.Monthly);
        apple.Status(monthly);
        await VerifyAsync(apple.Purchase(monthly), install);
        Assert.Equal(GoldPlan.Monthly, writer.Rows.Values.Single().Plan);

        clock.Now = clock.Now.AddMinutes(5);
        var yearly = AppleScript.Tx(AppleScript.NewId(), original, install, AppleScript.Yearly, purchaseDate: AppleScript.Now.AddMinutes(4));
        apple.Status(yearly);
        var result = await VerifyAsync(apple.Purchase(yearly), install);

        Assert.Equal(GoldPlan.Yearly, result.Plan);
        var row = Assert.Single(writer.Rows.Values);
        Assert.Equal(GoldPlan.Yearly, row.Plan);
        Assert.Equal(AppleScript.Yearly, row.ProductId);
    }

    // AC 4: new payments.

    [Fact]
    public async Task AFirstPurchaseAndAnUpgradeAreNewPaymentsAndTheirReVerifiesAreNot()
    {
        var install = Install();
        var original = AppleScript.NewId();
        var first = AppleScript.Tx(AppleScript.NewId(), original, install, AppleScript.Monthly);
        apple.Status(first);
        var firstJws = apple.Purchase(first);

        Assert.True((await VerifyAsync(firstJws, install)).IsNewPayment);
        clock.Now = clock.Now.AddMinutes(1);
        Assert.False((await VerifyAsync(firstJws, install)).IsNewPayment);

        clock.Now = clock.Now.AddMinutes(1);
        var upgrade = AppleScript.Tx(AppleScript.NewId(), original, install, AppleScript.Yearly, purchaseDate: AppleScript.Now.AddMinutes(1));
        apple.Status(upgrade);
        var upgradeJws = apple.Purchase(upgrade);

        Assert.True((await VerifyAsync(upgradeJws, install)).IsNewPayment);
        clock.Now = clock.Now.AddMinutes(1);
        Assert.False((await VerifyAsync(upgradeJws, install)).IsNewPayment);
        Assert.Equal(upgrade.PurchaseDate, writer.Rows.Values.Single().LastPaymentAt);
    }

    [Fact]
    public async Task ARenewalOrAnOlderPurchaseIsNotANewPayment()
    {
        var install = Install();
        var original = AppleScript.NewId();
        var current = AppleScript.Tx(AppleScript.NewId(), original, install, purchaseDate: AppleScript.Now.AddMinutes(-1));
        apple.Status(current);
        Assert.True((await VerifyAsync(apple.Purchase(current), install)).IsNewPayment);

        var renewal = AppleScript.Tx(AppleScript.NewId(), original, install, purchaseDate: AppleScript.Now, reason: AppleTransactionReason.Renewal);
        var older = AppleScript.Tx(AppleScript.NewId(), original, install, purchaseDate: AppleScript.Now.AddDays(-30));
        foreach (var transaction in new[] { renewal, older })
        {
            clock.Now = clock.Now.AddMinutes(1);
            apple.Status(transaction);
            Assert.False((await VerifyAsync(apple.Purchase(transaction), install)).IsNewPayment);
        }

        Assert.Null(writer.Seen[1].NewPaymentAt);
        Assert.NotNull(writer.Seen[2].NewPaymentAt);
    }

    [Fact]
    public async Task ARestoreBeforeTheVerifyCannotSwallowTheNewPayment()
    {
        var install = Install();
        var transaction = Tx(install);
        var jws = apple.Purchase(transaction);
        apple.Status(transaction);

        await Verifier.VerifyAsync(new AppStorePurchaseRef(new Sensitive<string>(jws)), Install(), BindingCheck.Skip, CancellationToken.None);
        clock.Now = clock.Now.AddMinutes(1);

        Assert.True((await VerifyAsync(jws, install)).IsNewPayment);
    }

    [Fact]
    public async Task TwoConcurrentVerifiesOfOnePaymentFlagItExactlyOnce()
    {
        var install = Install();
        var transaction = Tx(install);
        var jws = apple.Purchase(transaction);
        apple.Status(transaction);

        var results = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ => Task.Run(() => VerifyAsync(jws, install))));

        Assert.Equal(1, results.Count(r => r.IsNewPayment));
    }

    [Fact]
    public async Task EachVerifierTakesOnlyItsOwnStoresPurchase()
    {
        var play = new PlayVerification(new FakePlayDeveloperApi(), Play.Catalog, writer, telemetry, clock);

        await Assert.ThrowsAsync<ArgumentException>(() =>
            Verifier.VerifyAsync(new PlayPurchaseRef(Play.Yearly, new Sensitive<string>("t")), Install(), BindingCheck.RequireCaller, CancellationToken.None));
        await Assert.ThrowsAsync<ArgumentException>(() =>
            play.VerifyAsync(new AppStorePurchaseRef(new Sensitive<string>("x.y.z")), Install(), BindingCheck.RequireCaller, CancellationToken.None));
    }

    private static InstallId Install() => InstallId.FromGuid(Guid.NewGuid());

    private static string Id(AppleTransaction transaction) => transaction.TransactionId!.Value.Reveal();

    private static AppleTransaction Tx(
        InstallId? boundTo,
        string productId = AppleScript.Yearly,
        AppleEnvironment environment = AppleEnvironment.Production,
        AppleProductType type = AppleProductType.AutoRenewable,
        AppleOwnershipType ownership = AppleOwnershipType.Purchased,
        DateTimeOffset? expiresDate = null,
        DateTimeOffset? revocationDate = null,
        int? revocationReason = null,
        string bundleId = AppleScript.Bundle,
        DateTimeOffset? signedDate = null,
        string? appAccountToken = null) =>
        AppleScript.Tx(
            AppleScript.NewId(),
            AppleScript.NewId(),
            boundTo,
            productId,
            environment,
            type,
            ownership,
            expiresDate: expiresDate,
            revocationDate: revocationDate,
            revocationReason: revocationReason,
            bundleId: bundleId,
            signedDate: signedDate,
            appAccountToken: appAccountToken);

    private Task<StoreVerificationResult> VerifyAsync(string jws, InstallId caller) =>
        Verifier.VerifyAsync(new AppStorePurchaseRef(new Sensitive<string>(jws)), caller, BindingCheck.RequireCaller, CancellationToken.None);
}
