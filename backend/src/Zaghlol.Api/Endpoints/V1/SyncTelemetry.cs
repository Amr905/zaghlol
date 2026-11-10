using Zaghlol.Application.Sync;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// <see cref="ISyncTelemetry"/> on the Zaghlol meter and the structured log (T-128 design note §7). Every argument is a fixed tag
/// value; the log events carry only a fixed code and a fixed word (<c>reason</c>), never the request, the time nonce, the
/// install token or hash, or <c>entitlementIssuedAt</c>.
/// </summary>
internal sealed partial class SyncTelemetry(ZaghlolMetrics metrics, ILogger<SyncTelemetry> logger) : ISyncTelemetry
{
    public void Request(string outcome)
    {
        metrics.SyncRequest(outcome);
        if (string.Equals(outcome, SyncTags.Throttled, StringComparison.Ordinal))
        {
            LogThrottled(logger);
        }
    }

    public void Catalog(string mode) => metrics.SyncCatalog(mode);

    public void Intake(string kind, string result, int count) => metrics.SyncIntake(kind, result, count);

    public void BlockFailed(string block, string cause)
    {
        metrics.SyncBlockFailed(block);
        LogBlockFailed(logger, block, cause);
    }

    public void Unavailable(string cause)
    {
        metrics.SyncRequest(SyncTags.Unavailable);
        LogUnavailable(logger, cause);
    }

    public void FlagRulesInvalid(string flag)
    {
        metrics.SyncFlagRulesInvalid(flag);
        LogFlagRulesInvalid(logger, flag);
    }

    public void InstallHashUnavailable() => metrics.InstallHashUnavailable();

    [LoggerMessage(Level = LogLevel.Debug, Message = "SYNC_THROTTLED")]
    private static partial void LogThrottled(ILogger logger);

    [LoggerMessage(Level = LogLevel.Warning, Message = "SYNC_BLOCK_FAILED {Reason} {Cause}")]
    private static partial void LogBlockFailed(ILogger logger, string reason, string cause);

    [LoggerMessage(Level = LogLevel.Warning, Message = "SYNC_UNAVAILABLE {Reason}")]
    private static partial void LogUnavailable(ILogger logger, string reason);

    [LoggerMessage(Level = LogLevel.Warning, Message = "SYNC_FLAG_RULES_INVALID {Reason}")]
    private static partial void LogFlagRulesInvalid(ILogger logger, string reason);
}
