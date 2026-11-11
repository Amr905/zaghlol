using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Problems;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Api.RateLimiting;

/// <summary>One token bucket: <see cref="TokenLimit"/> burst, <see cref="TokensPerPeriod"/> added every <see cref="PeriodSeconds"/>.</summary>
public sealed class TokenBucketSettings
{
    public int TokenLimit { get; set; }

    public int TokensPerPeriod { get; set; }

    public int PeriodSeconds { get; set; }

    internal TokenBucketRateLimiterOptions ToOptions() => new()
    {
        TokenLimit = TokenLimit,
        TokensPerPeriod = TokensPerPeriod,
        ReplenishmentPeriod = TimeSpan.FromSeconds(PeriodSeconds),
        QueueLimit = 0,
        AutoReplenishment = true,
    };
}

/// <summary>
/// <c>RateLimits:*</c> (backend-api §1; T-124 design note, decision (a): the numbers are proposals). Buckets live in process
/// memory, so with N API instances the effective limit is up to N times higher (decision (b)).
/// </summary>
public sealed class RateLimitSettings
{
    public const string Section = "RateLimits";

    /// <summary>Every request per client /24 (IPv4) or /56 (IPv6), before authentication: 600 a minute.</summary>
    public TokenBucketSettings PerNetwork { get; set; } = new() { TokenLimit = 600, TokensPerPeriod = 600, PeriodSeconds = 60 };

    /// <summary><c>POST /v1/installs</c> per /24 in addition: 60 an hour (carrier NAT puts many users behind one /24).</summary>
    public TokenBucketSettings Register { get; set; } = new() { TokenLimit = 60, TokensPerPeriod = 60, PeriodSeconds = 3600 };

    /// <summary>Per install token (or per operator on `/admin/v1`), after authentication: burst 30, 10 a minute.</summary>
    public TokenBucketSettings PerToken { get; set; } = new() { TokenLimit = 30, TokensPerPeriod = 10, PeriodSeconds = 60 };

    /// <summary>The support lookup per operator in addition (T-136, enumeration guard): 20 a minute.</summary>
    public TokenBucketSettings SupportLookup { get; set; } = new() { TokenLimit = 20, TokensPerPeriod = 20, PeriodSeconds = 60 };

    /// <summary>
    /// <c>POST /v1/notifications/apple</c> per /24 (T-134, policy <c>notifications-apple</c>): 1 200 a minute, <b>instead of</b> the
    /// general per-network bucket, so Apple's delivery and app traffic never drain each other. A 429 is retried by Apple.
    /// </summary>
    public TokenBucketSettings AppleNotifications { get; set; } = new() { TokenLimit = 1200, TokensPerPeriod = 1200, PeriodSeconds = 60 };

    /// <summary>
    /// <c>POST /v1/notifications/google</c> per /24 (T-133, policy <c>notifications-google</c>): 1 200 a minute, instead of the general
    /// per-network bucket. A 429 is redelivered by Pub/Sub.
    /// </summary>
    public TokenBucketSettings GoogleNotifications { get; set; } = new() { TokenLimit = 1200, TokensPerPeriod = 1200, PeriodSeconds = 60 };
}

/// <summary>Endpoint metadata: this endpoint uses the <c>notifications-apple</c> per-network bucket instead of the general one.</summary>
internal sealed class AppleNotificationRateLimitMetadata
{
    public static readonly AppleNotificationRateLimitMetadata Instance = new();

    private AppleNotificationRateLimitMetadata()
    {
    }
}

/// <summary>Endpoint metadata: this endpoint also draws on the registration bucket.</summary>
/// <summary>Endpoint metadata: this endpoint uses the <c>notifications-google</c> per-network bucket instead of the general one.</summary>
internal sealed class GoogleNotificationRateLimitMetadata
{
    public static readonly GoogleNotificationRateLimitMetadata Instance = new();

    private GoogleNotificationRateLimitMetadata()
    {
    }
}

internal sealed class RegistrationRateLimitMetadata
{
    public static readonly RegistrationRateLimitMetadata Instance = new();

    private RegistrationRateLimitMetadata()
    {
    }
}

