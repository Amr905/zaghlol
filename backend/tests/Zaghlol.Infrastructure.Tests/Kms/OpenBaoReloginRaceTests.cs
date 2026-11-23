using System.Diagnostics;
using System.Net;
using System.Runtime.Versioning;
using System.Security.Cryptography.X509Certificates;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>
/// FU-266 N1: callers refused together (a revoked token) wait for the one forced login and retry with its token instead of
/// failing with a retryable 503. A real denial still fails after that login, and a failed or hung login releases every waiter.
/// </summary>
[SupportedOSPlatform("linux")]
public sealed class OpenBaoReloginRaceTests : IAsyncLifetime
{
    private const int Callers = 48;
    private const string HmacPath = "transit/hmac/audit/sha2-256";

    private OpenBaoTestBed bed = null!;

    public async Task InitializeAsync() => bed = await OpenBaoTestBed.CreateAsync();

    public async Task DisposeAsync() => await bed.DisposeAsync();

    [LinuxFact]
    public async Task ParallelCallersAfterARevocationShareOneLoginAndAllSucceed()
    {
        var clock = new ShiftedClock();
        using var client = Client(clock, TimeSpan.FromSeconds(10));
        await WarmUpAsync(client);
        bed.Stub.LoginDelay = TimeSpan.FromMilliseconds(200);

        // Several rounds, each past the forced-login interval, to hit the window where a refused caller arrives before the
        // winner has cleared the session (before the fix that caller failed instead of waiting).
        for (var round = 0; round < 5; round++)
        {
            clock.Shift += OpenBaoClient.ForcedLoginInterval + TimeSpan.FromSeconds(1);
            var attempts = bed.Stub.LoginAttempts;
            bed.Stub.RevokeAllTokens();

            var statuses = await RaceAsync(client);

            Assert.All(statuses, s => Assert.Equal(HttpStatusCode.OK, s));
            Assert.Equal(attempts + 1, bed.Stub.LoginAttempts);
        }
    }

    [LinuxFact]
    public async Task APolicyDenialStillFailsAfterTheSharedLogin()
    {
        using var client = Client(TimeProvider.System, TimeSpan.FromSeconds(10));
        await WarmUpAsync(client);
        bed.Stub.LoginDelay = TimeSpan.FromMilliseconds(200);
        bed.Stub.SetPolicy("zaghlol-api", "path \"transit/keys/x\" {\n  capabilities = [\"read\"]\n}\n");
        var attempts = bed.Stub.LoginAttempts;
        bed.Stub.RevokeAllTokens();

        var outcomes = await RaceAsync(client);

        Assert.All(outcomes, s => Assert.Null(s));
        Assert.Equal(attempts + 1, bed.Stub.LoginAttempts);
    }

    [LinuxTheory]
    [InlineData("fails")]
    [InlineData("hangs")]
    public async Task AFailedLoginReleasesEveryWaiterWithTheUsualError(string fault)
    {
        using var client = Client(TimeProvider.System, TimeSpan.FromSeconds(1));
        await WarmUpAsync(client);
        bed.Stub.LoginDelay = fault == "hangs" ? TimeSpan.FromSeconds(30) : TimeSpan.FromMilliseconds(200);
        bed.Stub.FailLogins = fault == "fails";
        var attempts = bed.Stub.LoginAttempts;
        bed.Stub.RevokeAllTokens();
        var watch = Stopwatch.StartNew();

        // No caller token: only the client's login bound may release them.
        var outcomes = await RaceAsync(client).WaitAsync(TimeSpan.FromSeconds(10));

        Assert.All(outcomes, s => Assert.Null(s));
        Assert.Equal(attempts + 1, bed.Stub.LoginAttempts);
        Assert.True(watch.Elapsed < TimeSpan.FromSeconds(5), $"waiters released after {watch.Elapsed}");
    }

