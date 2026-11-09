using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Observability;

/// <summary>T-138 / design note: <c>installHash</c> under a monthly log key derived in memory from the pepper through the KMS.</summary>
public sealed partial class LogPseudonymizerTests
{
    private static readonly InstallId InstallA = InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77");
    private static readonly InstallId InstallB = InstallId.Parse("6f1d2c3b-4a59-4e68-8f70-112233445566");

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

        var first = await pseudonymizer.InstallHashAsync(InstallA, CancellationToken.None);
        var again = await pseudonymizer.InstallHashAsync(InstallA, CancellationToken.None);
        var other = await pseudonymizer.InstallHashAsync(InstallB, CancellationToken.None);

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

        var november = await pseudonymizer.InstallHashAsync(InstallA, CancellationToken.None);
        clock.Now = new DateTimeOffset(2026, 12, 1, 0, 0, 0, TimeSpan.Zero);
        var december = await pseudonymizer.InstallHashAsync(InstallA, CancellationToken.None);

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

    // T-138 tests m6: which log key source AddZaghlolLogPseudonymizer picks.
    [Fact]
    public void WithAKmsTheLogKeyComesFromTheKeyedHasher()
    {
        using var kms = FakeKms.CreateDefault();
        using var services = kms.BuildServices(configure: s =>
        {
            s.AddSingleton<IHostEnvironment>(new HostEnvironment(Environments.Production));
            s.AddZaghlolLogPseudonymizer();
        });

        Assert.IsType<KmsLogKeySource>(services.GetRequiredService<ILogKeySource>());
    }

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    public void WithoutAKmsTheLogKeyIsRefusedOutsideDevelopmentAndTesting(string environment)
    {
        var services = new ServiceCollection();
        services.AddSingleton<IHostEnvironment>(new HostEnvironment(environment));
        services.AddSingleton(TimeProvider.System);
        services.AddZaghlolLogPseudonymizer();
        using var provider = services.BuildServiceProvider();

        var error = Assert.Throws<InvalidOperationException>(() => provider.GetRequiredService<ILogKeySource>());
        Assert.Contains("outside Development and Testing", error.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("Development")]
    [InlineData("Testing")]
    public void WithoutAKmsDevelopmentAndTestingUseAnEphemeralKey(string environment)
    {
        var services = new ServiceCollection();
        services.AddSingleton<IHostEnvironment>(new HostEnvironment(environment));
        services.AddZaghlolLogPseudonymizer();
        using var provider = services.BuildServiceProvider();

        Assert.IsType<EphemeralLogKeySource>(provider.GetRequiredService<ILogKeySource>());
    }

    private sealed class HostEnvironment(string name) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = name;

        public string ApplicationName { get; set; } = "Zaghlol.Tests";

        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;

        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