/// <summary>Endpoint metadata: this operator endpoint also draws on the per-operator support-lookup bucket.</summary>
internal sealed class SupportLookupRateLimitMetadata
{
    public static readonly SupportLookupRateLimitMetadata Instance = new();

    private SupportLookupRateLimitMetadata()
    {
    }
}

/// <summary>
/// The two rate-limiter stages of the pipeline (built-in <c>Microsoft.AspNetCore.RateLimiting</c>, no package): per client
/// network before authentication (so failed-token floods count) and per install token after it. A rejection is
/// <c>429 RATE_LIMITED</c> with <c>Retry-After</c> and <c>retryAfterSeconds</c>; it is never stored. The metric tag is the
/// bucket name constant only; partition keys (networks, token hashes) are never logged or tagged.
/// </summary>
internal sealed class ZaghlolRateLimiters : IDisposable
{
    public const string NetworkBucket = "network";
    public const string TokenBucket = "token";

    /// <summary>The partition prefix of the <c>notifications-apple</c> bucket (memory only, never logged).</summary>
    private const string AppleNotificationsPrefix = "assn:";

    /// <summary>The partition prefix of the <c>notifications-google</c> bucket (memory only, never logged).</summary>
    private const string GoogleNotificationsPrefix = "rtdn:";

    private readonly PartitionedRateLimiter<HttpContext> network;
    private readonly PartitionedRateLimiter<HttpContext> token;

    public ZaghlolRateLimiters(IOptions<RateLimitSettings> settings)
    {
        ArgumentNullException.ThrowIfNull(settings);

        var limits = settings.Value;
        var perNetwork = PartitionedRateLimiter.Create<HttpContext, string>(context =>
            context.GetEndpoint()?.Metadata is { } metadata && metadata.GetMetadata<AppleNotificationRateLimitMetadata>() is not null
                ? RateLimitPartition.GetTokenBucketLimiter(AppleNotificationsPrefix + ClientNetwork.Of(context.Connection.RemoteIpAddress), _ => limits.AppleNotifications.ToOptions())
                : context.GetEndpoint()?.Metadata.GetMetadata<GoogleNotificationRateLimitMetadata>() is not null
                    ? RateLimitPartition.GetTokenBucketLimiter(GoogleNotificationsPrefix + ClientNetwork.Of(context.Connection.RemoteIpAddress), _ => limits.GoogleNotifications.ToOptions())
                    : RateLimitPartition.GetTokenBucketLimiter(ClientNetwork.Of(context.Connection.RemoteIpAddress), _ => limits.PerNetwork.ToOptions()));
        var register = PartitionedRateLimiter.Create<HttpContext, string>(context =>
            context.GetEndpoint()?.Metadata.GetMetadata<RegistrationRateLimitMetadata>() is null
                ? RateLimitPartition.GetNoLimiter(string.Empty)
                : RateLimitPartition.GetTokenBucketLimiter(ClientNetwork.Of(context.Connection.RemoteIpAddress), _ => limits.Register.ToOptions()));
        // Registration first: the middleware retries a refused lease once (AcquireAsync) and a chain charges every limiter
        // before the one that refuses, so this order keeps a registration flood from also draining the /24's general bucket.
        network = PartitionedRateLimiter.CreateChained(register, perNetwork);
        var perToken = PartitionedRateLimiter.Create<HttpContext, string>(context =>
            context.User.FindFirst(InstallTokenAuthentication.TokenHashClaim)?.Value is { } key
                ? RateLimitPartition.GetTokenBucketLimiter(key, _ => limits.PerToken.ToOptions())
                : context.User.FindFirst(OperatorAuthentication.OperatorIdClaim)?.Value is { } operatorId
                    ? RateLimitPartition.GetTokenBucketLimiter("op:" + operatorId, _ => limits.PerToken.ToOptions())
                    : RateLimitPartition.GetNoLimiter(string.Empty));
        var supportLookup = PartitionedRateLimiter.Create<HttpContext, string>(context =>
            context.GetEndpoint()?.Metadata.GetMetadata<SupportLookupRateLimitMetadata>() is not null
            && context.User.FindFirst(OperatorAuthentication.OperatorIdClaim)?.Value is { } lookupOperator
                ? RateLimitPartition.GetTokenBucketLimiter("lookup:" + lookupOperator, _ => limits.SupportLookup.ToOptions())
                : RateLimitPartition.GetNoLimiter(string.Empty));

        // The stricter lookup bucket first, so a refused lookup doesn't also drain the operator's general bucket.
        token = PartitionedRateLimiter.CreateChained(supportLookup, perToken);

        PerNetwork = CreateOptions(network, NetworkBucket);
        PerToken = CreateOptions(token, TokenBucket);
    }

