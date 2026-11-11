using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.AppStore;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.AppStore;

/// <summary>
/// T-134 design note §1 step 3: the ASSN V2 outer payload through the same pipeline as T-131 (pinned-root chain, ES256 only,
/// forbidden headers, exactly three certificates, OIDs, P1363), with a 65 536-character cap and validation at the payload's own
/// <c>signedDate</c>; and the nested renewal JWS from a notification.
/// </summary>
public sealed class AppleNotificationVerifierTests : IDisposable
{
    private static readonly DateTimeOffset Now = DateTimeOffset.UtcNow;

    private readonly AppleTestPki pki = AppleTestPki.Create();

    private AppleJwsVerifier Verifier => new(pki.RootDer);

    public void Dispose() => pki.Dispose();

    [Fact]
    public void AGenuineNotificationVerifiesAndOnlyTheReadFieldsComeBack()
    {
        var uuid = Guid.NewGuid().ToString("D");
        var payload = AppleTestPki.Notification("DID_CHANGE_RENEWAL_STATUS", "AUTO_RENEW_DISABLED", "app.zaghlol", "Sandbox", "t.t.t", "r.r.r", Now.AddMinutes(-3), uuid, status: 1);

        var notification = Verifier.VerifyNotification(new Sensitive<string>(pki.Sign(payload)), Now);

        Assert.Equal("DID_CHANGE_RENEWAL_STATUS", notification.NotificationType);
        Assert.Equal("AUTO_RENEW_DISABLED", notification.Subtype);
        Assert.Equal(uuid, notification.NotificationUuid);
        Assert.Equal("2.0", notification.Version);
        Assert.Equal(AppleTestPki.Ms(Now.AddMinutes(-3)), notification.SignedDate.ToUnixTimeMilliseconds());
        Assert.Equal("app.zaghlol", notification.Data!.BundleId);
        Assert.Equal("Sandbox", notification.Data.Environment);
        Assert.Equal(1, notification.Data.Status);
        Assert.Equal("t.t.t", notification.Data.SignedTransactionInfo?.Reveal());
        Assert.Equal("r.r.r", notification.Data.SignedRenewalInfo?.Reveal());
        Assert.DoesNotContain("t.t.t", notification.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void ANotificationWithoutDataComesBackWithoutData()
    {
        var payload = AppleTestPki.Notification("RENEWAL_EXTENSION", "SUMMARY", "app.zaghlol", withData: false);

        Assert.Null(Verifier.VerifyNotification(new Sensitive<string>(pki.Sign(payload)), Now).Data);
    }

    [Fact]
    public void TheOuterCapIs65536CharactersCheckedBeforeAnyDecode()
    {
        Assert.Equal(65536, AppleJwsVerifier.MaxNotificationLength);

        // A genuine notification well above the 16 384 transaction cap verifies; a genuine one just above 65 536 is refused unread.
        var big = Sized(60000);
        var tooBig = Sized(AppleJwsVerifier.MaxNotificationLength + 1);
        Assert.InRange(big.Length, AppleJwsVerifier.MaxLength + 1, AppleJwsVerifier.MaxNotificationLength);
        Assert.InRange(tooBig.Length, AppleJwsVerifier.MaxNotificationLength + 1, AppleJwsVerifier.MaxNotificationLength + 8);
        Assert.Equal("TEST", Verifier.VerifyNotification(new Sensitive<string>(big), Now).NotificationType);
        Assert.Equal(AppleJwsFailure.Malformed, Fail(tooBig).Reason);

        // Transactions keep the 16 384 cap even inside a notification.
        var transaction = pki.Sign(AppleTestPki.Transaction("app.zaghlol", "zaghlol_gold_yearly", "2000000123456789", "2000000123456700", null));
        var padded = transaction + new string('A', AppleJwsVerifier.MaxLength + 1 - transaction.Length);
        Assert.Equal(AppleJwsFailure.Malformed, Assert.Throws<AppleJwsException>(() => Verifier.VerifyTransaction(new Sensitive<string>(padded), JwsSource.Notification, Now)).Reason);
    }

    /// <summary>A genuinely signed notification of at least <paramref name="length"/> characters (the smallest filler that reaches it).</summary>
    private string Sized(int length)
    {
        var filler = 0;
        while (true)
        {
            var payload = AppleTestPki.Notification("TEST", null, "app.zaghlol");
            payload["data"]!["filler"] = new string('x', filler);
            var jws = pki.Sign(payload);
            if (jws.Length >= length)
            {
                return jws;
            }

            filler += Math.Max(1, (length - jws.Length) * 3 / 4);
        }
    }

    [Fact]
    public void AFlippedPayloadOrSignatureByteIsASignatureFailure()
    {
        var parts = pki.Sign(AppleTestPki.Notification("REFUND", null, "app.zaghlol", signedTransactionInfo: "t.t.t")).Split('.');
        var body = parts[1].ToCharArray();
        body[10] = body[10] == 'A' ? 'B' : 'A';
        var signature = parts[2].ToCharArray();
        signature[5] = signature[5] == 'A' ? 'B' : 'A';

        Assert.Contains(Fail(parts[0] + "." + new string(body) + "." + parts[2]).Reason, new[] { AppleJwsFailure.Signature, AppleJwsFailure.Malformed, AppleJwsFailure.Payload });
        Assert.Equal(AppleJwsFailure.Signature, Fail(parts[0] + "." + parts[1] + "." + new string(signature)).Reason);
    }

    [Theory]
    [InlineData("none")]
    [InlineData("HS256")]
    [InlineData("ES384")]
    public void AnyAlgorithmButEs256IsRefused(string alg)
    {
        var header = pki.Header();
        header["alg"] = alg;

        Assert.Equal(AppleJwsFailure.Alg, Fail(pki.Sign(AppleTestPki.Notification("TEST", null, "app.zaghlol"), header)).Reason);
    }

    [Fact]
    public void AnEmbeddedJwkIsRefused()
    {
        var header = pki.Header();
        header["jwk"] = new JsonObject { ["kty"] = "EC" };

        Assert.Equal(AppleJwsFailure.Alg, Fail(pki.Sign(AppleTestPki.Notification("TEST", null, "app.zaghlol"), header)).Reason);
    }

    [Theory]
    [InlineData(2)]
    [InlineData(4)]
    public void AChainOfTwoOrFourCertificatesIsRefused(int count)
    {
        var header = pki.Header();
        var chain = (JsonArray)header["x5c"]!;
        var certificates = chain.Select(c => c!.GetValue<string>()).ToList();
        var resized = count == 2 ? certificates.Take(2) : certificates.Append(certificates[2]);
        header["x5c"] = new JsonArray([.. resized.Select(c => (JsonNode)c)]);

        Assert.Equal(AppleJwsFailure.Chain, Fail(pki.Sign(AppleTestPki.Notification("TEST", null, "app.zaghlol"), header)).Reason);
    }

    [Theory]
    [InlineData(false, true)]
    [InlineData(true, false)]
    public void ALeafOrIntermediateWithoutAppleMarkerIsRefused(bool leafOid, bool intermediateOid)
    {
        using var other = AppleTestPki.Create(leafOid: leafOid, intermediateOid: intermediateOid);
        var verifier = new AppleJwsVerifier(other.RootDer);

        var error = Assert.Throws<AppleJwsException>(() => verifier.VerifyNotification(new Sensitive<string>(other.Sign(AppleTestPki.Notification("TEST", null, "app.zaghlol"))), Now));
        Assert.Equal(AppleJwsFailure.Oid, error.Reason);
    }

    [Fact]
    public void ASelfMadeRootWithThePinnedRootsSubjectIsRefused()
    {
        using var forged = AppleTestPki.Create(rootSubject: "CN=Zaghlol Test Root CA - G3, OU=Test Certification Authority, O=Zaghlol Tests, C=EG");

        Assert.Equal(AppleJwsFailure.Chain, Fail(forged.Sign(AppleTestPki.Notification("REFUND", null, "app.zaghlol"))).Reason);
    }

    [Fact]
    public void ATestPkiNotificationNeverPassesTheRealPinnedAppleRoot()
    {
        var real = new AppleJwsVerifier(AppleRootCertificate.Der);

        var error = Assert.Throws<AppleJwsException>(() => real.VerifyNotification(new Sensitive<string>(pki.Sign(AppleTestPki.Notification("TEST", null, "app.zaghlol"))), Now));
        Assert.Equal(AppleJwsFailure.Chain, error.Reason);
    }

    [Fact]
    public void ARetryUnderAnIntermediateThatHasSinceExpiredVerifiesAtItsSignedDate()
    {
        // Apple's retries and history entries keep their original signature (T-134 §1 step 3).
        using var old = AppleTestPki.Create(intermediateNotAfter: Now.AddDays(-2));
        var verifier = new AppleJwsVerifier(old.RootDer);
        var payload = AppleTestPki.Notification("DID_RENEW", null, "app.zaghlol", signedDate: Now.AddDays(-6));

        var notification = verifier.VerifyNotification(new Sensitive<string>(old.Sign(payload)), Now);

        Assert.Equal("DID_RENEW", notification.NotificationType);
    }

    [Fact]
    public void ANotificationSignedMoreThanFiveMinutesAheadOrWithoutASignedDateIsRefused()
    {
        Assert.Equal(AppleJwsFailure.Payload, Fail(pki.Sign(AppleTestPki.Notification("TEST", null, "app.zaghlol", signedDate: Now.AddMinutes(6)))).Reason);
        Assert.NotNull(Verifier.VerifyNotification(new Sensitive<string>(pki.Sign(AppleTestPki.Notification("TEST", null, "app.zaghlol", signedDate: Now.AddMinutes(4)))), Now));

        var unsigned = AppleTestPki.Notification("TEST", null, "app.zaghlol");
        unsigned.Remove("signedDate");
        Assert.Equal(AppleJwsFailure.Payload, Fail(pki.Sign(unsigned)).Reason);
    }

    [Fact]
    public void DuplicateMembersOrAStatusOfTheWrongTypeAreRefused()
    {
        var duplicate = pki.Sign(pki.Header().ToJsonString(), "{\"notificationType\":\"TEST\",\"notificationType\":\"REFUND\",\"signedDate\":" + AppleTestPki.Ms(Now) + "}");
        var wrongType = AppleTestPki.Notification("TEST", null, "app.zaghlol");
        wrongType["data"]!["status"] = "1";

        Assert.Equal(AppleJwsFailure.Malformed, Fail(duplicate).Reason);
        Assert.Equal(AppleJwsFailure.Payload, Fail(pki.Sign(wrongType)).Reason);
    }

    [Fact]
    public void RenewalInfoFromANotificationIsValidatedAtItsSignedDateAndNeverAcceptedFromTheApp()
    {
        using var old = AppleTestPki.Create(intermediateNotAfter: Now.AddDays(-2));
        var verifier = new AppleJwsVerifier(old.RootDer);
        var renewal = AppleTestPki.Renewal("2000000123456700", "zaghlol_gold_yearly");
        renewal["signedDate"] = AppleTestPki.Ms(Now.AddDays(-6));
        var jws = new Sensitive<string>(old.Sign(renewal));

        Assert.Equal("2000000123456700", verifier.VerifyRenewalInfo(jws, JwsSource.Notification, Now).OriginalTransactionId?.Reveal());
        Assert.Equal(AppleJwsFailure.Chain, Assert.Throws<AppleJwsException>(() => verifier.VerifyRenewalInfo(jws, JwsSource.Api, Now)).Reason);
        Assert.Throws<ArgumentOutOfRangeException>(() => verifier.VerifyRenewalInfo(jws, JwsSource.App, Now));
    }

    /// <summary>AC 4: the Apple payload and history DTOs list only the fields read; no catch-all member of any kind.</summary>
    [Fact]
    public void TheNotificationAndHistoryDtosHaveNoCatchAllMember()
    {
        var types = typeof(AppleJwsVerifier).Assembly.GetTypes()
            .Where(t => t.Namespace == typeof(AppleJwsVerifier).Namespace && t.Name.EndsWith("Dto", StringComparison.Ordinal))
            .ToList();
        Assert.Contains(types, t => t.Name == "NotificationPayloadDto");
        Assert.Contains(types, t => t.Name == "NotificationDataDto");
        Assert.Contains(types, t => t.Name == "NotificationHistoryResponseDto");
        Assert.Contains(types, t => t.Name == "NotificationHistoryItemDto");

        foreach (var type in types)
        {
            foreach (var property in type.GetProperties(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic))
            {
                Assert.True(DtoRules.IsAllowed(property), $"{type.Name}.{property.Name} is a catch-all member");
            }
        }
    }

    private AppleJwsException Fail(string jws) =>
        Assert.Throws<AppleJwsException>(() => Verifier.VerifyNotification(new Sensitive<string>(jws), Now));
}

/// <summary>The AC 4 review rule as code: no extension data, no untyped JSON, no object, no dictionary.</summary>
internal static class DtoRules
{
    public static bool IsAllowed(PropertyInfo property)
    {
        if (property.GetCustomAttribute<JsonExtensionDataAttribute>() is not null)
        {
            return false;
        }

        var type = Nullable.GetUnderlyingType(property.PropertyType) ?? property.PropertyType;
        if (type == typeof(object) || type == typeof(JsonElement) || typeof(JsonNode).IsAssignableFrom(type) || type == typeof(JsonDocument))
        {
            return false;
        }

        return !type.GetInterfaces().Append(type).Any(i => i.IsGenericType
            && (i.GetGenericTypeDefinition() == typeof(IDictionary<,>) || i.GetGenericTypeDefinition() == typeof(IReadOnlyDictionary<,>)))
            && !typeof(System.Collections.IDictionary).IsAssignableFrom(type);
    }
}
