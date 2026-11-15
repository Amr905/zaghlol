using Npgsql;
using Zaghlol.Infrastructure.Accounts;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Accounts;

/// <summary>
/// T-135 review minor 1: sign-in locks the union of the purchases it will touch (the buying install's unlinked ones and the
/// account's linked ones) in one ascending-ID statement before it attaches, so a concurrent restore or delete, which also lock in
/// ascending ID, queues behind it instead of interleaving.
/// </summary>
[Collection(SchemaGroup.Name)]
public class AccountPurchaseLockOrderTests(SchemaFixture fixture)
{
    [Fact]
    public async Task SignInLocksTheUnionOfAttachAndAccountPurchasesBeforeAttaching()
    {
        var db = fixture.Database;
        var install = await Rows.InsertAsync(db, "installs");
        var account = await Rows.InsertAsync(db, "accounts");
        var installId = (Guid)install["id"]!;
        var accountId = (Guid)account["id"]!;
        // P1 is the buyer's unlinked purchase; P3 is already linked to the account (and bought elsewhere). Both must be locked.
        var unlinked = await Rows.InsertAsync(db, "purchases", new Dictionary<string, object?> { ["install_id"] = installId });
        var linked = await Rows.InsertAsync(db, "purchases", new Dictionary<string, object?> { ["account_id"] = accountId, ["account_linked_by"] = "signin" });
        var unrelated = await Rows.InsertAsync(db, "purchases");

        await using var signIn = await Db.OpenAsync(db.Api);
        await using var transaction = await signIn.BeginTransactionAsync();
        await new NpgsqlAccountTxStore(signIn, transaction).LockPurchasesAsync(installId, accountId, CancellationToken.None);

        foreach (var id in new[] { (Guid)unlinked["id"]!, (Guid)linked["id"]! })
        {
            var error = await Assert.ThrowsAsync<PostgresException>(() =>
                Db.ScalarAsync(db.Api, "SELECT id FROM zaghlol.purchases WHERE id = $1 FOR UPDATE NOWAIT", id));
            Assert.Equal(PostgresErrorCodes.LockNotAvailable, error.SqlState);
        }

        // A purchase of nobody involved is not locked.
        Assert.NotNull(await Db.ScalarAsync(db.Api, "SELECT id FROM zaghlol.purchases WHERE id = $1 FOR UPDATE NOWAIT", (Guid)unrelated["id"]!));
        await transaction.RollbackAsync();
    }
}