    /// <summary>Before authentication.</summary>
    public RateLimiterOptions PerNetwork { get; }

    /// <summary>After authentication.</summary>
    public RateLimiterOptions PerToken { get; }

    public void Dispose()
    {
        network.Dispose();
        token.Dispose();
    }

    private static RateLimiterOptions CreateOptions(PartitionedRateLimiter<HttpContext> limiter, string bucket) => new()
    {
        GlobalLimiter = limiter,
        RejectionStatusCode = StatusCodes.Status429TooManyRequests,
        OnRejected = async (context, _) =>
        {
            var seconds = context.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter)
                ? (int)Math.Ceiling(retryAfter.TotalSeconds)
                : 1;
            seconds = Math.Max(1, seconds);
            var http = context.HttpContext;
            http.RequestServices.GetService<ZaghlolMetrics>()?.RateLimited(bucket);
            http.Response.Headers.RetryAfter = seconds.ToString(CultureInfo.InvariantCulture);
            await ApiProblems.WriteAsync(http, StatusCodes.Status429TooManyRequests, ErrorCodes.RateLimited, seconds);
        },
    };
}

/// <summary>The rate-limit partition of a client address: its /24 (IPv4) or /56 (IPv6). Memory only, never logged.</summary>
internal static class ClientNetwork
{
    public const string Unknown = "none";

    public static string Of(IPAddress? address)
    {
        if (address is null)
        {
            return Unknown;
        }

        if (address.IsIPv4MappedToIPv6)
        {
            address = address.MapToIPv4();
        }

        var bytes = address.GetAddressBytes();
        if (address.AddressFamily == AddressFamily.InterNetwork)
        {
            bytes[3] = 0;
            return $"{new IPAddress(bytes)}/24";
        }

        for (var i = 7; i < bytes.Length; i++)
        {
            bytes[i] = 0;
        }

        return $"{new IPAddress(bytes)}/56";
    }
}

internal static class RateLimitServiceCollectionExtensions
{
    public const string ForwardedHeadersSection = "ForwardedHeaders";

    /// <summary>
    /// The rate limiters and the forwarded-headers rule: the client address is taken from <c>X-Forwarded-For</c> only when the
    /// direct peer is in <c>ForwardedHeaders:KnownProxies</c> (IP addresses) or <c>ForwardedHeaders:KnownNetworks</c> (CIDR);
    /// the defaults (loopback) are cleared, and the raw header is never read anywhere else. Outside Development and Testing,
    /// <see cref="ForwardedHeadersStartupCheck"/> stops the host when neither list nor <c>ForwardedHeaders:NoProxy=true</c> is set.
    /// </summary>
    public static IServiceCollection AddZaghlolRateLimits(this IServiceCollection services)
    {
        services.AddOptions<RateLimitSettings>().BindConfiguration(RateLimitSettings.Section);
        services.AddRateLimiter(_ => { });
        services.AddSingleton<ZaghlolRateLimiters>();

        services.AddOptions<ForwardedHeadersOptions>().Configure<IConfiguration>((options, configuration) =>
        {
            options.ForwardedHeaders = ForwardedHeaders.XForwardedFor;
            options.ForwardLimit = 1;
            options.KnownProxies.Clear();
            options.KnownIPNetworks.Clear();
            var section = configuration.GetSection(ForwardedHeadersSection);
            foreach (var proxy in section.GetSection("KnownProxies").GetChildren())
            {
                options.KnownProxies.Add(IPAddress.Parse(proxy.Value ?? string.Empty));
            }

            foreach (var network in section.GetSection("KnownNetworks").GetChildren())
            {
                options.KnownIPNetworks.Add(System.Net.IPNetwork.Parse(network.Value ?? string.Empty));
            }
        });
        services.AddHostedService<ForwardedHeadersStartupCheck>();
        return services;
    }
}
