using System.Net;
using Npgsql;
using Zaghlol.Api.Tests.Installs;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Purchases;

/// <summary>
/// FU-052 S-2: with the App pool capped at 3 connections, 10 concurrent verifies (distinct keys) whose Play read takes 2 s all
/// succeed, because no connection or transaction is held while the handler waits on Play. The old design (an advisory-lock
/// transaction held across the handler, plus the handler's own connection) timed out on the pool here.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class IdempotencyPoolTests(SmallPoolPurchasesHostFixture fixture) : IClassFixture<SmallPoolPurchasesHostFixture>
{
    [Fact]
    public async Task TenSlowVerifiesShareAThreeConnectionPoolWithoutHoldingAConnectionDuringTheHandler()
    {
        var (installId, install) = await fixture.NewInstallAsync();
        var binding = StoreBindingRef.Compute(InstallId.Parse(installId));
        var tokens = Enumerable.Range(0, 10).Select(_ => PurchasesHostFixture.NewPlayToken()).ToArray();
        foreach (var token in tokens)
        {
            fixture.Play.Get(PlayWireMock.SubscriptionPath(token), 200, PlayWireMock.SubscriptionBody(binding, acknowledged: true), delay: TimeSpan.FromSeconds(2));
        }

        var requests = tokens.Select(t => fixture.VerifyAsync(install, PurchasesHostFixture.AndroidBody(PlayWireMock.Yearly, t))).ToArray();

        // While every handler waits on Play: no App session sits in an open transaction, and the pool never exceeds 3.
        var probes = new List<(long InTransaction, long Total)>();
        for (var i = 0; i < 6; i++)
        {
            await Task.Delay(250);
            probes.Add(await ProbeAsync());
        }

        var responses = await Task.WhenAll(requests);
        try
        {
            Assert.All(responses, r => Assert.Equal(HttpStatusCode.OK, r.StatusCode));
            Assert.All(probes, p => Assert.Equal(0, p.InTransaction));
            Assert.All(probes, p => Assert.True(p.Total <= 3, $"{p.Total} App connections"));
            foreach (var token in tokens)
            {
                Assert.Equal("active", (await fixture.RowAsync(token))!.Value.State);
            }
        }
        finally
        {
            foreach (var response in responses)
            {
                response.Dispose();
            }
        }
    }

    private async Task<(long InTransaction, long Total)> ProbeAsync()
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            """
            SELECT count(*) FILTER (WHERE state LIKE 'idle in transaction%'), count(*)
            FROM pg_stat_activity WHERE usename = 'zaghlol_api'
            """,
            connection);
        await using var reader = await command.ExecuteReaderAsync();
        await reader.ReadAsync();
        return (reader.GetInt64(0), reader.GetInt64(1));
    }
}
