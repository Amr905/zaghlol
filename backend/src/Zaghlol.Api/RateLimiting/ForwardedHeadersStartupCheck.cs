using Microsoft.Extensions.Options;
using Zaghlol.Domain;

namespace Zaghlol.Api.RateLimiting;

/// <summary>
/// T-124 security S-1: the per-network rate limit partitions on the client address that <c>ForwardedHeaders</c> resolves.
/// Behind a load balancer with no trusted proxy configured, every client looks like the proxy and shares one bucket, so one
/// client could block registration for everyone. Outside Development and Testing the host therefore refuses to start unless
/// <c>ForwardedHeaders:KnownProxies</c> or <c>ForwardedHeaders:KnownNetworks</c> lists at least one entry, or
/// <c>ForwardedHeaders:NoProxy=true</c> states that clients connect directly. Nothing about requests is logged here.
/// </summary>
internal sealed class ForwardedHeadersStartupCheck(
    IOptions<ForwardedHeadersOptions> options,
    IConfiguration configuration,
    IHostEnvironment environment) : IHostedService
{
    public const string NoProxyKey = RateLimitServiceCollectionExtensions.ForwardedHeadersSection + ":NoProxy";

    public Task StartAsync(CancellationToken cancellationToken)
    {
        if (environment.IsDevelopment() || environment.IsEnvironment("Testing"))
        {
            return Task.CompletedTask;
        }

        var forwarded = options.Value;
        if (forwarded.KnownProxies.Count > 0 || forwarded.KnownIPNetworks.Count > 0)
        {
            return Task.CompletedTask;
        }

        if (configuration.GetValue<bool>(NoProxyKey))
        {
            return Task.CompletedTask;
        }

        throw new ForwardedHeadersConfigurationException();
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}

/// <summary>Neither a trusted proxy list nor the explicit no-proxy flag is configured outside Development and Testing.</summary>
public sealed class ForwardedHeadersConfigurationException : SafeException
{
    public const string DefaultMessage =
        "ForwardedHeaders is not configured: set ForwardedHeaders:KnownProxies or ForwardedHeaders:KnownNetworks to the "
        + "load balancer's addresses, or ForwardedHeaders:NoProxy=true if clients connect directly.";

    public ForwardedHeadersConfigurationException()
        : base(DefaultMessage)
    {
    }

    public ForwardedHeadersConfigurationException(string message)
        : base(message)
    {
    }

    public ForwardedHeadersConfigurationException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
