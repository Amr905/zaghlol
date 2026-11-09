using System.Collections.Frozen;
using System.Text.RegularExpressions;

namespace Zaghlol.Infrastructure.Observability;

/// <summary>How the value of an allow-listed log field must look. A value of another shape is written as <c>&lt;invalid&gt;</c>.</summary>
internal enum LogFieldShape
{
    /// <summary><c>^[A-Z_]{1,40}$</c> (stable problem codes).</summary>
    Code,

    /// <summary><c>^[a-z_:]{1,40}$</c> (reason, outcome, channel, operation).</summary>
    Word,

    /// <summary>16 lowercase hex characters (installHash, tokenHash8).</summary>
    Hex16,

    /// <summary><see cref="Hex16"/>, or <see cref="LogFieldPolicy.InstallHashUnavailable"/> when the log key could not be read (T-124 F7).</summary>
    InstallHash,

    /// <summary>A UUID.</summary>
    Uuid,

    /// <summary>A number.</summary>
    Number,

    /// <summary>A route template, never a raw path.</summary>
    Route,

    /// <summary>An HTTP method.</summary>
    Method,

    /// <summary><c>^[a-z0-9_]{1,60}$</c> (alert rule names).</summary>
    Rule,

    /// <summary>A service name.</summary>
    Service,

    /// <summary>A logger category (a type name).</summary>
    Category,
}

/// <summary>
/// The log allow-list (error-handling-and-observability.md section 3.2, FU-002): the only property names that reach the
/// output, each with the shape its value must have. Everything else is dropped, so a new property can never leak by default.
/// </summary>
public static partial class LogFieldPolicy
{
    /// <summary>The message template of the one event that may carry <c>purchaseId</c>.</summary>
    public const string AuditAlertMessage = "audit_alert";

    /// <summary>The <c>installHash</c> of a request whose pseudonym could not be computed (KMS down); the request still succeeds.</summary>
    public const string InstallHashUnavailable = "unavailable";

    /// <summary>What a value of the wrong shape is replaced by.</summary>
    public const string InvalidValue = "<invalid>";

    /// <summary>Fields written for every event before the properties.</summary>
    internal static readonly string[] CoreFields = ["ts", "level", "msg", "traceId", "spanId"];

    /// <summary>The allow-listed property names, in output order.</summary>
    internal static readonly string[] OrderedFields =
    [
        "service", "category", "method", "route", "status", "durationMs", "installHash", "code", "reason", "operation",
        "channel", "outcome", "tokenHash8", "count", "rule", "purchaseId", "operatorId",
    ];

    /// <summary>
    /// Names that must never appear in log output, as a field or as a value: headers, request members and secrets.
    /// The allow-list already excludes them; this list is what the tests and the code review check it against.
    /// </summary>
    public static IReadOnlyList<string> NeverLogged { get; } =
    [
        "Zaghlol-Time-Nonce", "timeNonce", "Idempotency-Key", "idempotencyKey", "seatKeys", "orderId", "ownershipCheck",
        "purchaseToken", "signedTransaction", "signedTransactions", "idToken", "nonce", "attestation", "assertion",
        "keyId", "refreshToken", "Authorization", "Location", "Cookie", "email", "ip", "requestBody", "responseBody",
        "queryString", "path", "uri", "url", "Zaghlol-Install", "Zaghlol-Account", "installToken", "rotateInstallToken", "accountToken", "headers",
        "requestHeaders",
    ];

