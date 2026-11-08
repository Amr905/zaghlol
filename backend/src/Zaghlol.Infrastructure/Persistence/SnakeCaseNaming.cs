using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata;

namespace Zaghlol.Infrastructure.Persistence;

/// <summary>
/// snake_case names for columns, keys, foreign keys and indexes (backend-schema.md conventions), without the
/// EFCore.NamingConventions dependency. Names set explicitly in a configuration are kept.
/// Keys: <c>pk_&lt;table&gt;</c>; FKs: <c>fk_&lt;table&gt;_&lt;principal&gt;_&lt;columns&gt;</c>;
/// indexes: <c>ix_</c> or, when unique, <c>ux_&lt;table&gt;_&lt;columns&gt;</c>.
/// </summary>
internal static class SnakeCaseNaming
{
    public static void Apply(IMutableModel model)
    {
        foreach (var entity in model.GetEntityTypes())
        {
            foreach (var property in entity.GetProperties())
            {
                if (property.FindAnnotation(RelationalAnnotationNames.ColumnName) is null)
                {
                    property.SetColumnName(ToSnakeCase(property.Name));
                }
            }
        }

        foreach (var entity in model.GetEntityTypes())
        {
            var table = entity.GetTableName();
            if (table is null)
            {
                continue; // the keyless view mapping has no keys or indexes
            }

            foreach (var key in entity.GetKeys())
            {
                key.SetName(key.IsPrimaryKey() ? $"pk_{table}" : $"ak_{table}_{Columns(key.Properties)}");
            }

            foreach (var foreignKey in entity.GetForeignKeys())
            {
                var principal = foreignKey.PrincipalEntityType.GetTableName();
                foreignKey.SetConstraintName($"fk_{table}_{principal}_{Columns(foreignKey.Properties)}");
            }

            foreach (var index in entity.GetIndexes())
            {
                if (index.FindAnnotation(RelationalAnnotationNames.Name) is null)
                {
                    index.SetDatabaseName($"{(index.IsUnique ? "ux" : "ix")}_{table}_{Columns(index.Properties)}");
                }
            }
        }
    }

    public static string ToSnakeCase(string name)
    {
        ArgumentException.ThrowIfNullOrEmpty(name);

        var builder = new StringBuilder(name.Length + 8);
        for (var i = 0; i < name.Length; i++)
        {
            var c = name[i];
            if (char.IsUpper(c))
            {
                var previousIsLowerOrDigit = i > 0 && (char.IsLower(name[i - 1]) || char.IsDigit(name[i - 1]));
                var acronymEnds = i > 0 && char.IsUpper(name[i - 1]) && i + 1 < name.Length && char.IsLower(name[i + 1]);
                if (previousIsLowerOrDigit || acronymEnds)
                {
                    builder.Append('_');
                }

                builder.Append(char.ToLowerInvariant(c));
            }
            else
            {
                builder.Append(c);
            }
        }

        return builder.ToString();
    }

    private static string Columns(IEnumerable<IReadOnlyProperty> properties) =>
        string.Join('_', properties.Select(p => p.GetColumnName()));
}
