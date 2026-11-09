using System.Diagnostics;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.Tests.Observability;

/// <summary>T-138: span redaction (the span tag allow-list, URL templates and the status description).</summary>
public sealed class RedactingActivityProcessorTests : IDisposable
{
    private const string Sentinel = "ZgHlSentinelQ7x2Vn9w";

    private readonly ActivitySource source = new("T138.Redaction");
    private readonly ActivityListener listener;

    public RedactingActivityProcessorTests()
    {
        listener = new ActivityListener
        {
            ShouldListenTo = s => s.Name == "T138.Redaction",
            Sample = (ref ActivityCreationOptions<ActivityContext> _) => ActivitySamplingResult.AllDataAndRecorded,
        };
        ActivitySource.AddActivityListener(listener);
    }

    public void Dispose()
    {
        listener.Dispose();
        source.Dispose();
    }

    [Fact]
    public void ServerSpansKeepOnlyAllowListedTagsAndTheRouteTemplate()
    {
        using var activity = source.StartActivity("HttpRequestIn", ActivityKind.Server)!;
        activity.DisplayName = "GET /test/items/" + Sentinel;
        activity.SetTag("http.request.method", "GET");
        activity.SetTag("http.response.status_code", 200);
        activity.SetTag("http.route", "/test/items/{key}");
        activity.SetTag("url.scheme", "https");
        activity.SetTag("url.path", "/test/items/" + Sentinel);
        activity.SetTag("url.query", "q=" + Sentinel);
        activity.SetTag("url.full", "https://h/test/items/" + Sentinel + "?q=1");
        activity.SetTag("http.url", "https://h/" + Sentinel);
        activity.SetTag("http.target", "/" + Sentinel);
        activity.SetTag("user_agent.original", Sentinel);
        activity.SetTag("enduser.id", Sentinel);
        activity.SetTag("client.address", "203.0.113.7");
        activity.SetTag("zaghlol.outcome", "ok");
        activity.SetTag("zaghlol.install", Sentinel);
        activity.SetStatus(ActivityStatusCode.Error, "failed for " + Sentinel);

        new RedactingActivityProcessor().OnEnd(activity);

        var keys = activity.TagObjects.Select(t => t.Key).Order(StringComparer.Ordinal).ToArray();
        string[] expected =
        [
            "http.request.method", "http.response.status_code", "http.route", "url.path", "url.scheme", "zaghlol.outcome",
        ];
        Assert.Equal(expected, keys);
        Assert.Equal("/test/items/{key}", activity.GetTagItem("url.path"));
        Assert.Equal("GET /test/items/{key}", activity.DisplayName);
        Assert.Equal(ActivityStatusCode.Error, activity.Status);
        Assert.Null(activity.StatusDescription);
        Assert.DoesNotContain(Sentinel, Describe(activity), StringComparison.Ordinal);
    }

    [Fact]
    public void AnUnroutedServerSpanHasNoPath()
    {
        using var activity = source.StartActivity("HttpRequestIn", ActivityKind.Server)!;
        activity.DisplayName = "GET /" + Sentinel;
        activity.SetTag("http.request.method", "GET");
        activity.SetTag("url.path", "/" + Sentinel);

        new RedactingActivityProcessor().OnEnd(activity);

        Assert.Null(activity.GetTagItem("url.path"));
        Assert.Equal("GET", activity.DisplayName);
    }

    [Fact]
    public void ClientSpansAreNamedAfterTheirExplicitTemplate()
    {
        const string template = "/androidpublisher/v3/applications/{packageName}/purchases/subscriptionsv2/tokens/{token}";
        using var activity = source.StartActivity("HttpRequestOut", ActivityKind.Client)!;
        activity.SetTag("http.request.method", "GET");
        activity.SetTag("url.template", template);
        activity.SetTag("url.full", "https://p/androidpublisher/v3/applications/app/purchases/subscriptionsv2/tokens/" + Sentinel);
        activity.SetTag("server.address", "play.example");
        activity.SetTag("server.port", 443);
        activity.SetTag("url.path", "/tokens/" + Sentinel);

        new RedactingActivityProcessor().OnEnd(activity);

        Assert.Equal("GET " + template, activity.DisplayName);
        Assert.Null(activity.GetTagItem("url.full"));
        Assert.Null(activity.GetTagItem("url.path"));
        Assert.Equal(template, activity.GetTagItem("url.template"));
        Assert.DoesNotContain(Sentinel, Describe(activity), StringComparison.Ordinal);
    }

    [Fact]
    public void ADatabaseSpanKeepsItsParameterizedStatementAndOperationOnly()
    {
        using var activity = source.StartActivity("Command", ActivityKind.Client)!;
        activity.SetTag("db.system", "postgresql");
        activity.SetTag("db.query.text", "INSERT INTO t (k) VALUES ($1)");
        activity.SetTag("db.operation.name", "INSERT");
        activity.SetTag("db.connection_string", "Host=h;Password=" + Sentinel);
        activity.SetTag("db.user", Sentinel);

        new RedactingActivityProcessor().OnEnd(activity);

        string[] expected = ["db.operation.name", "db.query.text", "db.system"];
        Assert.Equal(expected, activity.TagObjects.Select(t => t.Key).Order(StringComparer.Ordinal).ToArray());
    }

    [Fact]
    public void ZaghlolTagsMustBeOnTheFixedList()
    {
        Assert.All(SpanTagPolicy.ZaghlolKeys, key => Assert.True(SpanTagPolicy.IsAllowed(key), key));
        Assert.False(SpanTagPolicy.IsAllowed("zaghlol.installId"));
        Assert.False(SpanTagPolicy.IsAllowed("url.full"));
        Assert.False(SpanTagPolicy.IsAllowed("url.query"));
        Assert.False(SpanTagPolicy.IsAllowed("http.url"));
        Assert.False(SpanTagPolicy.IsAllowed("http.target"));
        Assert.False(SpanTagPolicy.IsAllowed("exception.message"));
    }

    [Fact]
    public void AnOutboundRequestWithoutATemplateIsUnknown()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri("https://example.test/x/" + Sentinel));
        Assert.Equal(HttpRequestTelemetry.UnknownTemplate, HttpRequestTelemetry.UrlTemplateOf(request));

        request.SetUrlTemplate("/x/{id}");

        Assert.Equal("/x/{id}", HttpRequestTelemetry.UrlTemplateOf(request));
    }

    private static string Describe(Activity activity)
    {
        var parts = new List<string?> { activity.DisplayName, activity.OperationName, activity.StatusDescription };
        parts.AddRange(activity.TagObjects.Select(t => t.Key + "=" + t.Value));
        parts.AddRange(activity.Events.Select(e => e.Name));
        return string.Join('|', parts);
    }
}
