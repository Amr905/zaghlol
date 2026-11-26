using System.Threading.RateLimiting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Ask;
using Zaghlol.Domain;

namespace Zaghlol.Api.RateLimiting;

/// <summary>
/// The LLM buckets of ask-llm §4.3, in process memory (with N API instances the effective limit is up to N times higher, as for
/// <see cref="ZaghlolRateLimiters"/>): per install and per account a token bucket (burst, per minute) and a sliding day, per client network a token bucket, and
/// one global per-minute bucket. The owner buckets (install, account) are drawn before attestation and the shared ones (/24, global) only after it passed (FU-432), so an unattested caller can't drain them.
/// The keys (install ids, accounts, networks) are memory only and are never logged or tagged; only the fixed bucket name leaves.
/// </summary>
internal sealed class LlmRateLimiter : ILlmRateLimiter, IDisposable
{
    public const string InstallBucket = "install";
    public const string AccountBucket = "account";
    public const string NetworkBucket = "network";
    public const string GlobalBucket = "global";

    private readonly PartitionedRateLimiter<string> installMinute;
    private readonly PartitionedRateLimiter<string> installDay;
    private readonly PartitionedRateLimiter<string> accountMinute;
    private readonly PartitionedRateLimiter<string> accountDay;
    private readonly PartitionedRateLimiter<string> network;
    private readonly PartitionedRateLimiter<string> attempts;
    private readonly RateLimiter global;

    public LlmRateLimiter(IOptions<RateLimitSettings> options, IConfiguration configuration)
    {
        var s = options.Value;
        TokenBucketRateLimiterOptions Minute(LlmFeature f, bool account) => f == LlmFeature.Ask
            ? (account ? s.AskAccount : s.AskInstall).ToOptions()
            : s.CatInstall.ToOptions();
        int Day(LlmFeature f, bool account) => f == LlmFeature.Ask ? (account ? s.AskAccountPerDay : s.AskInstallPerDay) : s.CatInstallPerDay;
        static LlmFeature FeatureOf(string key) => key.StartsWith("ask:", StringComparison.Ordinal) ? LlmFeature.Ask : LlmFeature.Categorise;

        installMinute = PartitionedRateLimiter.Create<string, string>(key => RateLimitPartition.GetTokenBucketLimiter(key, _ => Minute(FeatureOf(key), false)));
        accountMinute = PartitionedRateLimiter.Create<string, string>(key => RateLimitPartition.GetTokenBucketLimiter(key, _ => Minute(FeatureOf(key), true)));
        installDay = PartitionedRateLimiter.Create<string, string>(key => RateLimitPartition.GetSlidingWindowLimiter(key, _ => DayWindow(Day(FeatureOf(key), false))));
        accountDay = PartitionedRateLimiter.Create<string, string>(key => RateLimitPartition.GetSlidingWindowLimiter(key, _ => DayWindow(Day(FeatureOf(key), true))));
        network = PartitionedRateLimiter.Create<string, string>(key => RateLimitPartition.GetTokenBucketLimiter(key, _ => s.AskNetwork.ToOptions()));

        attempts = PartitionedRateLimiter.Create<string, string>(key => RateLimitPartition.GetTokenBucketLimiter(key, _ => s.LlmAttemptNetwork.ToOptions()));

        // ask-llm §4.3 names the global key Llm:GlobalPerMinute; RateLimits:LlmGlobalPerMinute overrides it when both are set.
        var perMinute = int.TryParse(configuration["Llm:GlobalPerMinute"], out var configured) && configured > 0 ? configured : s.LlmGlobalPerMinute;
        if (configuration["RateLimits:LlmGlobalPerMinute"] is not null)
        {
            perMinute = s.LlmGlobalPerMinute;
        }

        global = new FixedWindowRateLimiter(new FixedWindowRateLimiterOptions
        {
            PermitLimit = Math.Max(1, perMinute),
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0,
            AutoReplenishment = true,
        });
    }

    public LlmRateDecision TryAcquire(LlmFeature feature, InstallId install, Guid? account, string networkKey, LlmRateStage stage)
    {
        ArgumentNullException.ThrowIfNull(networkKey);
        var prefix = feature == LlmFeature.Ask ? "ask:" : "cat:";
        if (stage == LlmRateStage.Shared)
        {
            return Refused(network.AttemptAcquire(prefix + networkKey), NetworkBucket) ?? Refused(global.AttemptAcquire(), GlobalBucket) ?? LlmRateDecision.Ok;
        }

        // B96-m2: a generous per-/24 cap on attempts before attestation, so junk proofs can't spend the attestation provider's quota.
        if (Refused(attempts.AttemptAcquire(networkKey), NetworkBucket) is { } a0)
        {
            return a0;
        }

        var installKey = prefix + install;

        if (Refused(installMinute.AttemptAcquire(installKey), InstallBucket) is { } a1)
        {
            return a1;
        }

        if (Refused(installDay.AttemptAcquire(installKey), InstallBucket) is { } a2)
        {
            return a2;
        }

        if (account is { } accountId)
        {
            var accountKey = prefix + accountId.ToString("N");
            if (Refused(accountMinute.AttemptAcquire(accountKey), AccountBucket) is { } b1)
            {
                return b1;
            }

            if (Refused(accountDay.AttemptAcquire(accountKey), AccountBucket) is { } b2)
            {
                return b2;
            }
        }

        return LlmRateDecision.Ok;
    }

    public void Dispose()
    {
        installMinute.Dispose();
        installDay.Dispose();
        accountMinute.Dispose();
        accountDay.Dispose();
        network.Dispose();
        attempts.Dispose();
        global.Dispose();
    }

    private static SlidingWindowRateLimiterOptions DayWindow(int perDay) => new()
    {
        PermitLimit = Math.Max(1, perDay),
        Window = TimeSpan.FromHours(24),
        SegmentsPerWindow = 24,
        QueueLimit = 0,
        AutoReplenishment = true,
    };

    private static LlmRateDecision? Refused(RateLimitLease lease, string bucket)
    {
        using (lease)
        {
            if (lease.IsAcquired)
            {
                return null;
            }

            var seconds = lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter) ? (int)Math.Ceiling(retryAfter.TotalSeconds) : 60;
            return new LlmRateDecision(false, bucket, Math.Max(1, seconds));
        }
    }
}
