using System.Security.Cryptography;
using System.Text;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Purchases;

/// <summary>T-133 design note §4: the voided job and the expiry sweep only enqueue rows, idempotently, and never store unknown tokens.</summary>
public class PlayReconciliationJobTests
{
    private readonly FixedClock clock = new(Play.Now);
    private readonly FakePlayDeveloperApi play = new();
    private readonly RecordingPlayTelemetry telemetry = new();
    private readonly FakePlayNotificationStore store;

    public PlayReconciliationJobTests() => store = new FakePlayNotificationStore(clock);

    private PlayVoidedReconcileJob Voided => new(store, store, play, Play.Catalog, telemetry, clock);

    private PlayExpirySweepJob Sweep => new(store, store, telemetry, clock);

    private static PlayVoidedPurchase Void(string token, string orderId = "GPA.1234-5678-9012-34567", long? millis = null) =>
        new(new Sensitive<string>(token), new Sensitive<string>(orderId), millis ?? Play.Now.AddDays(-2).ToUnixTimeMilliseconds());

    [Fact]
    public async Task TheVoidedJobAsksForTheLast30DaysLessAnHourOnTheNotificationLane()
    {
        await Voided.RunOnceAsync(CancellationToken.None);

        var request = Assert.Single(play.VoidedRequests);
        Assert.Equal(Play.Now - TimeSpan.FromDays(30) + TimeSpan.FromHours(1), request.From);
        Assert.Equal(Play.Now, request.Until);
        Assert.Null(request.PageToken);
        Assert.Equal(StoreLane.Notification, request.Lane);
        Assert.Equal([PlayVoidedReconcileJob.LockName], store.LocksTaken);
        Assert.Equal((RtdnTags.StepVoided, RtdnTags.ReconcileOk), Assert.Single(telemetry.Reconciles));
    }

    [Fact]
    public async Task KnownVoidsAreEnqueuedOncePerOrderAndUnknownTokensAreNeverStored()
    {
        var known = Play.NewToken();
        store.AddPurchase(known, Play.Yearly, StoredPurchaseState.Active);
        var renewalVoid = Void(known, "GPA.1234-5678-9012-34567..0");
        play.VoidedPages.Enqueue(new PlayVoidedPage([Void(known), Void(Play.NewToken())], new Sensitive<string>("page-2")));
        play.VoidedPages.Enqueue(new PlayVoidedPage([renewalVoid], null));

        var run = await Voided.RunOnceAsync(CancellationToken.None);

        Assert.Equal(3, run.Read);
        Assert.Equal(2, run.Inserted);
        Assert.Equal(1, run.Skipped);
        Assert.Equal("page-2", play.VoidedRequests[1].PageToken);
        var rows = store.Notifications.Where(n => n.Type == "VOIDED_PURCHASE").ToList();
        Assert.Equal(2, rows.Count);
        Assert.All(rows, r =>
        {
            Assert.Matches("^voided:[0-9a-f]{64}$", r.ExternalId);
            Assert.Equal(known, r.StoreKey);
            Assert.Null(r.ProcessedAt);
            Assert.Equal(Convert.FromHexString(r.ExternalId["voided:".Length..]), r.Digest);
        });
        var expected = SHA256.HashData(Encoding.UTF8.GetBytes("GPA.1234-5678-9012-34567\0" + known + "\0" + Play.Now.AddDays(-2).ToUnixTimeMilliseconds()));
        Assert.Contains(rows, r => r.ExternalId == "voided:" + Convert.ToHexStringLower(expected));

        // No RTDN delivered these voids: both count as recovered (delivery failing).
        Assert.Equal(2, telemetry.RecoveredTotal);
    }

    [Fact]
    public async Task TheSameVoidOnTwoDaysIsOneRow()
    {
        var known = Play.NewToken();
        store.AddPurchase(known, Play.Yearly, StoredPurchaseState.Active);
        play.VoidedPages.Enqueue(new PlayVoidedPage([Void(known)], null));
        play.VoidedPages.Enqueue(new PlayVoidedPage([Void(known)], null));

        await Voided.RunOnceAsync(CancellationToken.None);
        clock.Now = Play.Now.AddDays(1);
        var second = await Voided.RunOnceAsync(CancellationToken.None);

        Assert.Equal(0, second.Inserted);
        Assert.Single(store.Notifications);
        Assert.Equal(1, telemetry.RecoveredTotal);
    }

    [Fact]
    public async Task AVoidAlreadyDeliveredByRtdnIsNotCountedAsRecovered()
    {
        var known = Play.NewToken();
        store.AddPurchase(known, Play.Yearly, StoredPurchaseState.Active);
        store.Add("VOIDED_PURCHASE", known, "rtdn-message-1");
        play.VoidedPages.Enqueue(new PlayVoidedPage([Void(known)], null));

        var run = await Voided.RunOnceAsync(CancellationToken.None);

        Assert.Equal(1, run.Inserted);
        Assert.Equal(0, telemetry.RecoveredTotal);
    }

