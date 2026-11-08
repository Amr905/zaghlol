using System.Diagnostics;
using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.HttpLogging;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Zaghlol.Api.Observability;
using Zaghlol.Api.Signing;
using Zaghlol.Infrastructure.Logging;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Api.Tests.Observability;

/// <summary>
/// T-138 acceptance (error-handling-and-observability.md section 3.2): a random sentinel placed in a query, a path key, an
/// outbound Play URL, the Apple callback's <c>Location</c>, <c>seatKeys</c>, an <c>ownershipCheck</c> order ID, the
/// <c>Zaghlol-Time-Nonce</c> and <c>Idempotency-Key</c> headers, exception messages and a database unique violation appears
/// in no log byte, span or metric tag. Each placement has a positive control: the request ran and was logged.
/// </summary>
public abstract class SentinelTests<TFixture>(TFixture fixture)
    where TFixture : ObservabilityHostFixture
{
    protected TFixture Fixture { get; } = fixture;

    protected abstract bool ExpectsDatabase { get; }

    [Fact]
    public async Task EveryPlacementRanAndWasLogged()
    {
        await Fixture.EnsureScenarioAsync();

        Assert.Equal(HttpStatusCode.OK, Fixture.Statuses["query"]);
        Assert.Equal(HttpStatusCode.OK, Fixture.Statuses["path"]);
        Assert.Equal(HttpStatusCode.OK, Fixture.Statuses["outbound"]);
        Assert.Equal(HttpStatusCode.SeeOther, Fixture.Statuses["redirect"]);
        Assert.Equal(HttpStatusCode.OK, Fixture.Statuses["nonce"]);
        Assert.Equal(HttpStatusCode.BadRequest, Fixture.Statuses["nonce-malformed"]);
        Assert.Equal(HttpStatusCode.NoContent, Fixture.Statuses["idempotency"]);
        Assert.Equal(HttpStatusCode.OK, Fixture.Statuses["body"]);
        Assert.Equal(HttpStatusCode.InternalServerError, Fixture.Statuses["body-throws"]);
        Assert.Equal(HttpStatusCode.InternalServerError, Fixture.Statuses["throws"]);
        Assert.Equal(HttpStatusCode.NotFound, Fixture.Statuses["unmatched"]);
        Assert.Equal(ExpectsDatabase, Fixture.Statuses.TryGetValue("database", out var database) && database == HttpStatusCode.InternalServerError);

        // The outbound client retried each route once (the fake Play server answers 503 first), so its handlers logged.
        Assert.Equal(2, Fixture.PlayAttemptsFor("token"));
        Assert.Equal(2, Fixture.PlayAttemptsFor("order"));

        var completed = Fixture.LogLines.Select(Parse).Where(l => l.GetProperty("msg").GetString() == "request completed").ToArray();
        Assert.True(completed.Length >= Fixture.RequestsSent, $"{completed.Length} request lines for {Fixture.RequestsSent} requests");
        var routes = completed.Select(l => l.GetProperty("route").GetString()).ToHashSet(StringComparer.Ordinal);
        Assert.Contains("/test/items/{key}", routes);
        Assert.Contains("/test/outbound", routes);
        Assert.Contains("/test/throws", routes);
        Assert.Contains("/t/anchored", routes);
        Assert.Contains(RequestLogMiddleware.Unmatched, routes);
        Assert.Contains(completed, l => l.GetProperty("route").GetString() == "/test/throws" && l.GetProperty("status").GetInt32() == 500 && l.GetProperty("level").GetString() == "error");
    }

    [Fact]
    public async Task TheSentinelAppearsInNoLogByte()
    {
        await Fixture.EnsureScenarioAsync();

        Assert.DoesNotContain(Fixture.Sentinel, Fixture.LogOutput, StringComparison.Ordinal);
    }

    [Fact]
    public async Task EveryLogLineIsAllowListedJson()
    {
        await Fixture.EnsureScenarioAsync();

        var allowed = LogFieldPolicy.AllFields.ToHashSet(StringComparer.Ordinal);
        Assert.NotEmpty(Fixture.LogLines);
        foreach (var line in Fixture.LogLines)
        {
            var json = Parse(line);
            Assert.All(json.EnumerateObject().Select(p => p.Name), name => Assert.Contains(name, allowed));
        }
    }

    [Fact]
    public async Task UnhandledExceptionsAreLoggedAsTypeAndStackOnly()
    {
        await Fixture.EnsureScenarioAsync();

        var errors = Fixture.LogLines.Select(Parse).Where(l => l.TryGetProperty("errorType", out _)).ToArray();
        Assert.Contains(errors, l => l.GetProperty("errorType").GetString() == "System.InvalidOperationException");
        Assert.All(errors.Where(l => l.GetProperty("errorType").GetString() == "System.InvalidOperationException"), l => Assert.False(l.TryGetProperty("errorMessage", out _)));
        if (ExpectsDatabase)
        {
            Assert.Contains(errors, l => l.GetProperty("errorType").GetString()!.Contains("PostgresException", StringComparison.Ordinal));
        }
    }

    [Fact]
    public async Task TheSentinelAppearsInNoSpan()
    {
        await Fixture.EnsureScenarioAsync();

        var spans = Fixture.Spans;
        Assert.NotEmpty(spans);
        Assert.DoesNotContain(spans.Select(ObservabilityHostFixture.Describe), d => d.Contains(Fixture.Sentinel, StringComparison.Ordinal));
        Assert.All(spans, span => Assert.All(span.TagObjects.Select(t => t.Key), key => Assert.True(SpanTagPolicy.IsAllowed(key), key)));
        Assert.All(spans, span => Assert.Null(span.StatusDescription));
    }

    [Fact]
    public async Task ServerSpansCarryTheRouteTemplateNotThePath()
    {
        await Fixture.EnsureScenarioAsync();

        var server = Fixture.Spans.Where(a => a.Kind == ActivityKind.Server && a.GetTagItem("http.route") is "/test/items/{key}").ToArray();
        Assert.True(server.Length >= 2, "two item requests");
        Assert.All(server, span =>
        {
            Assert.Equal("/test/items/{key}", span.GetTagItem("url.path"));
            Assert.Equal("GET /test/items/{key}", span.DisplayName);
            Assert.Null(span.GetTagItem("url.query"));
            Assert.Null(span.GetTagItem("url.full"));
        });
    }

    [Fact]
    public async Task OutboundSpansCarryTheExplicitTemplate()
    {
        await Fixture.EnsureScenarioAsync();

        var client = Fixture.Spans
            .Where(a => a.Kind == ActivityKind.Client && a.GetTagItem("url.template") is not null)
            .Select(a => (string)a.GetTagItem("url.template")!)
            .ToArray();

        Assert.Contains(ObservabilityHostFixture.PlayTokenTemplate, client);
        Assert.Contains(ObservabilityHostFixture.PlayOrderTemplate, client);
        Assert.All(Fixture.Spans.Where(a => a.Kind == ActivityKind.Client && a.GetTagItem("url.template") is not null), span =>
        {
            Assert.Null(span.GetTagItem("url.full"));
            Assert.Null(span.GetTagItem("url.path"));
        });
    }

    [Fact]
    public async Task TheSentinelAppearsInNoMetricTag()
    {
        await Fixture.EnsureScenarioAsync();

        Assert.NotEmpty(Fixture.MetricTags);
        Assert.DoesNotContain(Fixture.MetricTags, tag => tag.Contains(Fixture.Sentinel, StringComparison.Ordinal));
        Assert.Contains(Fixture.MetricTags, tag => tag.Contains("http.route=/test/items/{key}", StringComparison.Ordinal));
    }

    [Fact]
    public void NoHttpLoggingMiddlewareIsRegistered()
    {
        Assert.Empty(Fixture.Services.GetServices<IConfigureOptions<HttpLoggingOptions>>());
        Assert.Empty(Fixture.Services.GetServices<IHttpLoggingInterceptor>());
    }

    [Fact]
    public void TheHeaderNamesInTheScenarioAreTheNeverLoggedOnes()
    {
        Assert.Equal("Zaghlol-Time-Nonce", TimeNonceFilter.HeaderName);
        Assert.Contains(TimeNonceFilter.HeaderName, LogFieldPolicy.NeverLogged);
    }

    protected static JsonElement Parse(string line) => JsonDocument.Parse(line).RootElement.Clone();
}

