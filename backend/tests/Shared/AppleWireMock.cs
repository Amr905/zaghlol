using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json.Nodes;
using WireMock.RequestBuilders;
using WireMock.ResponseBuilders;
using WireMock.Server;

namespace Zaghlol.Testing;

/// <summary>
/// The App Store Server API on two local WireMock servers, one per environment (T-131), so a test can prove which base URL a
/// call went to. Signed parts come from an <see cref="AppleTestPki"/>; everything is synthetic.
/// </summary>
public sealed class AppleWireMock : IDisposable
{
    public const string BundleId = "app.zaghlol";
    public const string Monthly = "zaghlol_gold_monthly";
    public const string Yearly = "zaghlol_gold_yearly";
    public const string Lifetime = "zaghlol_gold_lifetime";

    /// <summary>A synthetic App Store Connect issuer and key ID.</summary>
    public const string IssuerId = "57246542-96fe-1a63-e053-0824d011072a";
    public const string KeyId = "ZT2K7Q9XAB";

    private readonly ECDsa apiKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);

    public AppleWireMock(AppleTestPki? pki = null)
    {
        Pki = pki ?? AppleTestPki.Create();
        Production = WireMockServer.Start();
        Sandbox = WireMockServer.Start();
    }

    public AppleTestPki Pki { get; }

    public WireMockServer Production { get; }

    public WireMockServer Sandbox { get; }

    /// <summary>The public half of the API key the settings carry (to check the bearer JWT's signature).</summary>
    public ECDsa ApiKey => apiKey;

    /// <summary><c>Purchases:Apple:*</c> for a Development/Testing host pointed at these servers, with fast retries and the test root.</summary>
    public IReadOnlyDictionary<string, string?> Settings(int retryBaseDelayMs = 20, int attemptTimeoutMs = 5000, int totalTimeoutMs = 20000) =>
        new Dictionary<string, string?>
        {
            ["Purchases:Apple:BundleId"] = BundleId,
            ["Purchases:Apple:AllowSandbox"] = "true",
            ["Purchases:Apple:ProductionBaseUrl"] = Production.Urls[0],
            ["Purchases:Apple:SandboxBaseUrl"] = Sandbox.Urls[0],
            ["Purchases:Apple:TestRootCertificate"] = Pki.RootBase64,
            ["Purchases:Apple:IssuerId"] = IssuerId,
            ["Purchases:Apple:KeyId"] = KeyId,
            ["Purchases:Apple:PrivateKey"] = apiKey.ExportPkcs8PrivateKeyPem(),
            ["Purchases:Apple:Products:" + Monthly + ":Type"] = "auto_renewable",
            ["Purchases:Apple:Products:" + Monthly + ":Plan"] = "monthly",
            ["Purchases:Apple:Products:" + Yearly + ":Type"] = "auto_renewable",
            ["Purchases:Apple:Products:" + Yearly + ":Plan"] = "yearly",
            ["Purchases:Apple:Products:" + Lifetime + ":Type"] = "non_consumable",
            ["Purchases:Apple:Products:" + Lifetime + ":Plan"] = "lifetime",
            ["Purchases:Apple:Resilience:RetryBaseDelayMs"] = retryBaseDelayMs.ToString(CultureInfo.InvariantCulture),
            ["Purchases:Apple:Resilience:AttemptTimeoutMs"] = attemptTimeoutMs.ToString(CultureInfo.InvariantCulture),
            ["Purchases:Apple:Resilience:TotalTimeoutMs"] = totalTimeoutMs.ToString(CultureInfo.InvariantCulture),
            ["Purchases:Apple:Resilience:MinimumThroughput"] = "100000",
            ["Purchases:Apple:Budget:TokenLimit"] = "100000",
            ["Purchases:Apple:Budget:TokensPerPeriod"] = "100000",
            ["Purchases:Apple:Budget:VerifyPerInstallPerHour"] = "1000",
        };

    public const string HistoryPath = "/inApps/v1/notifications/history";

    public static string TransactionPath(string transactionId) => "/inApps/v1/transactions/" + transactionId;

    public static string SubscriptionsPath(string transactionId) => "/inApps/v1/subscriptions/" + transactionId;

    public static string LookupPath(string orderId) => "/inApps/v1/lookup/" + orderId;

    /// <summary>A fresh synthetic numeric transaction ID.</summary>
    public static string NewTransactionId() => "2" + string.Concat(RandomNumberGenerator.GetBytes(7).Select(b => (b % 10).ToString(CultureInfo.InvariantCulture))) + "00000000";

    public static string TransactionInfoBody(string jws) => new JsonObject { ["signedTransactionInfo"] = jws }.ToJsonString();

    public static string StatusBody(string environment, params (int Status, string OriginalTransactionId, string SignedTransaction, string SignedRenewal)[] items)
    {
        var last = new JsonArray();
        foreach (var (status, original, signedTransaction, signedRenewal) in items)
        {
            last.Add(new JsonObject
            {
                ["status"] = status,
                ["originalTransactionId"] = original,
                ["signedTransactionInfo"] = signedTransaction,
                ["signedRenewalInfo"] = signedRenewal,
            });
        }

        return new JsonObject
        {
            ["environment"] = environment,
            ["bundleId"] = BundleId,
            ["appAppleId"] = 1234567890,
            ["data"] = new JsonArray(new JsonObject { ["subscriptionGroupIdentifier"] = "21000001", ["lastTransactions"] = last }),
        }.ToJsonString();
    }

    public static string LookupBody(int status, params string[] signedTransactions) =>
        new JsonObject { ["status"] = status, ["signedTransactions"] = new JsonArray([.. signedTransactions.Select(s => (JsonNode)s)]) }.ToJsonString();

    /// <summary>A <c>NotificationHistoryResponse</c> (T-134); <c>sendAttempts</c> is Apple's and is never read.</summary>
    public static string HistoryBody(bool hasMore, string? paginationToken, params string[] signedPayloads) =>
        new JsonObject
        {
            ["hasMore"] = hasMore,
            ["paginationToken"] = paginationToken,
            ["notificationHistory"] = new JsonArray([.. signedPayloads.Select(p => (JsonNode)new JsonObject
            {
                ["signedPayload"] = p,
                ["sendAttempts"] = new JsonArray(new JsonObject { ["attemptDate"] = 1, ["sendAttemptResult"] = "TIMED_OUT" }),
            })]),
        }.ToJsonString();

    public static string ErrorBody(long code) => new JsonObject { ["errorCode"] = code, ["errorMessage"] = "synthetic" }.ToJsonString();

    public WireMockServer Server(bool sandbox) => sandbox ? Sandbox : Production;

    public void Get(bool sandbox, string path, int status, string? body = null, TimeSpan? delay = null, string? retryAfter = null)
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

        Server(sandbox).Given(Request.Create().WithPath(path).UsingGet()).WithGuid(StubId(path)).RespondWith(response);
    }

    /// <summary>
    /// <c>POST /inApps/v1/notifications/history</c> (T-134): the answer for requests without a <c>paginationToken</c> query, or with
    /// exactly <paramref name="paginationToken"/>.
    /// </summary>
    public void History(bool sandbox, int status, string? body, string? paginationToken = null, string? retryAfter = null)
    {
        var response = Response.Create().WithStatusCode(status);
        if (body is not null)
        {
            response = response.WithHeader("Content-Type", "application/json").WithBody(body);
        }

        if (retryAfter is not null)
        {
            response = response.WithHeader("Retry-After", retryAfter);
        }

        var request = Request.Create().WithPath(HistoryPath).UsingPost();
        request = paginationToken is null
            ? request.WithParam(query => query is null || !query.ContainsKey("paginationToken"))
            : request.WithParam("paginationToken", paginationToken);
        Server(sandbox).Given(request).RespondWith(response);
    }

    /// <summary>The history requests one server received: (body, paginationToken query value or null).</summary>
    public IReadOnlyList<(string Body, string? Token)> HistoryRequests(bool sandbox) =>
    [
        .. Server(sandbox).LogEntries
            .Where(e => e.RequestMessage!.Path == HistoryPath)
            .Select(e => (e.RequestMessage!.Body ?? string.Empty,
                e.RequestMessage.Query is { } q && q.TryGetValue("paginationToken", out var v) ? v.FirstOrDefault() : null)),
    ];

    /// <summary>The first <paramref name="failures"/> GETs answer <paramref name="failStatus"/>, every later one 200 with the body.</summary>
    public void GetAfterFailures(bool sandbox, string path, int failures, int failStatus, string body)
    {
        var server = Server(sandbox);
        var scenario = "get-" + Guid.NewGuid().ToString("N");
        for (var i = 0; i < failures; i++)
        {
            var step = server.Given(Request.Create().WithPath(path).UsingGet()).InScenario(scenario);
            step = i == 0 ? step : step.WhenStateIs("s" + i);
            step.WillSetStateTo("s" + (i + 1)).RespondWith(Response.Create().WithStatusCode(failStatus));
        }

        var ok = server.Given(Request.Create().WithPath(path).UsingGet()).InScenario(scenario);
        (failures == 0 ? ok : ok.WhenStateIs("s" + failures))
            .RespondWith(Response.Create().WithStatusCode(200).WithHeader("Content-Type", "application/json").WithBody(body));
    }

    public int Count(bool sandbox, string path) => Server(sandbox).LogEntries.Count(e => e.RequestMessage!.Path == path);

    /// <summary>Every request either server received, as (environment, path, Authorization header).</summary>
    public IReadOnlyList<(string Environment, string Path, string? Authorization)> Received() =>
    [
        .. Production.LogEntries.Select(e => ("production", e.RequestMessage!.Path, Auth(e.RequestMessage.Headers))),
        .. Sandbox.LogEntries.Select(e => ("sandbox", e.RequestMessage!.Path, Auth(e.RequestMessage.Headers))),
    ];

    public void Dispose()
    {
        Production.Stop();
        Sandbox.Stop();
        apiKey.Dispose();
        Pki.Dispose();
    }

    private static string? Auth(IDictionary<string, WireMock.Types.WireMockList<string>>? headers) =>
        headers is not null && headers.TryGetValue("Authorization", out var values) ? values.FirstOrDefault() : null;

    private static Guid StubId(string path) => new(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes("GET " + path)).AsSpan(0, 16));
}
