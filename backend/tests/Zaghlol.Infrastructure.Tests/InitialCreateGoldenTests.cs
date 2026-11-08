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
        [nameof(InitialCreateSql.CreateEntitlementView)] = "a64ebd4e02cdd7c5da65ba56815be54a91ebae6814dfe5412adb5f7d26597e2e",
        [nameof(InitialCreateSql.CreateTriggers)] = "9add43021e788a9d583e16b7496d52780b5af23846109551cdc64f1e1ec49fdc",
        [nameof(InitialCreateSql.CreateInvariantTriggers)] = "08983c0aaf18bbf5182fde14466270eb7b8135f0ee7c03fa9e15cd0a62b5703b",
        [nameof(InitialCreateSql.Grants)] = "3267f3499b643226d5495b7ed35f52ca7d09162995553449aacba45478e480d6",
        [nameof(InitialCreateSql.AuditLogRowLevelSecurity)] = "6b3bf5e4f378ba82ec624848dc3c1a0dc20983309c97dda9e5eebcd62c6a74fe",
        [nameof(InitialCreateSql.Comments)] = "26ec38e147466988df3e544424e5ef0c7dccb8016783926b4aa11a0d16510a09",
        [nameof(InitialCreateSql.DropViewAndTriggers)] = "8ed0e92ce88096e9cab6202f1424665fa4e5301b2d5ce5e195a84c3266458aa0",
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