    [Fact]
    public async Task MoreThanTenPagesIsTruncated()
    {
        for (var i = 0; i < 12; i++)
        {
            play.VoidedPages.Enqueue(new PlayVoidedPage([], new Sensitive<string>("p" + i)));
        }

        await Voided.RunOnceAsync(CancellationToken.None);

        Assert.Equal(PlayVoidedReconcileJob.MaxPages, play.VoidedRequests.Count);
        Assert.Equal((RtdnTags.StepVoided, RtdnTags.ReconcileTruncated), Assert.Single(telemetry.Reconciles));
    }

    [Theory]
    [InlineData(PlayCallOutcome.ServerError, "failed")]
    [InlineData(PlayCallOutcome.BudgetDenied, "deferred")]
    public async Task APlayFailureEndsTheRunAndTheNextDayRepeatsTheWindow(PlayCallOutcome outcome, string tag)
    {
        play.Throws.Enqueue(new PlayApiException(PlayApi.VoidedList, outcome, 503));

        var run = await Voided.RunOnceAsync(CancellationToken.None);

        Assert.True(run.Ran);
        Assert.Equal((RtdnTags.StepVoided, tag), Assert.Single(telemetry.Reconciles));
    }

    [Theory]
    [InlineData("tok/../x", "GPA.1", 1L)]
    [InlineData("tok.ok", "GPA 1", 1L)]
    [InlineData("tok.ok", "GPA.1", -1L)]
    public async Task MalformedEntriesAreSkipped(string token, string orderId, long millis)
    {
        store.AddPurchase(token, Play.Yearly, StoredPurchaseState.Active);
        play.VoidedPages.Enqueue(new PlayVoidedPage([new PlayVoidedPurchase(new Sensitive<string>(token), new Sensitive<string>(orderId), millis)], null));

        var run = await Voided.RunOnceAsync(CancellationToken.None);

        Assert.Equal(1, run.Skipped);
        Assert.Empty(store.Notifications);
    }

    [Fact]
    public async Task TheExpirySweepEnqueuesOneRowPerExpiryAndSkipsExistingOnes()
    {
        var due = store.AddPurchase(Play.NewToken(), Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-2), lastVerifiedAt: Play.Now.AddDays(-30));
        store.AddPurchase(Play.NewToken(), Play.Yearly, StoredPurchaseState.Active, Play.Now.AddMinutes(-5), lastVerifiedAt: Play.Now.AddDays(-30));
        store.AddPurchase(Play.NewToken(), Play.Yearly, StoredPurchaseState.Expired, Play.Now.AddHours(-2), lastVerifiedAt: Play.Now.AddDays(-30));
        store.AddPurchase(Play.NewToken(), Play.Yearly, StoredPurchaseState.Active, Play.Now.AddHours(-2), lastVerifiedAt: Play.Now.AddHours(-1));

        var first = await Sweep.RunOnceAsync(CancellationToken.None);
        var second = await Sweep.RunOnceAsync(CancellationToken.None);

        Assert.Equal(1, first.Inserted);
        Assert.Equal(0, second.Read);
        var row = Assert.Single(store.Notifications);
        Assert.Equal(PlayJobKeys.Sweep(due.Id, Play.Now.AddHours(-2)), row.ExternalId);
        Assert.Equal("EXPIRY_SWEEP", row.Type);
        Assert.Equal(due.StoreKey, row.StoreKey);
        Assert.Equal(Play.Now.AddHours(-2), row.EventTime);

        // FU-098 code 3: a dead-lettered sweep row is never re-enqueued for the same expiry; a renewal (new expiry) gets a new row.
        row.ProcessedAt = Play.Now;
        row.LastError = "STORE_ERROR";
        Assert.Equal(0, (await Sweep.RunOnceAsync(CancellationToken.None)).Read);
        due.ExpiresAt = Play.Now.AddMinutes(-30);
        Assert.Equal(1, (await Sweep.RunOnceAsync(CancellationToken.None)).Inserted);
        Assert.Equal(2, store.Notifications.Count);
    }

    [Fact]
    public void TheSweepKeyRoundTrips()
    {
        var id = Guid.CreateVersion7();
        var key = PlayJobKeys.Sweep(id, Play.Now);

        Assert.Matches("^sweep:[0-9a-f-]{36}:[0-9]{1,12}$", key);
        Assert.True(PlayJobKeys.TryParseSweep(key, out var parsed, out var epoch));
        Assert.Equal(id, parsed);
        Assert.Equal(Play.Now.ToUnixTimeSeconds(), epoch);
        Assert.False(PlayJobKeys.TryParseSweep("sweep:" + id.ToString("D").ToUpperInvariant() + ":1", out _, out _));
    }
}
