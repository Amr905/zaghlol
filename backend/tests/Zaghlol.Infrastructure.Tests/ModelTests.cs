using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Metadata;
using Zaghlol.Infrastructure.Persistence;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>Model-level checks that need no database.</summary>
public partial class ModelTests
{
    private static readonly IModel Model = CreateModel();

    // Enum columns whose documented column has no IN (...) CHECK.
    private static readonly HashSet<string> EnumColumnsWithoutCheck =
        new(["purchase_events.from_state", "purchase_events.to_state"], StringComparer.Ordinal);

    [Fact]
    public void EveryEnumMappingEqualsItsColumnsCheckValues()
    {
        var problems = new List<string>();
        var compared = 0;
        foreach (var entity in Model.GetEntityTypes().Where(e => e.GetTableName() is not null))
        {
            var table = entity.GetTableName()!;
            foreach (var property in entity.GetProperties())
            {
                var enumType = Nullable.GetUnderlyingType(property.ClrType) ?? property.ClrType;
                if (!enumType.IsEnum)
                {
                    continue;
                }

                var column = property.GetColumnName();
                var converter = property.GetValueConverter();
                Assert.NotNull(converter);
                var mapped = Enum.GetValues(enumType).Cast<object>()
                    .Select(v => (string)converter.ConvertToProvider(v)!)
                    .ToHashSet(StringComparer.Ordinal);

                var check = entity.GetCheckConstraints().SingleOrDefault(c => c.Sql.StartsWith(column + " IN (", StringComparison.Ordinal));
                if (check is null)
                {
                    if (!EnumColumnsWithoutCheck.Contains($"{table}.{column}"))
                    {
                        problems.Add($"{table}.{column}: enum without an IN CHECK");
                    }

                    continue;
                }

                var allowed = Quoted().Matches(check.Sql).Select(m => m.Groups[1].Value).ToHashSet(StringComparer.Ordinal);
                if (!allowed.SetEquals(mapped))
                {
                    problems.Add($"{table}.{column}: CHECK [{string.Join(',', allowed)}] vs mapping [{string.Join(',', mapped)}]");
                }

                compared++;
            }
        }

        Assert.Empty(problems);
        Assert.True(compared >= 14, $"only {compared} enum columns compared");
    }

    [Fact]
    public void NoPropertyIsFloatingPoint()
    {
        var floating = Model.GetEntityTypes()
            .SelectMany(e => e.GetProperties())
            .Where(p => (Nullable.GetUnderlyingType(p.ClrType) ?? p.ClrType) is var t && (t == typeof(double) || t == typeof(float)))
            .Select(p => $"{p.DeclaringType.Name}.{p.Name}")
            .ToList();

        Assert.Empty(floating);
    }

    [Fact]
    public void PricesAreNumericWithTheDocumentedPrecision()
    {
        var price = Model.FindEntityType(typeof(PriceQuote))!.FindProperty(nameof(PriceQuote.Price))!;
        var rate = Model.FindEntityType(typeof(FxRate))!.FindProperty(nameof(FxRate.Rate))!;

        Assert.Equal(typeof(decimal), price.ClrType);
        Assert.Equal(20, price.GetPrecision());
        Assert.Equal(6, price.GetScale());
        Assert.Equal(typeof(decimal), rate.ClrType);
        Assert.Equal(24, rate.GetPrecision());
        Assert.Equal(12, rate.GetScale());
    }

    [Fact]
    public void EveryObjectIsInTheZaghlolSchemaAndUuidKeysAreNotGeneratedByTheDatabase()
    {
        foreach (var entity in Model.GetEntityTypes())
        {
            Assert.Equal(ZaghlolDbContext.Schema, entity.GetSchema() ?? entity.GetViewSchema());
            foreach (var key in entity.FindPrimaryKey()?.Properties ?? Array.Empty<IProperty>())
            {
                if (key.ClrType == typeof(Guid))
                {
                    Assert.Equal(ValueGenerated.Never, key.ValueGenerated);
                }
            }
        }
    }

    [Fact]
    public void EveryModelTableAndTheViewAppearInTheGrantMatrix()
    {
        var objects = Model.GetEntityTypes().Select(e => e.GetTableName() ?? e.GetViewName()!).ToHashSet(StringComparer.Ordinal);
        var readable = GrantMatrix.Current.Where(g => g.Role == GrantMatrix.OpsRo).Select(g => g.Table).ToHashSet(StringComparer.Ordinal);

        Assert.Empty(objects.Except(readable));
        Assert.Empty(readable.Except(objects));
    }

