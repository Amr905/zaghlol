using System.Globalization;
using System.Text;
using Zaghlol.Domain;

namespace Zaghlol.Application.Catalog;

/// <summary>A category row of the seed.</summary>
public sealed record SeedCategory(string Code, CatalogFields Fields);

/// <summary>A merchant row of the seed with its aliases (<c>alias</c>, <c>match</c>).</summary>
public sealed record SeedMerchant(string Canonical, CatalogFields Fields, IReadOnlyList<SeedAlias> Aliases);

/// <summary>An alias of a seed merchant; <paramref name="Alias"/> must already be in normalized form.</summary>
public sealed record SeedAlias(string Alias, string Match);

/// <summary>A keyword row of the seed.</summary>
public sealed record SeedKeyword(string Lang, string Keyword, CatalogFields Fields);

/// <summary>The parsed seed: parents before children.</summary>
public sealed record CatalogSeed(IReadOnlyList<SeedCategory> Categories, IReadOnlyList<SeedMerchant> Merchants, IReadOnlyList<SeedKeyword> Keywords);

/// <summary>The seed file is malformed. The message is constant; <see cref="Line"/> says where.</summary>
public sealed class CatalogSeedFormatException : SafeException
{
    public const string DefaultMessage = "The catalog seed file is malformed.";

    public CatalogSeedFormatException()
        : base(DefaultMessage)
    {
    }

    public CatalogSeedFormatException(int line)
        : base(DefaultMessage) => Line = line;

    public CatalogSeedFormatException(string message)
        : base(message)
    {
    }

    public CatalogSeedFormatException(string message, Exception innerException)
        : base(message, innerException)
    {
    }

    /// <summary>The 1-based line of the offending row, or 0.</summary>
    public int Line { get; }
}

/// <summary>
/// Reads the catalog seed CSV of <c>tools/catalog_build</c> (RFC 4180: comma separated, <c>"</c> quoting with <c>""</c>, UTF-8).
/// The first row is the header and must contain these columns in any order:
/// <c>entity,code,nameAr,nameEn,icon,color,bucket,sort,canonical,category,alias,match,keyword,lang,weight</c>.
/// <list type="bullet">
/// <item><c>entity=category</c>: <c>code,nameAr,nameEn,icon,color,bucket,sort</c></item>
/// <item><c>entity=merchant</c>: <c>canonical,nameAr,category</c></item>
/// <item><c>entity=alias</c>: <c>canonical</c> (the owning merchant), <c>alias</c> (normalized), <c>match</c></item>
/// <item><c>entity=keyword</c>: <c>keyword,lang,category,weight</c></item>
/// </list>
/// Unused columns stay empty. Blank lines are skipped.
/// </summary>
public static class CatalogSeedCsv
{
    private static readonly string[] Columns =
    [
        "entity", "code", "nameAr", "nameEn", "icon", "color", "bucket", "sort", "canonical", "category", "alias", "match",
        "keyword", "lang", "weight",
    ];

    public static CatalogSeed Parse(string csv)
    {
        ArgumentNullException.ThrowIfNull(csv);

        var rows = ReadRows(csv.TrimStart('\uFEFF'));
        if (rows.Count == 0)
        {
            throw new CatalogSeedFormatException(1);
        }

        var header = rows[0].Cells;
        var index = new Dictionary<string, int>(StringComparer.Ordinal);
        for (var i = 0; i < header.Count; i++)
        {
            index[header[i]] = i;
        }

        if (Columns.Any(c => !index.ContainsKey(c)))
        {
            throw new CatalogSeedFormatException(rows[0].Line);
        }

        var categories = new List<SeedCategory>();
        var merchants = new List<SeedMerchant>();
        var aliases = new Dictionary<string, List<SeedAlias>>(StringComparer.Ordinal);
        var keywords = new List<SeedKeyword>();
        foreach (var row in rows.Skip(1))
        {
            string Get(string column) => index[column] < row.Cells.Count ? row.Cells[index[column]] : string.Empty;

            switch (Get("entity"))
            {
                case "category":
                    categories.Add(new SeedCategory(
                        Get("code"),
                        new CatalogFields
                        {
                            NameAr = Get("nameAr"),
                            NameEn = Get("nameEn"),
                            Icon = Get("icon"),
                            Color = Get("color"),
                            Bucket = Get("bucket"),
                            Sort = ParseInt(Get("sort"), row.Line),
                        }));
                    break;
                case "merchant":
                    merchants.Add(new SeedMerchant(
                        Get("canonical"),
                        new CatalogFields { Canonical = Get("canonical"), NameAr = Get("nameAr"), Category = Get("category") },
                        []));
                    break;
                case "alias":
                    if (!aliases.TryGetValue(Get("canonical"), out var list))
                    {
                        list = [];
                        aliases[Get("canonical")] = list;
                    }

                    list.Add(new SeedAlias(Get("alias"), Get("match")));
                    break;
                case "keyword":
                    keywords.Add(new SeedKeyword(
                        Get("lang"),
                        Get("keyword"),
                        new CatalogFields { Category = Get("category"), Weight = ParseInt(Get("weight"), row.Line) }));
                    break;
                default:
                    throw new CatalogSeedFormatException(row.Line);
            }
        }

        var withAliases = merchants
            .Select(m => m with { Aliases = aliases.GetValueOrDefault(m.Canonical) ?? [] })
            .ToList();
        if (aliases.Keys.Any(k => merchants.All(m => !string.Equals(m.Canonical, k, StringComparison.Ordinal))))
        {
            throw new CatalogSeedFormatException(0);
        }

        return new CatalogSeed(categories, withAliases, keywords);
    }

    private static int ParseInt(string text, int line) =>
        int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out var value) ? value : throw new CatalogSeedFormatException(line);

    private sealed record Row(int Line, List<string> Cells);

    private static List<Row> ReadRows(string csv)
    {
        var rows = new List<Row>();
        var cells = new List<string>();
        var cell = new StringBuilder();
        var quoted = false;
        var line = 1;
        var rowLine = 1;
        var hasContent = false;

        void EndCell()
        {
            cells.Add(cell.ToString());
            cell.Clear();
        }

        void EndRow()
        {
            if (hasContent)
            {
                EndCell();
                rows.Add(new Row(rowLine, cells));
                cells = [];
            }

            cell.Clear();
            hasContent = false;
        }

        for (var i = 0; i < csv.Length; i++)
        {
            var c = csv[i];
            if (quoted)
            {
                if (c == '"' && i + 1 < csv.Length && csv[i + 1] == '"')
                {
                    cell.Append('"');
                    i++;
                }
                else if (c == '"')
                {
                    quoted = false;
                }
                else
                {
                    if (c == '\n')
                    {
                        line++;
                    }

                    cell.Append(c);
                }

                continue;
            }

            switch (c)
            {
                case '"':
                    quoted = true;
                    hasContent = true;
                    break;
                case ',':
                    hasContent = true;
                    EndCell();
                    break;
                case '\r':
                    break;
                case '\n':
                    EndRow();
                    line++;
                    rowLine = line;
                    break;
                default:
                    hasContent = true;
                    cell.Append(c);
                    break;
            }
        }

        if (quoted)
        {
            throw new CatalogSeedFormatException(rowLine);
        }

        EndRow();
        return rows;
    }
}
