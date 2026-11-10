using Microsoft.Extensions.Options;
using Zaghlol.Domain;

namespace Zaghlol.Api.Auth;

/// <summary>
/// T-136 design note §4: outside Development and Testing the host refuses to start unless operator auth is fully configured:
/// <c>OperatorAuth:Enabled=true</c>, valid settings (https issuer, audiences, algorithms within RS256/ES256), the IdP's
/// discovery document and JWKS reachable at boot, and no <c>OperatorAuth:TestIssuer</c>. So a misconfiguration fails the
/// deployment instead of silently refusing every operator. In every environment, an enabled validator in Advisory mode logs
/// a warning that phishing-resistant MFA is enforced by the IdP only (R4-6).
/// </summary>
internal sealed partial class OperatorAuthStartupCheck(
    IOptions<OperatorAuthOptions> options,
    IHostEnvironment environment,
    IServiceProvider services,
    ILogger<OperatorAuthStartupCheck> logger) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        var settings = options.Value;
        var lenient = environment.IsDevelopment() || environment.IsEnvironment("Testing");
        var problem = settings.Enabled ? settings.Problem() : null;

        if (settings.Enabled && problem is null && settings.PhishingResistantMode == PhishingResistantMode.Advisory)
        {
            LogAdvisory(logger, settings.Profile);
        }

        if (lenient)
        {
            if (settings.Enabled && problem is not null)
            {
                LogDisabled(logger, problem);
            }

            return;
        }

        if (settings.TestIssuer.Enabled)
        {
            throw new OperatorAuthConfigurationException("OperatorAuth:TestIssuer is allowed only in the Development and Testing environments.");
        }

        if (!settings.Enabled)
        {
            throw new OperatorAuthConfigurationException("OperatorAuth:Enabled must be true outside Development and Testing.");
        }

        if (problem is not null)
        {
            throw new OperatorAuthConfigurationException(problem);
        }

        var keys = services.GetService<OidcKeyCache>()
            ?? throw new OperatorAuthConfigurationException("The operator OIDC validator is not registered.");
        try
        {
            await keys.LoadAsync(cancellationToken);
        }
#pragma warning disable CA1031 // Rethrown as a configuration failure that stops the host.
        catch (Exception ex) when (ex is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
#pragma warning restore CA1031
        {
            throw new OperatorAuthConfigurationException("The operator IdP's discovery document or JWKS could not be loaded at startup.", ex);
        }
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    [LoggerMessage(
        Level = LogLevel.Warning,
        Message = "Operator auth runs in Advisory mode (profile {Profile}): support_agent and support_lead rely on the IdP's phishing-resistant MFA policy; the API only counts unproven requests (R4-6)")]
    private static partial void LogAdvisory(ILogger logger, OperatorAuthProfile profile);

    [LoggerMessage(Level = LogLevel.Warning, Message = "Operator auth is enabled but not usable, so every operator call is refused: {Problem}")]
    private static partial void LogDisabled(ILogger logger, string problem);
}

/// <summary>Operator auth is missing or misconfigured outside Development and Testing. Constant messages only.</summary>
public sealed class OperatorAuthConfigurationException : SafeException
{
    public OperatorAuthConfigurationException()
    {
    }

    public OperatorAuthConfigurationException(string message)
        : base(message)
    {
    }

    public OperatorAuthConfigurationException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