    [LinuxFact]
    public async Task AfterAFailedForcedLoginTheNextCallersWaitOutTheIntervalBeforeAnotherLogin()
    {
        var clock = new ShiftedClock();
        using var client = Client(clock, TimeSpan.FromSeconds(10));
        await WarmUpAsync(client);
        clock.Shift += OpenBaoClient.ForcedLoginInterval + TimeSpan.FromSeconds(1);
        bed.Stub.FailLogins = true;
        var attempts = bed.Stub.LoginAttempts;
        bed.Stub.RevokeAllTokens();

        Assert.Null((await RaceAsync(client))[0]);
        Assert.Equal(attempts + 1, bed.Stub.LoginAttempts);

        // The server is back, but the session is empty: before the fix this caller logged in at once, unthrottled.
        bed.Stub.FailLogins = false;
        Assert.Null((await RaceAsync(client))[0]);
        Assert.Equal(attempts + 1, bed.Stub.LoginAttempts);

        clock.Shift += OpenBaoClient.ForcedLoginInterval + TimeSpan.FromSeconds(1);
        Assert.All(await RaceAsync(client), s => Assert.Equal(HttpStatusCode.OK, s));
        Assert.Equal(attempts + 2, bed.Stub.LoginAttempts);
    }

    [LinuxFact]
    public async Task NoRequestFailsAcrossTokenExpiries()
    {
        // FU-285: the token is renewed at two thirds of its lease, so stepping the clock across several lifetimes never
        // surfaces a refusal or an error.
        bed.Stub.TokenTtlSeconds = 30;
        var clock = new ShiftedClock();
        using var client = Client(clock, TimeSpan.FromSeconds(10));
        await WarmUpAsync(client);
        var attempts = bed.Stub.LoginAttempts;

        for (var step = 0; step < 6; step++)
        {
            clock.Shift += TimeSpan.FromSeconds(21);
            Assert.All(await RaceAsync(client), s => Assert.Equal(HttpStatusCode.OK, s));
        }

        Assert.Equal(attempts + 6, bed.Stub.LoginAttempts);
    }

    private OpenBaoClient Client(TimeProvider clock, TimeSpan loginTimeout)
    {
        var roots = new X509Certificate2Collection { bed.Stub.Ca.Certificate };
        var role = bed.ApiRole;
        return new OpenBaoClient(
            bed.Stub.Address,
            OpenBaoClient.CreateHandler(roots, TimeSpan.FromSeconds(5)),
            () => new OpenBaoCredentials(role.RoleId, role.SecretId),
            clock,
            loginTimeout);
    }

    private static async Task WarmUpAsync(OpenBaoClient client)
    {
        using var answer = await client.SendAsync(HttpMethod.Post, HmacPath, w => w.WriteString("input", "AA=="), CancellationToken.None);
        Assert.Equal(HttpStatusCode.OK, answer.Status);
    }

    /// <summary>Each caller's status, or <c>null</c> when it failed with the adapter's constant error.</summary>
    private static async Task<HttpStatusCode?[]> RaceAsync(OpenBaoClient client)
    {
        using var start = new ManualResetEventSlim();
        var calls = Enumerable.Range(0, Callers).Select(_ => Task.Run(async () =>
        {
            start.Wait();
            try
            {
                using var answer = await client.SendAsync(HttpMethod.Post, HmacPath, w => w.WriteString("input", "AA=="), CancellationToken.None);
                return (HttpStatusCode?)answer.Status;
            }
            catch (OpenBaoUnavailableException ex)
            {
                Assert.Equal(OpenBaoUnavailableException.DefaultMessage, ex.Message);
                return null;
            }
        })).ToArray();
        start.Set();
        return await Task.WhenAll(calls);
    }

    /// <summary>System time moved forward by <see cref="Shift"/> (to pass the forced-login interval without waiting).</summary>
    private sealed class ShiftedClock : TimeProvider
    {
        public TimeSpan Shift { get; set; }

        public override DateTimeOffset GetUtcNow() => base.GetUtcNow() + Shift;

        public override long GetTimestamp() => base.GetTimestamp() + (long)(Shift.TotalSeconds * TimestampFrequency);
    }
}
