using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.Tests.Observability;

/// <summary>T-138 / design note: <c>installHash</c> under a monthly log key derived in memory from the pepper through the KMS.</summary>
public sealed partial class LogPseudonymizerTests
{
    [GeneratedRegex("^[0-9a-f]{16}$")]
    private static partial Regex Hex16();

    private sealed class MonthKeys : ILogKeySource
    {
        public List<string> Requested { get; } = [];

        public ValueTask<byte[]> GetKeyAsync(string month, CancellationToken cancellationToken)
        {
            Requested.Add(month);
            return ValueTask.FromResult(SHA256.HashData(Encoding.UTF8.GetBytes("k" + month)));
        }
    }

    private sealed class Clock(DateTimeOffset start) : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = start;

        public override DateTimeOffset GetUtcNow() => Now;
    }

    private sealed class CapturingHasher : IKeyedHasher
    {
        public List<(KeyedHashKey Key, byte[] Data)> Calls { get; } = [];

        public ValueTask<byte[]> HmacSha256Async(KeyedHashKey key, ReadOnlyMemory<byte> data, CancellationToken cancellationToken)
        {
            Calls.Add((key, data.ToArray()));
            return ValueTask.FromResult(new byte[32]);
        }
    }

    [Fact]
    public async Task TheHashIsSixteenHexCharactersAndStableWithinAMonth()
    {
        var keys = new MonthKeys();
        var clock = new Clock(new DateTimeOffset(2026, 11, 8, 0, 0, 0, TimeSpan.Zero));
        var pseudonymizer = new LogPseudonymizer(keys, clock);

        var first = await pseudonymizer.InstallHashAsync("install-a", CancellationToken.None);
        var again = await pseudonymizer.InstallHashAsync("install-a", CancellationToken.None);
        var other = await pseudonymizer.InstallHashAsync("install-b", CancellationToken.None);

        Assert.Matches(Hex16(), first);
        Assert.Equal(first, again);
        Assert.NotEqual(first, other);
        Assert.Equal(["2026-11"], keys.Requested);
    }

    [Fact]
    public async Task TheKeyRotatesEveryMonth()
    {
        var keys = new MonthKeys();
        var clock = new Clock(new DateTimeOffset(2026, 11, 30, 23, 59, 0, TimeSpan.Zero));
        var pseudonymizer = new LogPseudonymizer(keys, clock);

        var november = await pseudonymizer.InstallHashAsync("install-a", CancellationToken.None);
        clock.Now = new DateTimeOffset(2026, 12, 1, 0, 0, 0, TimeSpan.Zero);
        var december = await pseudonymizer.InstallHashAsync("install-a", CancellationToken.None);

        Assert.NotEqual(november, december);
        Assert.Equal(["2026-11", "2026-12"], keys.Requested);
    }

    [Fact]
    public async Task TheMonthlyKeyIsDerivedFromThePepperWithTheLogLabel()
    {
        var hasher = new CapturingHasher();

        await new KmsLogKeySource(hasher).GetKeyAsync("2026-11", CancellationToken.None);

        var call = Assert.Single(hasher.Calls);
        Assert.Equal(KeyedHashKey.InstallHashPepper, call.Key);
        Assert.Equal(Encoding.UTF8.GetBytes("zaghlol-log-v1\02026-11"), call.Data);
    }
}
