using System.Text.Json.Nodes;
using WireMock.Matchers;
using WireMock.RequestBuilders;
using WireMock.ResponseBuilders;
using WireMock.Server;

namespace Zaghlol.Testing;

/// <summary>
/// The Google Play Developer API v3 on a local WireMock server (T-130). Bodies follow Google's field names; the deprecated
/// <c>latestOrderId</c> can be added to prove it is never read. Every helper takes the purchase token as it appears in the path.
/// </summary>
public sealed class PlayWireMock : IDisposable
{
    public const string Package = "app.zaghlol";
    public const string Monthly = "zaghlol_gold_monthly";
    public const string Yearly = "zaghlol_gold_yearly";
    public const string Lifetime = "zaghlol_gold_lifetime";

    private const string Applications = "/androidpublisher/v3/applications/" + Package;

    public PlayWireMock() => Server = WireMockServer.Start();

    public WireMockServer Server { get; }

    public string BaseUrl => Server.Urls[0];

    /// <summary><c>Purchases:Google:*</c> for a Testing host pointed at this server, with fast retries.</summary>
    public IReadOnlyDictionary<string, string?> Settings(int retryBaseDelayMs = 20, int attemptTimeoutMs = 2000, int totalTimeoutMs = 8000) =>
        new Dictionary<string, string?>
        {
            ["Purchases:Google:PackageName"] = Package,
            ["Purchases:Google:BaseUrl"] = BaseUrl,
            ["Purchases:Google:CredentialSource"] = "None",
            ["Purchases:Google:Products:" + Monthly + ":Kind"] = "subscription",
            ["Purchases:Google:Products:" + Monthly + ":Plan"] = "monthly",
            ["Purchases:Google:Products:" + Yearly + ":Kind"] = "subscription",
            ["Purchases:Google:Products:" + Yearly + ":Plan"] = "yearly",
            ["Purchases:Google:Products:" + Lifetime + ":Kind"] = "onetime",
            ["Purchases:Google:Products:" + Lifetime + ":Plan"] = "lifetime",
            ["Purchases:Google:Resilience:RetryBaseDelayMs"] = retryBaseDelayMs.ToString(System.Globalization.CultureInfo.InvariantCulture),
            ["Purchases:Google:Resilience:AttemptTimeoutMs"] = attemptTimeoutMs.ToString(System.Globalization.CultureInfo.InvariantCulture),
            ["Purchases:Google:Resilience:TotalTimeoutMs"] = totalTimeoutMs.ToString(System.Globalization.CultureInfo.InvariantCulture),
            ["Purchases:Google:Budget:TokenLimit"] = "100000",
            ["Purchases:Google:Budget:TokensPerPeriod"] = "100000",
        };

    public static string SubscriptionPath(string token) => Applications + "/purchases/subscriptionsv2/tokens/" + Uri.EscapeDataString(token);

    public static string ProductPath(string token) => Applications + "/purchases/productsv2/tokens/" + Uri.EscapeDataString(token);

    public static string SubscriptionAckPath(string productId, string token) =>
        Applications + "/purchases/subscriptions/" + productId + "/tokens/" + Uri.EscapeDataString(token) + ":acknowledge";

    public static string ProductAckPath(string productId, string token) =>
        Applications + "/purchases/products/" + productId + "/tokens/" + Uri.EscapeDataString(token) + ":acknowledge";

    public static string OrderPath(string orderId) => Applications + "/orders/" + Uri.EscapeDataString(orderId);

    /// <summary>A <c>SubscriptionPurchaseV2</c> body.</summary>
    public static string SubscriptionBody(
        string? obfuscatedAccountId,
        string state = "SUBSCRIPTION_STATE_ACTIVE",
        string productId = Yearly,
        DateTimeOffset? expiry = null,
        bool acknowledged = false,
        bool test = false,
        string? linkedPurchaseToken = null,
        string? latestSuccessfulOrderId = null,
        string? latestOrderId = null)
    {
        var item = new JsonObject
        {
            ["productId"] = productId,
            ["expiryTime"] = (expiry ?? DateTimeOffset.UtcNow.AddDays(30)).UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'00Z'", System.Globalization.CultureInfo.InvariantCulture),
            ["autoRenewingPlan"] = new JsonObject { ["autoRenewEnabled"] = true },
        };
        if (latestSuccessfulOrderId is not null)
        {
            item["latestSuccessfulOrderId"] = latestSuccessfulOrderId;
        }

        var body = new JsonObject
        {
            ["kind"] = "androidpublisher#subscriptionPurchaseV2",
            ["regionCode"] = "EG",
            ["startTime"] = DateTimeOffset.UtcNow.AddMinutes(-3).UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", System.Globalization.CultureInfo.InvariantCulture),
            ["subscriptionState"] = state,
            ["acknowledgementState"] = acknowledged ? "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED" : "ACKNOWLEDGEMENT_STATE_PENDING",
            ["lineItems"] = new JsonArray(item),
        };
        if (latestOrderId is not null)
        {
            body["latestOrderId"] = latestOrderId;
        }

        if (obfuscatedAccountId is not null)
        {
            body["externalAccountIdentifiers"] = new JsonObject { ["obfuscatedExternalAccountId"] = obfuscatedAccountId };
        }

        if (test)
        {
            body["testPurchase"] = new JsonObject();
        }

        if (linkedPurchaseToken is not null)
        {
            body["linkedPurchaseToken"] = linkedPurchaseToken;
        }

        return body.ToJsonString();
    }

