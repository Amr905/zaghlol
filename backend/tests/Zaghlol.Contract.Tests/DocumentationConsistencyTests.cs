using System.Reflection;
using System.Text.RegularExpressions;
using Zaghlol.Domain;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// Keeps <c>zaghlol-v1.yaml</c> and <c>docs/03-technical/backend-api.md</c> (sections 2, 5 and 6) saying the
/// same thing about endpoints and problem codes.
/// </summary>
public partial class DocumentationConsistencyTests
{
    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private static readonly string Document = File.ReadAllText(FindDocument());

    [GeneratedRegex("`((?:GET|POST|PUT|DELETE)(?:/(?:GET|POST|PUT|DELETE))*) (/v1/[^`\\s]+)`")]
    private static partial Regex PublicEndpointCell();

    [GeneratedRegex("`((?:GET|POST|PUT|DELETE)(?:/(?:GET|POST|PUT|DELETE))*) (/admin/v1/[A-Za-z0-9/_-]*)")]
    private static partial Regex AdminEndpointCell();

    [GeneratedRegex("`([A-Z][A-Z0-9_]*)`")]
    private static partial Regex CodeToken();

    [Fact]
    public void ErrorCodeTableMatchesTheSpecProblemCodeEnum()
    {
        var documented = DocumentedCodes();
        var inSpec = Spec.Schemas["ProblemCode"]!["enum"]!.AsArray().Select(n => n!.GetValue<string>()).ToHashSet(StringComparer.Ordinal);

        Assert.Empty(documented.Except(inSpec, StringComparer.Ordinal));
        Assert.Empty(inSpec.Except(documented, StringComparer.Ordinal));
    }

    [Fact]
    public void EveryCodeDefinedInSourceIsDocumentedAndInTheSpec()
    {
        var inSource = typeof(ErrorCodes)
            .GetFields(BindingFlags.Public | BindingFlags.Static)
            .Select(f => (string)f.GetRawConstantValue()!)
            .ToList();
        var documented = DocumentedCodes();

        Assert.NotEmpty(inSource);
        Assert.Empty(inSource.Except(documented, StringComparer.Ordinal));
    }

    [Fact]
    public void PublicEndpointTableMatchesTheSpecOperationForOperation()
    {
        var documented = new HashSet<string>(StringComparer.Ordinal);
        foreach (var line in Section("## 2.", "## 3.").Split('\n'))
        {
            var match = PublicEndpointCell().Match(FirstCell(line));
            if (!match.Success)
            {
                continue;
            }

            foreach (var method in match.Groups[1].Value.Split('/'))
            {
                documented.Add($"{method.ToLowerInvariant()} {match.Groups[2].Value}");
            }
        }

        var inSpec = Spec.Operations()
            .Where(o => o.Path.StartsWith("/v1/", StringComparison.Ordinal))
            .Select(o => $"{o.Method} {o.Path}")
            .ToHashSet(StringComparer.Ordinal);

        Assert.NotEmpty(documented);
        Assert.Empty(documented.Except(inSpec, StringComparer.Ordinal));
        Assert.Empty(inSpec.Except(documented, StringComparer.Ordinal));
    }

    [Fact]
    public void AdminEndpointTableMatchesTheSpecOperations()
    {
        var rows = new List<(string[] Methods, string Prefix)>();
        foreach (var line in Section("## 5.", "## 6.").Split('\n'))
        {
            var match = AdminEndpointCell().Match(FirstCell(line));
            if (match.Success)
            {
                rows.Add((match.Groups[1].Value.Split('/').Select(m => m.ToLowerInvariant()).ToArray(), match.Groups[2].Value));
            }
        }

        Assert.NotEmpty(rows);
        var adminOperations = Spec.Operations().Where(o => o.Path.StartsWith("/admin/v1/", StringComparison.Ordinal)).ToList();

        var missingInSpec = rows
            .SelectMany(r => r.Methods.Select(m => (Method: m, r.Prefix)))
            .Where(r => !adminOperations.Any(o => o.Method == r.Method && o.Path.StartsWith(r.Prefix, StringComparison.Ordinal)))
            .Select(r => $"{r.Method} {r.Prefix}*")
            .ToList();
        var missingInDocument = adminOperations
            .Where(o => !rows.Any(r => r.Methods.Contains(o.Method) && o.Path.StartsWith(r.Prefix, StringComparison.Ordinal)))
            .Select(o => o.Label)
            .ToList();

        Assert.Empty(missingInSpec);
        Assert.Empty(missingInDocument);
    }

    private static HashSet<string> DocumentedCodes()
    {
        var codes = new HashSet<string>(StringComparer.Ordinal);
        foreach (var line in Section("## 6.", null).Split('\n'))
        {
            var cells = line.Split('|');
            var statusCell = cells.Length > 1 ? cells[1].Trim() : string.Empty;
            if (cells.Length < 4 || statusCell.Length == 0 || !statusCell.All(c => char.IsAsciiDigit(c) || c == '/'))
            {
                continue;
            }

            foreach (Match code in CodeToken().Matches(cells[2]))
            {
                codes.Add(code.Groups[1].Value);
            }
        }

        Assert.NotEmpty(codes);
        return codes;
    }

    /// <summary>The first table cell of a markdown row, with escaped pipes kept inside the cell.</summary>
    private static string FirstCell(string line)
    {
        if (!line.StartsWith('|'))
        {
            return string.Empty;
        }

        var protectedLine = line.Replace("\\|", "\u0001", StringComparison.Ordinal);
        var cells = protectedLine.Split('|');
        return cells.Length > 1 ? cells[1].Replace('\u0001', '|') : string.Empty;
    }

    private static string Section(string start, string? end)
    {
        var begin = Document.IndexOf("\n" + start, StringComparison.Ordinal);
        Assert.True(begin >= 0, $"section '{start}' not found in backend-api.md");
        var finish = end is null ? Document.Length : Document.IndexOf("\n" + end, begin + 1, StringComparison.Ordinal);
        Assert.True(finish > begin, $"section end '{end}' not found in backend-api.md");
        return Document[begin..finish];
    }

    private static string FindDocument()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var candidate = Path.Combine(directory.FullName, "docs", "03-technical", "backend-api.md");
            if (File.Exists(candidate))
            {
                return candidate;
            }

            directory = directory.Parent;
        }

        throw new FileNotFoundException("docs/03-technical/backend-api.md not found above " + AppContext.BaseDirectory);
    }
}
