using System.Collections.Frozen;

namespace Zaghlol.Infrastructure.Observability;

/// <summary>The span attributes that may leave the process (T-138 design note). Every other tag is removed before export.</summary>
public static class SpanTagPolicy
{
    /// <summary>The <c>zaghlol.*</c> tags our own code may set, with low-cardinality values only.</summary>
    public static IReadOnlyCollection<string> ZaghlolKeys { get; } =
        ["zaghlol.operation", "zaghlol.outcome", "zaghlol.channel", "zaghlol.store", "zaghlol.rule", "zaghlol.code"];

    private static readonly FrozenSet<string> Allowed = new[]
    {
        "http.request.method", "http.response.status_code", "http.route", "url.scheme", "url.template", "server.address",
        "server.port", "network.protocol.version", "db.system", "db.system.name", "db.operation.name", "db.query.text", "error.type",
        "otel.status_code", "url.path",
    }.Concat(ZaghlolKeys).ToFrozenSet(StringComparer.Ordinal);

    public static IReadOnlyCollection<string> AllowedTags => Allowed;

    public static bool IsAllowed(string key) => Allowed.Contains(key);
}