[Collection(ObservabilityCollection.Name)]
public sealed class ProductionLevelSentinelTests(ProductionLevelsFixture fixture)
    : SentinelTests<ProductionLevelsFixture>(fixture), IClassFixture<ProductionLevelsFixture>
{
    protected override bool ExpectsDatabase => true;

    [Fact]
    public async Task FrameworkCategoriesStayAtWarning()
    {
        await Fixture.EnsureScenarioAsync();

        foreach (var line in Fixture.LogLines.Select(Parse))
        {
            var category = line.TryGetProperty("category", out var c) ? c.GetString() : null;
            if (category is not null && LoggingConfigurationExtensions.QuietCategories.Any(q => category.StartsWith(q, StringComparison.Ordinal)))
            {
                Assert.True(line.GetProperty("level").GetString() is "warn" or "error" or "fatal", category);
            }
        }
    }

    [Fact]
    public async Task TheDatabaseUniqueViolationRanAndItsKeyIsNowhere()
    {
        await Fixture.EnsureScenarioAsync();

        Assert.Contains(Fixture.Spans, a => a.GetTagItem("db.system") is "postgresql");
        Assert.DoesNotContain(Fixture.Sentinel, Fixture.LogOutput, StringComparison.Ordinal);
    }
}

[Collection(ObservabilityCollection.Name)]
public sealed class VerboseLevelSentinelTests(VerboseLevelsFixture fixture)
    : SentinelTests<VerboseLevelsFixture>(fixture), IClassFixture<VerboseLevelsFixture>
{
    protected override bool ExpectsDatabase => false;

    [Fact]
    public async Task TheFrameworkReallyLoggedAtVerbose()
    {
        await Fixture.EnsureScenarioAsync();

        var categories = Fixture.LogLines.Select(Parse)
            .Select(l => l.TryGetProperty("category", out var c) ? c.GetString() : null)
            .Where(c => c is not null)
            .ToArray();
        Assert.Contains(categories, c => c!.StartsWith("Microsoft.AspNetCore", StringComparison.Ordinal));
        Assert.Contains(categories, c => c!.StartsWith("System.Net.Http.HttpClient.google-play", StringComparison.Ordinal));
        Assert.Contains(categories, c => c == "Test.Retry");
    }
}

/// <summary>The two hosts share process-wide listeners (activity sources, meters), so their tests run one after the other.</summary>
internal static class ObservabilityCollection
{
    public const string Name = "observability-host";
}