    private static readonly FrozenDictionary<string, LogFieldShape> Shapes = new Dictionary<string, LogFieldShape>(StringComparer.Ordinal)
    {
        ["service"] = LogFieldShape.Service,
        ["category"] = LogFieldShape.Category,
        ["method"] = LogFieldShape.Method,
        ["route"] = LogFieldShape.Route,
        ["status"] = LogFieldShape.Number,
        ["durationMs"] = LogFieldShape.Number,
        ["installHash"] = LogFieldShape.InstallHash,
        ["code"] = LogFieldShape.Code,
        ["reason"] = LogFieldShape.Word,
        ["operation"] = LogFieldShape.Word,
        ["channel"] = LogFieldShape.Word,
        ["outcome"] = LogFieldShape.Word,
        ["tokenHash8"] = LogFieldShape.Hex16,
        ["count"] = LogFieldShape.Number,
        ["rule"] = LogFieldShape.Rule,
        ["purchaseId"] = LogFieldShape.Uuid,
        ["operatorId"] = LogFieldShape.Uuid,
    }.ToFrozenDictionary(StringComparer.Ordinal);

    /// <summary>The allow-listed property names (the written <c>ts, level, msg, traceId, spanId</c> and error fields are not properties).</summary>
    public static IReadOnlyCollection<string> AllowedProperties => Shapes.Keys;

    /// <summary>Every field name the formatter can write.</summary>
    public static IReadOnlyCollection<string> AllFields { get; } =
        [.. CoreFields, .. OrderedFields, "errorType", "errorMessage", "stack"];

    internal static bool TryGetShape(string canonicalName, out LogFieldShape shape) => Shapes.TryGetValue(canonicalName, out shape);

    /// <summary>The property name as written: a leading capital becomes lower case (<c>InstallHash</c> to <c>installHash</c>).</summary>
    internal static string Canonical(string propertyName) =>
        propertyName.Length > 0 && char.IsUpper(propertyName[0])
            ? string.Concat(char.ToLowerInvariant(propertyName[0]).ToString(), propertyName.AsSpan(1))
            : propertyName;

    /// <summary>True when a string value has the shape of its field.</summary>
    internal static bool Matches(LogFieldShape shape, string value) => shape switch
    {
        LogFieldShape.Code => CodeRegex().IsMatch(value),
        LogFieldShape.Word => WordRegex().IsMatch(value),
        LogFieldShape.Hex16 => HexRegex().IsMatch(value),
        LogFieldShape.InstallHash => HexRegex().IsMatch(value) || string.Equals(value, InstallHashUnavailable, StringComparison.Ordinal),
        LogFieldShape.Uuid => Guid.TryParseExact(value, "D", out _),
        LogFieldShape.Route => RouteRegex().IsMatch(value),
        LogFieldShape.Method => MethodRegex().IsMatch(value),
        LogFieldShape.Rule => RuleRegex().IsMatch(value),
        LogFieldShape.Service => ServiceRegex().IsMatch(value),
        LogFieldShape.Category => CategoryRegex().IsMatch(value),
        _ => false,
    };

    [GeneratedRegex("^[A-Z_]{1,40}$", RegexOptions.CultureInvariant)]
    private static partial Regex CodeRegex();

    [GeneratedRegex("^[a-z_:]{1,40}$", RegexOptions.CultureInvariant)]
    private static partial Regex WordRegex();

    [GeneratedRegex("^[0-9a-f]{16}$", RegexOptions.CultureInvariant)]
    private static partial Regex HexRegex();

    [GeneratedRegex("^[A-Za-z0-9/{}_.:*~-]{1,200}$", RegexOptions.CultureInvariant)]
    private static partial Regex RouteRegex();

    [GeneratedRegex("^[A-Z]{3,10}$", RegexOptions.CultureInvariant)]
    private static partial Regex MethodRegex();

    [GeneratedRegex("^[a-z0-9_]{1,60}$", RegexOptions.CultureInvariant)]
    private static partial Regex RuleRegex();

    [GeneratedRegex("^[a-z0-9-]{1,32}$", RegexOptions.CultureInvariant)]
    private static partial Regex ServiceRegex();

    [GeneratedRegex("^[A-Za-z0-9_.-]{1,200}$", RegexOptions.CultureInvariant)]
    private static partial Regex CategoryRegex();
}