    [Fact]
    public void AuditLogIsAppendOnlyForOperatorsAndPurgedOnlyByTheWorker()
    {
        var audit = GrantMatrix.Current.Where(g => g.Table == "audit_log").ToList();

        Assert.DoesNotContain(audit, g => g.Privileges.HasFlag(TablePrivileges.Update) || g.UpdateColumns is { Count: > 0 });
        Assert.Equal(new[] { GrantMatrix.OpsRw }, audit.Where(g => g.Privileges.HasFlag(TablePrivileges.Insert)).Select(g => g.Role));
        Assert.Equal(new[] { GrantMatrix.WorkerRw }, audit.Where(g => g.Privileges.HasFlag(TablePrivileges.Delete)).Select(g => g.Role));
    }

    [Fact]
    public void ThePublicApiRoleWritesNoCatalogFlagPriceOperatorOrAuditRows()
    {
        string[] adminOwned =
        [
            "catalog_versions", "catalog_categories", "catalog_merchants", "catalog_aliases", "catalog_keywords",
            "feature_flags", "price_quotes", "fx_rates", "operators", "audit_log", "contribution_aggregates",
        ];
        const TablePrivileges writes = TablePrivileges.Insert | TablePrivileges.Update | TablePrivileges.Delete;

        var violations = GrantMatrix.Current
            .Where(g => g.Role == GrantMatrix.AppRw && adminOwned.Contains(g.Table)
                        && ((g.Privileges & writes) != 0 || g.UpdateColumns is { Count: > 0 }))
            .ToList();

        Assert.Empty(violations);
    }

    [Fact]
    public void ReadOnlyOperatorsNeverSeeTokenHashesRefreshTokensOrStoredResponses()
    {
        var opsRo = GrantMatrix.Current.Where(g => g.Role == GrantMatrix.OpsRo).ToList();

        Assert.All(opsRo, g => Assert.Equal(TablePrivileges.None, g.Privileges & ~TablePrivileges.Select));
        Assert.All(opsRo, g => Assert.Null(g.UpdateColumns));
        foreach (var (table, column) in new[] { ("installs", "token_hash"), ("accounts", "apple_refresh_token_enc"), ("idempotency_records", "response_body_enc") })
        {
            var grant = opsRo.Single(g => g.Table == table);
            Assert.Equal(TablePrivileges.None, grant.Privileges);
            Assert.DoesNotContain(column, grant.SelectColumns!);
        }
    }

    [Fact]
    public void GrantSqlIsRenderedSchemaQualified()
    {
        var sql = GrantMatrix.ToSql([new TableGrant("ops_rw", "purchases", TablePrivileges.Select, UpdateColumns: ["account_id"])]);

        Assert.Equal("GRANT SELECT ON zaghlol.purchases TO ops_rw;\nGRANT UPDATE (account_id) ON zaghlol.purchases TO ops_rw;\n", sql);
    }

    [Theory]
    [InlineData("Id", "id")]
    [InlineData("SeatKeyTrusted", "seat_key_trusted")]
    [InlineData("RegistrationBodySha256", "registration_body_sha256")]
    [InlineData("AppleRefreshTokenEnc", "apple_refresh_token_enc")]
    [InlineData("OidcSubject", "oidc_subject")]
    [InlineData("HTTPStatus", "http_status")]
    public void SnakeCaseConversion(string name, string expected) => Assert.Equal(expected, SnakeCaseNaming.ToSnakeCase(name));

    [Fact]
    public void AnIncompleteEnumMapIsRejected() =>
        Assert.Throws<ArgumentException>(() => new EnumMap<Plan>((Plan.Monthly, "monthly"), (Plan.Yearly, "yearly")));

    [Fact]
    public void AnEnumMapWithDuplicateValuesIsRejected() =>
        Assert.Throws<ArgumentException>(() => new EnumMap<Platform>((Platform.Android, "x"), (Platform.Ios, "x")));

    private static IModel CreateModel()
    {
        using var context = new ZaghlolDbContext(ZaghlolDbContextOptions.Create("Host=localhost;Database=unused"));
        return context.GetService<IDesignTimeModel>().Model;
    }

    [GeneratedRegex("'([^']*)'")]
    private static partial Regex Quoted();
}
