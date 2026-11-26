namespace Zaghlol.Application.Flags;

/// <summary>
/// Posts one operator alert (a fixed-format line with no user data) to the ops channel that <see cref="IOpsNotifier"/> already uses
/// (<c>OpsChannel:WebhookUrl</c>). Best effort: never throws; <c>false</c> when nothing was delivered (channel off or failing).
/// </summary>
public interface IOpsAlertSink
{
    Task<bool> SendAsync(string message, CancellationToken cancellationToken);
}
