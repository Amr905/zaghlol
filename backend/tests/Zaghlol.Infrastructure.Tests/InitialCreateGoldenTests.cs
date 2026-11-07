using System.Security.Cryptography;
using System.Text;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>
/// CR#2: the raw SQL InitialCreate runs is frozen. The grants are rendered from <see cref="GrantMatrix.InitialCreate"/>
/// and its column lists, so an innocent-looking edit there would change what a fresh database gets while production
/// keeps the old grants. Each block's SHA-256 is pinned here. If this fails, don't update the hash: put the change in
/// a new migration.
/// </summary>
public class InitialCreateGoldenTests
{
    private static readonly Dictionary<string, string> Pinned = new(StringComparer.Ordinal)
    {
        [nameof(InitialCreateSql.CreateEntitlementView)] = "pending",
        [nameof(InitialCreateSql.CreateTriggers)] = "pending",
        [nameof(InitialCreateSql.CreateInvariantTriggers)] = "pending",
        [nameof(InitialCreateSql.Grants)] = "pending",
        [nameof(InitialCreateSql.AuditLogRowLevelSecurity)] = "pending",
        [nameof(InitialCreateSql.Comments)] = "pending",
        [nameof(InitialCreateSql.DropViewAndTriggers)] = "pending",
    };

    public static TheoryData<string> Blocks => [.. Pinned.Keys];

    [Theory]
    [MemberData(nameof(Blocks))]
    public void TheSqlOfInitialCreateIsUnchanged(string block)
    {
        var sql = block switch
        {
            nameof(InitialCreateSql.CreateEntitlementView) => InitialCreateSql.CreateEntitlementView,
            nameof(InitialCreateSql.CreateTriggers) => InitialCreateSql.CreateTriggers,
            nameof(InitialCreateSql.CreateInvariantTriggers) => InitialCreateSql.CreateInvariantTriggers,
            nameof(InitialCreateSql.Grants) => InitialCreateSql.Grants,
            nameof(InitialCreateSql.AuditLogRowLevelSecurity) => InitialCreateSql.AuditLogRowLevelSecurity,
            nameof(InitialCreateSql.Comments) => InitialCreateSql.Comments,
            nameof(InitialCreateSql.DropViewAndTriggers) => InitialCreateSql.DropViewAndTriggers,
            _ => throw new ArgumentOutOfRangeException(nameof(block)),
        };

        var actual = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(sql)));

        Assert.True(
            string.Equals(Pinned[block], actual, StringComparison.Ordinal),
            $"InitialCreateSql.{block} changed (sha256 {actual}). InitialCreate is frozen: put the change in a new migration.");
    }

    [Fact]
    public void TheGrantsBlockIsExactlyTheRenderedFrozenList()
    {
        Assert.Equal(GrantMatrix.ToSql(GrantMatrix.InitialCreate), InitialCreateSql.Grants);
    }
}
