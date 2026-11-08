using System.Text;
using System.Text.RegularExpressions;

namespace Zaghlol.Infrastructure.Tests;

public sealed record DocColumn(string Name, string Type, bool NotNull, bool HasDefault, bool Identity);

public sealed record DocTable(string Name, IReadOnlyList<DocColumn> Columns);

/// <summary>
/// Reads the SQL fence of <c>docs/03-technical/backend-schema.md</c> section 2: every <c>CREATE TABLE</c>, its columns
/// (name, type, NOT NULL, DEFAULT, identity). Table-level CHECK / UNIQUE / PRIMARY KEY items and comments are skipped.
/// </summary>
public static partial class SchemaDocument
{
    private static readonly Lazy<string> Text = new(() =>
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "docs", "backend-schema.md")));

    public static string TablesSql
    {
        get
        {
            var text = Text.Value;
            var section = text.IndexOf("## 2. Tables", StringComparison.Ordinal);
            var fence = text.IndexOf("```sql", section, StringComparison.Ordinal) + "```sql".Length;
            var end = text.IndexOf("```", fence, StringComparison.Ordinal);
            Assert.True(section >= 0 && fence > section && end > fence, "backend-schema.md section 2 SQL fence not found");
            return text[fence..end];
        }
    }

    public static IReadOnlyDictionary<string, DocTable> Tables()
    {
        var code = StripComments(TablesSql);
        var tables = new Dictionary<string, DocTable>(StringComparer.Ordinal);
        foreach (Match match in CreateTable().Matches(code))
        {
            var items = SplitTopLevel(code, match.Index + match.Length);
            var compositeKey = items
                .Select(i => CompositePrimaryKey().Match(i))
                .Where(m => m.Success)
                .SelectMany(m => m.Groups[1].Value.Split(',', StringSplitOptions.TrimEntries))
                .ToHashSet(StringComparer.Ordinal);
            var columns = items
                .Where(i => !TableConstraint().IsMatch(i))
                .Select(i => ParseColumn(i, compositeKey))
                .ToList();
            tables.Add(match.Groups[1].Value, new DocTable(match.Groups[1].Value, columns));
        }

        return tables;
    }

    /// <summary>The comment on a column's line plus the comment-only lines right after it, joined with single spaces.</summary>
    public static string ColumnComment(string table, string column)
    {
        var lines = TablesSql.Split('\n');
        var start = Array.FindIndex(lines, l => l.Contains($"CREATE TABLE {table} (", StringComparison.Ordinal));
        Assert.True(start >= 0, $"table {table} not in backend-schema.md");
        var at = Array.FindIndex(lines, start, l => l.TrimStart().StartsWith(column + " ", StringComparison.Ordinal));
        Assert.True(at >= 0, $"column {table}.{column} not in backend-schema.md");

        var parts = new List<string> { lines[at][(lines[at].IndexOf("--", StringComparison.Ordinal) + 2)..] };
        for (var i = at + 1; i < lines.Length && lines[i].TrimStart().StartsWith("--", StringComparison.Ordinal); i++)
        {
            parts.Add(lines[i].TrimStart()[2..]);
        }

        return Whitespace().Replace(string.Join(' ', parts), " ").Trim();
    }

    /// <summary>Doc type spelling to <c>format_type()</c> spelling.</summary>
    public static string NormalizeType(string type) => type switch
    {
        "timestamptz" => "timestamp with time zone",
        "timestamptz[]" => "timestamp with time zone[]",
        "int" => "integer",
        "bool" => "boolean",
        _ => type,
    };

    private static DocColumn ParseColumn(string item, HashSet<string> compositeKey)
    {
        var tokens = item.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        Assert.True(tokens.Length >= 2, $"unparseable column definition: {item}");
        var name = tokens[0];

        // Keywords are looked for outside parentheses only, so CHECK bodies can't fake them.
        var outer = Parenthesized().Replace(item, string.Empty);
        var notNull = outer.Contains("NOT NULL", StringComparison.Ordinal)
                      || outer.Contains("PRIMARY KEY", StringComparison.Ordinal)
                      || compositeKey.Contains(name);
        var identity = outer.Contains("GENERATED ALWAYS AS IDENTITY", StringComparison.Ordinal);
        var hasDefault = outer.Contains(" DEFAULT ", StringComparison.Ordinal);
        return new DocColumn(name, NormalizeType(tokens[1]), notNull, hasDefault, identity);
    }

    private static List<string> SplitTopLevel(string code, int start)
    {
        var items = new List<string>();
        var current = new StringBuilder();
        var depth = 1;
        var inQuote = false;
        for (var i = start; i < code.Length; i++)
        {
            var c = code[i];
            if (inQuote)
            {
                current.Append(c);
                inQuote = c != '\'';
                continue;
            }

            switch (c)
            {
                case '\'':
                    inQuote = true;
                    break;
                case '(':
                    depth++;
                    break;
                case ')':
                    depth--;
                    if (depth == 0)
                    {
                        items.Add(current.ToString());
                        return [.. items.Select(s => Whitespace().Replace(s, " ").Trim()).Where(s => s.Length > 0)];
                    }

                    break;
                case ',' when depth == 1:
                    items.Add(current.ToString());
                    current.Clear();
                    continue;
            }

            current.Append(c);
        }

        throw new InvalidOperationException("unterminated CREATE TABLE in backend-schema.md");
    }

    private static string StripComments(string sql)
    {
        var result = new StringBuilder(sql.Length);
        foreach (var line in sql.Split('\n'))
        {
            var inQuote = false;
            var cut = line.Length;
            for (var i = 0; i < line.Length; i++)
            {
                if (line[i] == '\'')
                {
                    inQuote = !inQuote;
                }
                else if (!inQuote && line[i] == '-' && i + 1 < line.Length && line[i + 1] == '-')
                {
                    cut = i;
                    break;
                }
            }

            result.Append(line.AsSpan(0, cut)).Append('\n');
        }

        return result.ToString();
    }

    [GeneratedRegex(@"CREATE TABLE (\w+)\s*\(")]
    private static partial Regex CreateTable();

    [GeneratedRegex(@"^(CHECK|UNIQUE|PRIMARY KEY|CONSTRAINT|FOREIGN KEY)\b")]
    private static partial Regex TableConstraint();

    [GeneratedRegex(@"^PRIMARY KEY \(([^)]*)\)")]
    private static partial Regex CompositePrimaryKey();

    [GeneratedRegex(@"\([^()]*(\([^()]*\)[^()]*)*\)")]
    private static partial Regex Parenthesized();

    [GeneratedRegex(@"\s+")]
    private static partial Regex Whitespace();
}
