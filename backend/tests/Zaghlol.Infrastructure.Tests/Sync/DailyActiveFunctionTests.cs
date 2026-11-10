using System.Security.Cryptography;
using Npgsql;

namespace Zaghlol.Infrastructure.Tests.Sync;

/// <summary>
/// T-128 security review S3 (migration CountDailyActiveServerDay): <c>zaghlol.count_daily_active</c> takes no day (it uses the
/// database's UTC date whatever the session time zone) and accepts only <c>android</c> or <c>ios</c>; the old signature is gone.
/// Run as the App login, the only one allowed to execute it (<see cref="GrantTests"/>).
/// </summary>
[Collection(SchemaGroup.Name)]
public class DailyActiveFunctionTests(SchemaFixture fixture)
{
    private static string UniqueAppVersion() => "1.0.0-s3" + Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(4));

    [Fact]
    public async Task TheDayIsTheDatabasesUtcDateWhateverTheSessionTimeZone()
    {
        var appVersion = UniqueAppVersion();
        await using (var connection = await Db.OpenAsync(fixture.Database.For("zaghlol_api")))
        {
            // UTC+14: for ten hours of every UTC day its local date is already tomorrow.
            await using (var zone = new NpgsqlCommand("SET TIME ZONE 'Pacific/Kiritimati'", connection))
            {
                await zone.ExecuteNonQueryAsync();
            }

            await using var command = new NpgsqlCommand("SELECT zaghlol.count_daily_active('ios', $1)", connection);
            command.Parameters.Add(new NpgsqlParameter { Value = appVersion });
            await command.ExecuteNonQueryAsync();
        }

        var rows = await Db.QueryAsync(
            fixture.Database.Superuser,
            """
            SELECT day, installs, platform, ((now() AT TIME ZONE 'UTC')::date - day)
            FROM zaghlol.daily_active_counts WHERE app_version = $1
            """,
            appVersion);

        var row = Assert.Single(rows);
        Assert.Equal(1, row[1]);
        Assert.Equal("ios", row[2]);
        Assert.InRange((int)row[3]!, 0, 1); // 1 only if the UTC date turned between the two statements
    }

    [Fact]
    public async Task TwoCallsAddTwoToOneRow()
    {
        var appVersion = UniqueAppVersion();
        await Db.ExecuteAsync(fixture.Database.For("zaghlol_api"), "SELECT zaghlol.count_daily_active('android', $1)", appVersion);
        await Db.ExecuteAsync(fixture.Database.For("zaghlol_api"), "SELECT zaghlol.count_daily_active('android', $1)", appVersion);

        Assert.Equal(
            2L,
            await Db.ScalarAsync(
                fixture.Database.Superuser,
                "SELECT sum(installs)::bigint FROM zaghlol.daily_active_counts WHERE app_version = $1",
                appVersion));
    }

    [Theory]
    [InlineData("x")]
    [InlineData("windows")]
    [InlineData("Android")]
    [InlineData("")]
    public async Task AnUnknownPlatformIsRejectedAndWritesNothing(string platform)
    {
        var appVersion = UniqueAppVersion();

        var error = await Assert.ThrowsAsync<PostgresException>(
            () => Db.ExecuteAsync(fixture.Database.For("zaghlol_api"), "SELECT zaghlol.count_daily_active($1, $2)", platform, appVersion));

        Assert.Equal(PostgresErrorCodes.InvalidParameterValue, error.SqlState);
        Assert.Equal("count_daily_active: unknown platform", error.MessageText); // never the argument
        Assert.Equal(
            0L,
            await Db.ScalarAsync(fixture.Database.Superuser, "SELECT count(*) FROM zaghlol.daily_active_counts WHERE app_version = $1", appVersion));
    }

    [Fact]
    public async Task ANullPlatformIsRejected()
    {
        var error = await Assert.ThrowsAsync<PostgresException>(
            () => Db.ExecuteAsync(fixture.Database.For("zaghlol_api"), "SELECT zaghlol.count_daily_active(NULL, $1)", UniqueAppVersion()));

        Assert.Equal(PostgresErrorCodes.InvalidParameterValue, error.SqlState);
    }

    [Fact]
    public async Task TheCallerCanNoLongerChooseTheDay()
    {
        var error = await Assert.ThrowsAsync<PostgresException>(
            () => Db.ExecuteAsync(fixture.Database.For("zaghlol_api"), "SELECT zaghlol.count_daily_active(DATE '2000-01-01', 'ios', '1.0.0')"));

        Assert.Equal(PostgresErrorCodes.UndefinedFunction, error.SqlState);
        Assert.Equal(
            0L,
            await Db.ScalarAsync(fixture.Database.Superuser, "SELECT count(*) FROM zaghlol.daily_active_counts WHERE day = DATE '2000-01-01'"));
    }

    [Fact]
    public async Task OnlyTheTwoArgumentFunctionExists()
    {
        var signatures = await Db.QueryAsync(
            fixture.Database.Superuser,
            """
            SELECT pg_get_function_identity_arguments(p.oid)
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'zaghlol' AND p.proname = 'count_daily_active'
            """);

        Assert.Equal("p_platform text, p_app_version text", Assert.Single(signatures)[0]);
    }
}
