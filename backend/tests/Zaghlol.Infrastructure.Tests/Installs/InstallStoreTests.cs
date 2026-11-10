using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Installs;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Persistence.Entities;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Installs;

/// <summary>A migrated database of its own and the stores on the App login, built the way the API builds them.</summary>
public sealed class InstallStoreFixture : IAsyncLifetime
{
    private ServiceProvider? services;

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public IServiceProvider Services => services!;

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["ConnectionStrings:App"] = Database.Api })
            .Build();
        var collection = new ServiceCollection();
        collection.AddSingleton<IConfiguration>(configuration);
        collection.AddZaghlolDatabase(DatabaseRole.App);
        collection.AddZaghlolInstallStores();
        services = collection.BuildServiceProvider();
    }

    public async Task DisposeAsync()
    {
        if (services is not null)
        {
            await services.DisposeAsync();
        }

        if (Database is not null)
        {
            await Database.DisposeAsync();
        }
    }
}

/// <summary>T-124: the install and idempotency stores against PostgreSQL, and the FU-021 role binding.</summary>
public class InstallStoreTests(InstallStoreFixture fixture) : IClassFixture<InstallStoreFixture>
{
    private static readonly DateTimeOffset Now = new(2026, 11, 9, 12, 0, 0, TimeSpan.Zero);

    private IInstallStore Installs => fixture.Services.GetRequiredService<IInstallStore>();

    private IIdempotencyStore Idempotency => fixture.Services.GetRequiredService<IIdempotencyStore>();

    [Fact]
    public async Task AReplayRacingTheFirstAuthenticatedCallHasExactlyOneWinner()
    {
        // R3-6: the replay's UPDATE needs the registration columns; the first call's UPDATE needs the old token hash.
        for (var round = 0; round < 25; round++)
        {
            var id = NewInstallId();
            var key = Hash("key-" + round);
            var body = Hash("body-" + round);
            var first = Hash("token-a-" + round);
            Assert.Equal(
                RegistrationOutcome.Created,
                await Installs.RegisterAsync(id, Platform.Android, "1.0.0", first, key, body, Now, CancellationToken.None));

            var replay = Installs.RegisterAsync(id, Platform.Android, "1.0.0", Hash("token-b-" + round), key, body, Now, CancellationToken.None);
            var confirm = Installs.ConfirmFirstUseAsync(id, first, CancellationToken.None);
            await Task.WhenAll(replay, confirm);
            var replayOutcome = await replay;
            var confirmed = await confirm;

            var replayWon = replayOutcome == RegistrationOutcome.Reissued;
            Assert.True(replayWon ^ confirmed, $"round {round}: replay {replayOutcome}, confirm {confirmed}");
            Assert.Equal(replayWon ? RegistrationOutcome.Reissued : RegistrationOutcome.Exists, replayOutcome);
        }
    }

    [Fact]
    public async Task ATokenHashIsFoundOnlyWhileTheInstallIsLive()
    {
        var id = NewInstallId();
        var token = Hash("live-token");
        await Installs.RegisterAsync(id, Platform.Ios, "2.1.0-beta.1", token, Hash("k"), Hash("b"), Now, CancellationToken.None);

        var found = await Installs.FindByTokenHashAsync(token, CancellationToken.None);
        Assert.Equal(new AuthenticatedInstall(id, RegistrationPending: true), found);

        await Installs.DeleteAsync(id, Now, CancellationToken.None);

        Assert.Null(await Installs.FindByTokenHashAsync(token, CancellationToken.None));
        Assert.False(await Installs.ConfirmFirstUseAsync(id, token, CancellationToken.None));
        Assert.Equal(
            RegistrationOutcome.Exists,
            await Installs.RegisterAsync(id, Platform.Ios, "2.1.0-beta.1", Hash("again"), Hash("k"), Hash("b"), Now, CancellationToken.None));
    }

