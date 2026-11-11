using System.Text.Json.Nodes;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.AppStore;

namespace Zaghlol.Infrastructure.Tests.AppStore;

/// <summary>Reports <b>skipped</b> until a recorded sandbox ASSN V2 <c>TEST</c> notification is checked in (T-134 §9, PO question 2).</summary>
public sealed class RecordedAppleNotificationFactAttribute : FactAttribute
{
    public RecordedAppleNotificationFactAttribute()
    {
        if (!File.Exists(AppleNotificationRecordedVectorTests.VectorPath))
        {
            Skip = "No recorded sandbox TEST notification yet (AppStore/fixtures/recorded-sandbox-test-notification.json; T-134 PO question 2).";
        }
    }
}

/// <summary>
/// T-134 §9: the recorded sandbox <c>TEST</c> notification (from <c>Request a Test Notification</c>), stored as
/// <c>{"signedPayload": "..."}</c>, verifies against the real pinned Apple Root CA G3 at its own <c>signedDate</c> and carries the
/// shape the ingest reads. A <c>TEST</c> notification holds no purchase data. No value is printed.
/// </summary>
[Trait("live", "appstore")]
public sealed class AppleNotificationRecordedVectorTests
{
    public static string VectorPath => Path.Combine(AppContext.BaseDirectory, "AppStore", "fixtures", "recorded-sandbox-test-notification.json");

    [RecordedAppleNotificationFact]
    public void TheRecordedSandboxTestNotificationVerifiesAgainstThePinnedAppleRoot()
    {
        var vector = JsonNode.Parse(File.ReadAllText(VectorPath))!.AsObject();
        var payload = new Sensitive<string>(vector["signedPayload"]!.GetValue<string>());

        var notification = new AppleJwsVerifier(AppleRootCertificate.Der).VerifyNotification(payload, DateTimeOffset.UtcNow);

        Assert.Equal("TEST", notification.NotificationType);
        Assert.Equal("2.0", notification.Version);
        Assert.True(Guid.TryParseExact(notification.NotificationUuid, "D", out _));
        Assert.Equal("Sandbox", notification.Data?.Environment);
        Assert.False(string.IsNullOrEmpty(notification.Data?.BundleId));
    }
}
