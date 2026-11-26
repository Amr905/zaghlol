using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using Zaghlol.Api.RateLimiting;
using Zaghlol.Application.Llm;
using Zaghlol.Domain;

namespace Zaghlol.Api.Tests.Llm;

/// <summary>T-349 / ask-llm §4.3: the in-process LLM buckets (no database).</summary>
[Collection(ApiHostGroup.Name)]
public class LlmRateLimiterTests
{
    private static LlmRateLimiter Limiter(Action<RateLimitSettings>? tweak = null, IDictionary<string, string?>? config = null)
    {
        var settings = new RateLimitSettings();
        tweak?.Invoke(settings);
        return new LlmRateLimiter(Options.Create(settings), new ConfigurationBuilder().AddInMemoryCollection(config ?? new Dictionary<string, string?>()).Build());
    }

    private static InstallId NewInstall() => InstallId.Parse(Guid.NewGuid().ToString());

    [Fact]
    public void AnInstallGetsABurstOfThreeThenARefusalNamingTheInstallBucket()
    {
        using var limiter = Limiter();
        var install = NewInstall();

        for (var i = 0; i < 3; i++)
        {
            Assert.True(limiter.TryAcquire(LlmFeature.Ask, install, null, "10.0.0.0/24").Allowed);
        }

        var refused = limiter.TryAcquire(LlmFeature.Ask, install, null, "10.0.0.0/24");
        Assert.False(refused.Allowed);
        Assert.Equal("install", refused.Bucket);
        Assert.InRange(refused.RetryAfterSeconds, 1, 60);
        Assert.True(limiter.TryAcquire(LlmFeature.Ask, NewInstall(), null, "10.0.0.0/24").Allowed);
    }

    [Fact]
    public void TheDayLimitIsTwentyPerInstall()
    {
        using var limiter = Limiter(s => s.AskInstall = new TokenBucketSettings { TokenLimit = 1000, TokensPerPeriod = 1000, PeriodSeconds = 60 });
        var install = NewInstall();

        for (var i = 0; i < 20; i++)
        {
            Assert.True(limiter.TryAcquire(LlmFeature.Ask, install, null, "n").Allowed);
        }

        var refused = limiter.TryAcquire(LlmFeature.Ask, install, null, "n");
        Assert.False(refused.Allowed);
        Assert.Equal("install", refused.Bucket);
    }

    [Fact]
    public void AnAccountHasItsOwnBucketsAcrossInstalls()
    {
        using var limiter = Limiter();
        var account = Guid.NewGuid();

        for (var i = 0; i < 3; i++)
        {
            Assert.True(limiter.TryAcquire(LlmFeature.Ask, NewInstall(), account, "n").Allowed);
        }

        var refused = limiter.TryAcquire(LlmFeature.Ask, NewInstall(), account, "n");
        Assert.False(refused.Allowed);
        Assert.Equal("account", refused.Bucket);
    }

    [Fact]
    public void ANetworkHasThirtyAMinuteAndTheGlobalBucketCapsTheProcess()
    {
        using var network = Limiter();
        for (var i = 0; i < 30; i++)
        {
            Assert.True(network.TryAcquire(LlmFeature.Ask, NewInstall(), null, "10.1.1.0/24").Allowed);
        }

        Assert.Equal("network", network.TryAcquire(LlmFeature.Ask, NewInstall(), null, "10.1.1.0/24").Bucket);
        Assert.True(network.TryAcquire(LlmFeature.Ask, NewInstall(), null, "10.2.2.0/24").Allowed);

        using var global = Limiter(config: new Dictionary<string, string?> { ["Llm:GlobalPerMinute"] = "5" });
        for (var i = 0; i < 5; i++)
        {
            Assert.True(global.TryAcquire(LlmFeature.Ask, NewInstall(), null, "net" + i).Allowed);
        }

        var refused = global.TryAcquire(LlmFeature.Ask, NewInstall(), null, "net-x");
        Assert.False(refused.Allowed);
        Assert.Equal("global", refused.Bucket);
    }

    [Fact]
    public void CategoriseHasItsOwnInstallBucketOfTwoAMinute()
    {
        using var limiter = Limiter();
        var install = NewInstall();

        Assert.True(limiter.TryAcquire(LlmFeature.Categorise, install, null, "n").Allowed);
        Assert.True(limiter.TryAcquire(LlmFeature.Categorise, install, null, "n").Allowed);
        Assert.False(limiter.TryAcquire(LlmFeature.Categorise, install, null, "n").Allowed);

        // The same install still has its Ask burst.
        Assert.True(limiter.TryAcquire(LlmFeature.Ask, install, null, "n").Allowed);
    }
}
