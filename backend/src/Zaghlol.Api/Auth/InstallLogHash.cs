using Zaghlol.Api.Observability;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Api.Auth;

/// <summary>
/// Puts <c>installHash</c> for the request log in <c>HttpContext.Items</c> (F6/F7). The pseudonymizer only ever gets an
/// <see cref="InstallId"/>. A pseudonymizer or KMS failure is counted and logged as <c>installHash=unavailable</c>; the
/// request itself still succeeds.
/// </summary>
internal static class InstallLogHash
{
    public static async ValueTask SetAsync(HttpContext context, InstallId installId)
    {
        ArgumentNullException.ThrowIfNull(context);

        var pseudonymizer = context.RequestServices.GetRequiredService<ILogPseudonymizer>();
        string value;
        try
        {
            value = await pseudonymizer.InstallHashAsync(installId, context.RequestAborted);
        }
#pragma warning disable CA1031 // F7: any failure of the log pseudonym degrades the log line, never the request.
        catch (Exception ex) when (ex is not OperationCanceledException)
#pragma warning restore CA1031
        {
            context.RequestServices.GetService<ZaghlolMetrics>()?.InstallHashUnavailable();
            value = LogFieldPolicy.InstallHashUnavailable;
        }

        context.Items[RequestLogItems.InstallHash] = value;
    }
}

/// <summary>
/// F7 startup check: computes <c>installHash</c> for a fixed install ID. Outside Development and Testing a failure (no KMS,
/// wrong key reference) stops the host; in Development and Testing it is logged and the host starts.
/// </summary>
internal sealed partial class InstallHashStartupCheck(
    ILogPseudonymizer pseudonymizer,
    IHostEnvironment environment,
    ILogger<InstallHashStartupCheck> logger) : IHostedService
{
    public static readonly InstallId Probe = InstallId.Parse("00000000-0000-4000-8000-000000000000");

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            await pseudonymizer.InstallHashAsync(Probe, cancellationToken);
        }
#pragma warning disable CA1031 // Any failure is either fatal (rethrown as a constant-message exception) or logged in Development.
        catch (Exception ex) when (ex is not OperationCanceledException)
#pragma warning restore CA1031
        {
            if (!environment.IsDevelopment() && !environment.IsEnvironment("Testing"))
            {
                throw new InstallHashUnavailableException();
            }

            LogUnavailable(logger);
        }
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    [LoggerMessage(Level = LogLevel.Warning, Message = "installHash is unavailable at startup; requests will log installHash=unavailable")]
    private static partial void LogUnavailable(ILogger logger);
}

/// <summary>The log pseudonym could not be computed at startup outside Development and Testing.</summary>
public sealed class InstallHashUnavailableException : SafeException
{
    public const string DefaultMessage = "installHash is unavailable: the KMS-derived log key could not be read.";

    public InstallHashUnavailableException()
        : base(DefaultMessage)
    {
    }

    public InstallHashUnavailableException(string message)
        : base(message)
    {
    }

    public InstallHashUnavailableException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