    [Fact]
    public async Task RotationReplacesTheHashOnlyFromTheCurrentToken()
    {
        var id = NewInstallId();
        var first = Hash("rotate-1");
        var second = Hash("rotate-2");
        await Installs.RegisterAsync(id, Platform.Android, "1.0.0", first, Hash("k"), Hash("b"), Now, CancellationToken.None);

        Assert.True(await Installs.RotateTokenAsync(id, first, second, CancellationToken.None));
        Assert.False(await Installs.RotateTokenAsync(id, first, Hash("rotate-3"), CancellationToken.None));
        Assert.Null(await Installs.FindByTokenHashAsync(first, CancellationToken.None));
        Assert.Equal(id, (await Installs.FindByTokenHashAsync(second, CancellationToken.None))?.InstallId);
    }

    [Fact]
    public async Task AClaimIsCompletedIntoAFinalRowThatIsServedOnlyUntilItExpires()
    {
        var id = await RegisteredInstallAsync();
        const string Key = "01JZAGHLLTSTKEY0000000000A";

        var claim = await Idempotency.TryClaimAsync(id, IdempotentOperation.VerifyPurchase, Key, Hash("body"), Now, CancellationToken.None);
        Assert.Equal(IdempotencyClaimKind.Claimed, claim.Kind);
        Assert.False(claim.TakenOver);
        Assert.True(await Idempotency.CompleteAsync(id, IdempotentOperation.VerifyPurchase, Key, claim.ClaimId, Hash("body"), 200, new byte[] { 1, 2, 3 }, Now.AddHours(24), CancellationToken.None));

        var live = await Idempotency.TryClaimAsync(id, IdempotentOperation.VerifyPurchase, Key, Hash("body"), Now.AddHours(23), CancellationToken.None);
        Assert.Equal(IdempotencyClaimKind.Stored, live.Kind);
        Assert.Equal(200, live.Stored!.Status);
        Assert.Equal(Hash("body"), live.Stored.BodySha256.ToArray());

        // Past expires_at, before any purge: never served (R3-6(b)); the key is claimed afresh instead.
        var later = await Idempotency.TryClaimAsync(id, IdempotentOperation.VerifyPurchase, Key, Hash("other"), Now.AddHours(24), CancellationToken.None);
        Assert.Equal(IdempotencyClaimKind.Claimed, later.Kind);
        Assert.False(later.TakenOver);
    }

    [Fact]
    public async Task ASecondClaimOnTheSameKeyIsInProgressWhileTheFirstHoldsIt()
    {
        var id = await RegisteredInstallAsync();
        var other = await RegisteredInstallAsync();
        const string Key = "01JZAGHLLTSTKEY0000000000B";

        var first = await Idempotency.TryClaimAsync(id, IdempotentOperation.SignIn, Key, Hash("b"), Now, CancellationToken.None);
        var second = await Idempotency.TryClaimAsync(id, IdempotentOperation.SignIn, Key, Hash("b"), Now.AddSeconds(30), CancellationToken.None);

        Assert.Equal(IdempotencyClaimKind.Claimed, first.Kind);
        Assert.Equal(IdempotencyClaimKind.InProgress, second.Kind);

        // Another install's same key, and another operation, are different keys.
        Assert.Equal(IdempotencyClaimKind.Claimed, (await Idempotency.TryClaimAsync(other, IdempotentOperation.SignIn, Key, Hash("b"), Now, CancellationToken.None)).Kind);
        Assert.Equal(IdempotencyClaimKind.Claimed, (await Idempotency.TryClaimAsync(id, IdempotentOperation.VerifyPurchase, Key, Hash("b"), Now, CancellationToken.None)).Kind);
    }

    [Fact]
    public async Task ConcurrentClaimsOfOneKeyHaveExactlyOneWinner()
    {
        var id = await RegisteredInstallAsync();
        for (var round = 0; round < 10; round++)
        {
            var key = "01JZAGHLLTSTKEYRACE00000" + round.ToString("00", System.Globalization.CultureInfo.InvariantCulture);
            var claims = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ =>
                Idempotency.TryClaimAsync(id, IdempotentOperation.VerifyPurchase, key, Hash("race"), Now, CancellationToken.None)));