    /// <summary>A <c>ProductPurchaseV2</c> body.</summary>
    public static string ProductBody(
        string? obfuscatedAccountId,
        string state = "PURCHASED",
        string productId = Lifetime,
        bool acknowledged = false,
        bool test = false,
        string? orderId = null)
    {
        var body = new JsonObject
        {
            ["kind"] = "androidpublisher#productPurchaseV2",
            ["productLineItem"] = new JsonArray(new JsonObject { ["productId"] = productId, ["productOfferDetails"] = new JsonObject { ["quantity"] = 1 } }),
            ["purchaseStateContext"] = new JsonObject { ["purchaseState"] = state },
            ["acknowledgementState"] = acknowledged ? "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED" : "ACKNOWLEDGEMENT_STATE_PENDING",
            ["purchaseCompletionTime"] = DateTimeOffset.UtcNow.AddMinutes(-3).UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", System.Globalization.CultureInfo.InvariantCulture),
            ["regionCode"] = "EG",
        };
        if (obfuscatedAccountId is not null)
        {
            body["obfuscatedExternalAccountId"] = obfuscatedAccountId;
        }

        if (test)
        {
            body["testPurchaseContext"] = new JsonObject { ["fopType"] = "TEST" };
        }

        if (orderId is not null)
        {
            body["orderId"] = orderId;
        }

        return body.ToJsonString();
    }

    public static string OrderBody(string? purchaseToken, string state) =>
        new JsonObject { ["orderId"] = "redacted", ["purchaseToken"] = purchaseToken, ["state"] = state }.ToJsonString();

    public void Get(string path, int status, string? body = null, TimeSpan? delay = null, string? retryAfter = null)
    {
        var response = Response.Create().WithStatusCode(status);
        if (body is not null)
        {
            response = response.WithHeader("Content-Type", "application/json").WithBody(body);
        }

        if (delay is { } d)
        {
            response = response.WithDelay(d);
        }

        if (retryAfter is not null)
        {
            response = response.WithHeader("Retry-After", retryAfter);
        }

        Server.Given(Request.Create().WithPath(path).UsingGet()).WithGuid(StubId("GET", path)).RespondWith(response);
    }

    /// <summary>The first <paramref name="failures"/> GETs answer <paramref name="failStatus"/>, every later one 200 with the body.</summary>
    public void GetAfterFailures(string path, int failures, int failStatus, string body)
    {
        var scenario = "get-" + Guid.NewGuid().ToString("N");
        for (var i = 0; i < failures; i++)
        {
            var step = Server.Given(Request.Create().WithPath(path).UsingGet()).InScenario(scenario);
            step = i == 0 ? step : step.WhenStateIs("s" + i);
            step.WillSetStateTo("s" + (i + 1)).RespondWith(Response.Create().WithStatusCode(failStatus));
        }

        var ok = Server.Given(Request.Create().WithPath(path).UsingGet()).InScenario(scenario);
        (failures == 0 ? ok : ok.WhenStateIs("s" + failures))
            .RespondWith(Response.Create().WithStatusCode(200).WithHeader("Content-Type", "application/json").WithBody(body));
    }

    public void Acknowledge(string path, int status = 200, TimeSpan? delay = null)
    {
        var response = Response.Create().WithStatusCode(status);
        if (delay is { } d)
        {
            response = response.WithDelay(d);
        }

        Server.Given(Request.Create().WithPath(path).UsingPost()).WithGuid(StubId("POST", path)).RespondWith(response);
    }

    /// <summary>One stub per method and path: stubbing the same path again replaces the earlier answer.</summary>
    private static Guid StubId(string method, string path) =>
        new(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(method + " " + path)).AsSpan(0, 16));

    /// <summary>Requests the server received, as (method, path).</summary>
    public IReadOnlyList<(string Method, string Path)> Received() =>
        [.. Server.LogEntries.Select(e => (e.RequestMessage!.Method, e.RequestMessage.Path))];

    public int Count(string method, string path) => Received().Count(r => r.Method == method && r.Path == path);

    /// <summary>Requests whose path contains <paramref name="fragment"/>.</summary>
    public int CountContaining(string method, string fragment) =>
        Received().Count(r => r.Method == method && r.Path.Contains(fragment, StringComparison.Ordinal));

    public void Reset() => Server.Reset();

    public void Dispose() => Server.Stop();
}

/// <summary>Matches any path under the package (for catch-all 404s).</summary>
public static class PlayPaths
{
    public static IStringMatcher Any { get; } = new WildcardMatcher("/androidpublisher/*");
}
