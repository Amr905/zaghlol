using System.Diagnostics;
using System.Text.RegularExpressions;
using Serilog;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.Tests.Observability;

/// <summary>T-138 / FU-002: the allow-list formatter and its field names (error-handling-and-observability.md section 3.2).</summary>
public sealed partial class ZaghlolJsonFormatterTests
{
    private const string Sentinel = "ZgHlSentinelQ7x2Vn9w";

    private static readonly int[] Pair = [1, 2];

    [GeneratedRegex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z$")]
    private static partial Regex Timestamp();

    private sealed class TestSafeException(string message) : SafeException(message);

    [Fact]
    public void RequestCompletedUsesTheDocumentedFieldNames()
    {
        var output = LogCapture.Run(log => log
            .ForContext("Method", "GET")
            .ForContext("Route", "/v1/catalog/{version}/full")
            .ForContext("Status", 200)
            .ForContext("DurationMs", 12L)
            .ForContext("InstallHash", "0123456789abcdef")
            .ForContext("Code", "VALIDATION_FAILED")
            .Information("request completed"));

        var line = LogCapture.Single(output);

        string[] expected = ["ts", "level", "msg", "service", "method", "route", "status", "durationMs", "installHash", "code"];
        Assert.Equal(expected, LogCapture.Keys(line));
        Assert.Matches(Timestamp(), line.GetProperty("ts").GetString());
        Assert.Equal("info", line.GetProperty("level").GetString());
        Assert.Equal("request completed", line.GetProperty("msg").GetString());
        Assert.Equal("test", line.GetProperty("service").GetString());
        Assert.Equal("/v1/catalog/{version}/full", line.GetProperty("route").GetString());
        Assert.Equal(200, line.GetProperty("status").GetInt32());
        Assert.Equal(12, line.GetProperty("durationMs").GetInt64());
        Assert.Equal("0123456789abcdef", line.GetProperty("installHash").GetString());
        Assert.Equal("VALIDATION_FAILED", line.GetProperty("code").GetString());
        Assert.EndsWith("\n", output, StringComparison.Ordinal);
    }

    [Fact]
    public void TheSectionNamesAreAllWritable()
    {
        // ts, level, msg, traceId, route, status, durationMs, installHash, code (FU-002).
        string[] required = ["ts", "level", "msg", "traceId", "route", "status", "durationMs", "installHash", "code"];
        Assert.All(required, name => Assert.Contains(name, LogFieldPolicy.AllFields));
    }

    [Fact]
    public void TraceAndSpanIdsComeFromTheCurrentActivity()
    {
        using var source = new ActivitySource("T138.Formatter");
        using var listener = new ActivityListener
        {
            ShouldListenTo = s => s.Name == "T138.Formatter",
            Sample = (ref ActivityCreationOptions<ActivityContext> _) => ActivitySamplingResult.AllDataAndRecorded,
        };
        ActivitySource.AddActivityListener(listener);
        using var activity = source.StartActivity("work");
        Assert.NotNull(activity);

        var line = LogCapture.Single(LogCapture.Run(log => log.Information("inside")));

        Assert.Equal(activity.TraceId.ToHexString(), line.GetProperty("traceId").GetString());
        Assert.Equal(activity.SpanId.ToHexString(), line.GetProperty("spanId").GetString());
    }

    [Theory]
    [InlineData(Serilog.Events.LogEventLevel.Warning, "warn")]
    [InlineData(Serilog.Events.LogEventLevel.Error, "error")]
    [InlineData(Serilog.Events.LogEventLevel.Fatal, "fatal")]
    public void LevelsUseTheDocumentedNames(Serilog.Events.LogEventLevel level, string expected)
    {
        var line = LogCapture.Single(LogCapture.Run(log => log.Write(level, "x")));
        Assert.Equal(expected, line.GetProperty("level").GetString());
    }

    [Fact]
    public void MsgIsTheTemplateAndValuesNeverReachTheOutput()
    {
        var output = LogCapture.Run(log => log.Information("verified {Secret} for {Other}", Sentinel, 42));

        var line = LogCapture.Single(output);

        Assert.Equal("verified {Secret} for {Other}", line.GetProperty("msg").GetString());
        Assert.DoesNotContain(Sentinel, output, StringComparison.Ordinal);
    }

    [Fact]
    public void PropertiesOutsideTheAllowListAreDropped()
    {
        var output = LogCapture.Run(log => log
            .ForContext("RequestPath", "/v1/x/" + Sentinel)
            .ForContext("QueryString", "?q=" + Sentinel)
            .ForContext("Anything", Sentinel)
            .Information("x"));

        Assert.DoesNotContain(Sentinel, output, StringComparison.Ordinal);
        string[] expected = ["ts", "level", "msg", "service"];
        Assert.Equal(expected, LogCapture.Keys(LogCapture.Single(output)));
    }

    [Theory]
    [InlineData("Code", "lower_case")]
    [InlineData("Code", "ABCDEFGHIJKLMNOPQRSTUVWXYZ_ABCDEFGHIJKLMNOPQ")]
    [InlineData("InstallHash", "not-hex-at-all-1")]
    [InlineData("InstallHash", "0123456789ABCDEF")]
    [InlineData("TokenHash8", "0123456789abcde")]
    [InlineData("Reason", "Has Spaces")]
    [InlineData("Outcome", "UPPER")]
    [InlineData("Channel", "ab1")]
    [InlineData("Operation", "x/y")]
    [InlineData("Route", "/v1/sync?q=1")]
    [InlineData("Route", "/v1/a b")]
    [InlineData("Method", "get")]
    [InlineData("Rule", "Bad Rule")]
    public void AValueOfTheWrongShapeIsReplaced(string field, string value)
    {
        var line = LogCapture.Single(LogCapture.Run(log => log.ForContext(field, value).Information("x")));

        Assert.Equal(LogFieldPolicy.InvalidValue, line.GetProperty(LogFieldPolicy.Canonical(field)).GetString());
    }

    [Theory]
    [InlineData("Code", "RATE_LIMITED")]
    [InlineData("Reason", "hash_mismatch")]
    [InlineData("Outcome", "ok:retry")]
    [InlineData("Channel", "play_integrity")]
    [InlineData("Operation", "sign_verify")]
    [InlineData("TokenHash8", "89abcdef01234567")]
    [InlineData("Method", "POST")]
    [InlineData("Route", "unmatched")]
    [InlineData("Route", "/admin/v1/catalog/draft/{entity}/{id}")]
    public void AValueOfTheRightShapeIsWritten(string field, string value)
    {
        var line = LogCapture.Single(LogCapture.Run(log => log.ForContext(field, value).Information("x")));

        Assert.Equal(value, line.GetProperty(LogFieldPolicy.Canonical(field)).GetString());
    }

    [Fact]
    public void NumbersMustBeNumbersAndStructuresAreInvalid()
    {
        var line = LogCapture.Single(LogCapture.Run(log => log
            .ForContext("Status", "200")
            .ForContext("Count", 3)
            .ForContext("DurationMs", Pair, destructureObjects: true)
            .Information("x")));

        Assert.Equal(LogFieldPolicy.InvalidValue, line.GetProperty("status").GetString());
        Assert.Equal(3, line.GetProperty("count").GetInt32());
        Assert.Equal(LogFieldPolicy.InvalidValue, line.GetProperty("durationMs").GetString());
    }

    [Fact]
    public void PurchaseIdIsWrittenOnAuditAlertEventsOnly()
    {
        var purchase = Guid.NewGuid();

        var alert = LogCapture.Single(LogCapture.Run(log => log
            .ForContext("Rule", "support_unfreeze").ForContext("PurchaseId", purchase).Warning(LogFieldPolicy.AuditAlertMessage)));
        var other = LogCapture.Single(LogCapture.Run(log => log
            .ForContext("PurchaseId", purchase).Warning("something else")));

        Assert.Equal(purchase.ToString("D"), alert.GetProperty("purchaseId").GetString());
        Assert.Equal("support_unfreeze", alert.GetProperty("rule").GetString());
        Assert.False(other.TryGetProperty("purchaseId", out _));
    }

    [Fact]
    public void IdentifiersMustBeUuids()
    {
        var line = LogCapture.Single(LogCapture.Run(log => log
            .ForContext("OperatorId", "operator-7")
            .ForContext("PurchaseId", "not-a-uuid")
            .Warning(LogFieldPolicy.AuditAlertMessage)));

        Assert.Equal(LogFieldPolicy.InvalidValue, line.GetProperty("operatorId").GetString());
        Assert.Equal(LogFieldPolicy.InvalidValue, line.GetProperty("purchaseId").GetString());
    }

    [Fact]
    public void AnExceptionIsWrittenAsTypeAndStackWithoutItsMessage()
    {
        var failure = Capture(() => throw new InvalidOperationException("order " + Sentinel, new ArgumentException("inner " + Sentinel)));

        var output = LogCapture.Run(log => log.Error(failure, "failed"));

        var line = LogCapture.Single(output);
        Assert.Equal("System.InvalidOperationException>System.ArgumentException", line.GetProperty("errorType").GetString());
        Assert.False(line.TryGetProperty("errorMessage", out _));
        Assert.Contains(nameof(Capture), line.GetProperty("stack").GetString(), StringComparison.Ordinal);
        Assert.DoesNotContain(Sentinel, output, StringComparison.Ordinal);
    }

    [Fact]
    public void ASafeExceptionKeepsItsConstantMessage()
    {
        var failure = Capture(() => throw new TestSafeException("constant text"));

        var line = LogCapture.Single(LogCapture.Run(log => log.Error(failure, "failed")));

        Assert.Equal("constant text", line.GetProperty("errorMessage").GetString());
    }

    // G3 (T-123 test report): the nonce test proves the filter adds nothing, but the framework never logs headers, so it
    // can't show the header is guarded. This does, directly: every never-logged name is outside the allow-list, and a log
    // event that carries it as a property (as a header, a DTO member or a scope value) writes neither the name nor the value.
    [Fact]
    public void TheNeverLoggedNamesIncludeTheTimeNonceAndIdempotencyHeaders()
    {
        Assert.Contains("Zaghlol-Time-Nonce", LogFieldPolicy.NeverLogged);
        Assert.Contains("timeNonce", LogFieldPolicy.NeverLogged);
        Assert.Contains("Idempotency-Key", LogFieldPolicy.NeverLogged);
        Assert.Contains("seatKeys", LogFieldPolicy.NeverLogged);
        Assert.Contains("orderId", LogFieldPolicy.NeverLogged);
    }

    [Fact]
    public void NoNeverLoggedNameIsAllowListed()
    {
        foreach (var name in LogFieldPolicy.NeverLogged)
        {
            Assert.DoesNotContain(name, LogFieldPolicy.AllFields, StringComparer.OrdinalIgnoreCase);
            Assert.DoesNotContain(LogFieldPolicy.Canonical(name), LogFieldPolicy.AllFields);
        }
    }

    [Fact]
    public void ANeverLoggedNameAsAPropertyWritesNeitherNameNorValue()
    {
        foreach (var name in LogFieldPolicy.NeverLogged)
        {
            var headers = new Dictionary<string, string> { [name] = Sentinel };
            var output = LogCapture.Run(log => log
                .ForContext(name, Sentinel)
                .ForContext("Headers", headers, destructureObjects: true)
                .ForContext("RequestHeaders", headers, destructureObjects: true)
                .Information("handled"));

            Assert.DoesNotContain(Sentinel, output, StringComparison.Ordinal);
            Assert.DoesNotContain("\"" + name + "\"", output, StringComparison.OrdinalIgnoreCase);
        }
    }

    [Fact]
    public void SensitiveMembersNeverShowTheirValueThroughDestructuringOrToString()
    {
        var dto = new Secrets(new Sensitive<string>(Sentinel), new Sensitive<string[]>([Sentinel]));

        var output = LogCapture.Run(log => log.Information("got {@Dto} {Dto}", dto, dto));

        Assert.DoesNotContain(Sentinel, output, StringComparison.Ordinal);
        Assert.DoesNotContain(Sentinel, dto.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(Sentinel, $"{dto.OrderId} {dto.SeatKeys}", StringComparison.Ordinal);
    }

    private sealed record Secrets(Sensitive<string> OrderId, Sensitive<string[]> SeatKeys);

    private static Exception Capture(Action throwing)
    {
        try
        {
            throwing();
        }
        catch (Exception ex)
        {
            return ex;
        }

        throw new InvalidOperationException("The action did not throw.");
    }
}