            Assert.Single(claims, c => c.Kind == IdempotencyClaimKind.Claimed);
            Assert.All(claims.Where(c => c.Kind != IdempotencyClaimKind.Claimed), c => Assert.Equal(IdempotencyClaimKind.InProgress, c.Kind));
        }
    }

    [Fact]
    public async Task AnExpiredClaimFromACrashedRequestIsTakenOverAndItsLateCompletionIsLost()
    {
        var id = await RegisteredInstallAsync();
        const string Key = "01JZAGHLLTSTKEY0000000000C";
        var crashed = await Idempotency.TryClaimAsync(id, IdempotentOperation.VerifyPurchase, Key, Hash("b"), Now, CancellationToken.None);

        var takeover = await Idempotency.TryClaimAsync(id, IdempotentOperation.VerifyPurchase, Key, Hash("b"), Now + IdempotencyStore.Lease, CancellationToken.None);

        Assert.Equal(IdempotencyClaimKind.Claimed, takeover.Kind);
        Assert.True(takeover.TakenOver);
        Assert.False(await Idempotency.CompleteAsync(id, IdempotentOperation.VerifyPurchase, Key, crashed.ClaimId, Hash("b"), 200, new byte[] { 7 }, Now.AddHours(24), CancellationToken.None));
        Assert.True(await Idempotency.CompleteAsync(id, IdempotentOperation.VerifyPurchase, Key, takeover.ClaimId, Hash("b"), 422, new byte[] { 8 }, Now.AddHours(24), CancellationToken.None));
        Assert.Equal(422, (await Idempotency.TryClaimAsync(id, IdempotentOperation.VerifyPurchase, Key, Hash("b"), Now.AddMinutes(5), CancellationToken.None)).Stored!.Status);
    }

    [Fact]
    public async Task AReleasedClaimLetsTheNextRequestRunAtOnceAndAnotherRequestCantReleaseIt()
    {
        var id = await RegisteredInstallAsync();
        const string Key = "01JZAGHLLTSTKEY0000000000D";
        var first = await Idempotency.TryClaimAsync(id, IdempotentOperation.VerifyPurchase, Key, Hash("b"), Now, CancellationToken.None);

        await Idempotency.ReleaseAsync(id, IdempotentOperation.VerifyPurchase, Key, Guid.NewGuid(), CancellationToken.None);
        Assert.Equal(IdempotencyClaimKind.InProgress, (await Idempotency.TryClaimAsync(id, IdempotentOperation.VerifyPurchase, Key, Hash("b"), Now, CancellationToken.None)).Kind);

        await Idempotency.ReleaseAsync(id, IdempotentOperation.VerifyPurchase, Key, first.ClaimId, CancellationToken.None);
        Assert.Equal(IdempotencyClaimKind.Claimed, (await Idempotency.TryClaimAsync(id, IdempotentOperation.VerifyPurchase, Key, Hash("b"), Now, CancellationToken.None)).Kind);
    }

    [Fact]
    public async Task ADeletedInstallCantClaimAndADeleteRacingAClaimLeavesNoRow()
    {
        // S-4: the claim and the completion insert only while the install exists and isn't deleted.
        var id = await RegisteredInstallAsync();
        const string Key = "01JZAGHLLTSTKEY0000000000E";
        var claim = await Idempotency.TryClaimAsync(id, IdempotentOperation.VerifyPurchase, Key, Hash("b"), Now, CancellationToken.None);
        Assert.Equal(IdempotencyClaimKind.Claimed, claim.Kind);

        await Installs.DeleteAsync(id, Now, CancellationToken.None);

        Assert.False(await Idempotency.CompleteAsync(id, IdempotentOperation.VerifyPurchase, Key, claim.ClaimId, Hash("b"), 200, new byte[] { 1 }, Now.AddHours(24), CancellationToken.None));
        Assert.Equal(IdempotencyClaimKind.NoInstall, (await Idempotency.TryClaimAsync(id, IdempotentOperation.VerifyPurchase, Key, Hash("b"), Now, CancellationToken.None)).Kind);
        Assert.Equal(0L, await RowsOf(id));

        // Many deletes racing many claims: never a row left for a deleted install.
        for (var round = 0; round < 10; round++)
        {
            var racer = await RegisteredInstallAsync();
            var claims = Enumerable.Range(0, 4).Select(i => Idempotency.TryClaimAsync(
                racer, IdempotentOperation.VerifyPurchase, "01JZAGHLLTSTKEYDEL000000" + i.ToString("00", System.Globalization.CultureInfo.InvariantCulture), Hash("b"), Now, CancellationToken.None));
            var delete = Installs.DeleteAsync(racer, Now, CancellationToken.None);
            await Task.WhenAll([.. claims, delete]);
            Assert.Equal(0L, await RowsOf(racer));
        }
    }

    private async Task<InstallId> RegisteredInstallAsync()
    {
        var id = NewInstallId();
        Assert.Equal(
            RegistrationOutcome.Created,
            await Installs.RegisterAsync(id, Platform.Android, "1.0.0", Hash("token-" + id), Hash("k" + id), Hash("b" + id), Now, CancellationToken.None));
        return id;
    }

    private async Task<long> RowsOf(InstallId id)
    {
        await using var connection = new NpgsqlConnection(fixture.Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT count(*) FROM zaghlol.idempotency_records WHERE install_id = @i", connection);
        command.Parameters.AddWithValue("i", id.Value);
        return (long)(await command.ExecuteScalarAsync())!;
    }

    [Fact]
    public async Task TheAppFactoryLogsInAsTheAppRoleWithoutAdminGrants()
    {
        // FU-021: the /v1 factory is bound to app_rw; an admin-only write fails from it.
        await using var db = fixture.Services.GetRequiredService<IAppDbContextFactory>().CreateDbContext();

        var user = await db.Database.SqlQuery<string>($"SELECT current_user::text AS \"Value\"").ToListAsync();
        Assert.Equal(["zaghlol_api"], user);

        var error = await Assert.ThrowsAsync<PostgresException>(() => db.Database.ExecuteSqlRawAsync("DELETE FROM zaghlol.feature_flags WHERE false"));
        Assert.Equal(PostgresErrorCodes.InsufficientPrivilege, error.SqlState);
    }

    [Fact]
    public void TheStoresDependOnlyOnTheAppFactory()
    {
        Assert.False(typeof(IZaghlolDbContextFactory).IsVisible);
        foreach (var store in new[] { typeof(InstallStore), typeof(IdempotencyStore) })
        {
            var dependencies = store.GetConstructors(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                .SelectMany(c => c.GetParameters())
                .Select(p => p.ParameterType)
                .Concat(store.GetFields(BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public).Select(f => f.FieldType))
                .ToList();

            Assert.Contains(typeof(IAppDbContextFactory), dependencies);
            Assert.DoesNotContain(typeof(IZaghlolDbContextFactory), dependencies);
            Assert.DoesNotContain(typeof(DatabaseRole), dependencies);
        }
    }

    private static InstallId NewInstallId() => InstallId.FromGuid(Guid.NewGuid());

    private static byte[] Hash(string text) => SHA256.HashData(Encoding.UTF8.GetBytes(text));
}

/// <summary>T-138 tests m7: EF sensitive-data logging (parameter values in logs) is banned.</summary>
public class SensitiveDataLoggingTests
{
    private const string Banned = "EnableSensitive" + "DataLogging";

    [Fact]
    public void NoSourceFileEnablesIt()
    {
        var src = SourceRoot();
        var offenders = Directory.EnumerateFiles(src, "*.cs", SearchOption.AllDirectories)
            .Where(f => File.ReadAllText(f).Contains(Banned, StringComparison.Ordinal))
            .Select(f => Path.GetRelativePath(src, f))
            .ToList();

        Assert.True(Directory.Exists(Path.Combine(src, "Zaghlol.Infrastructure")), src);
        Assert.Empty(offenders);
    }

    [Fact]
    public void TheBuiltOptionsHaveItDisabled()
    {
        var options = ZaghlolDbContextOptions.Create("Host=localhost;Database=none");

        var core = options.FindExtension<CoreOptionsExtension>();

        Assert.NotNull(core);
        Assert.False(core.IsSensitiveDataLoggingEnabled);
    }

    private static string SourceRoot()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            var candidate = Path.Combine(dir.FullName, "src");
            if (Directory.Exists(Path.Combine(candidate, "Zaghlol.Api")))
            {
                return candidate;
            }
        }

        throw new DirectoryNotFoundException("backend/src not found above the test output directory.");
    }
}
