using System.Text.RegularExpressions;
using Zaghlol.Ops.Cli;
using Zaghlol.Ops.Commands;
using Zaghlol.Ops.Tests.Support;

namespace Zaghlol.Ops.Tests;

/// <summary>The parser, the D-57 rule that the order ID has no option or variable, and the spec-coverage check.</summary>
public partial class CommandLineTests
{
    private static readonly string[] SupportWrites = ["support move", "support detach", "support unfreeze"];

    [Fact]
    public void TheSupportWriteCommandsHaveNoOrderIdOrOwnershipOptionAndNoPositional()
    {
        foreach (var path in SupportWrites)
        {
            var spec = Registry.All.Single(s => s.Path == path);
            var names = spec.Options.Concat(CommandLine.GlobalOptions).Select(o => o.Name).ToList();

            Assert.DoesNotContain(names, n => n.Contains("order", StringComparison.OrdinalIgnoreCase) || n.Contains("owner", StringComparison.OrdinalIgnoreCase)
                || n.Contains("receipt", StringComparison.OrdinalIgnoreCase) || n.Contains("secret", StringComparison.OrdinalIgnoreCase));
            Assert.Equal(0, spec.MaxPositionals);
        }
    }

    [Theory]
    [InlineData("support", "move", "--order-id", "SENTINEL-ORDER-1", "--purchase", "x")]
    [InlineData("support", "move", "--order-id=SENTINEL-ORDER-1")]
    [InlineData("support", "detach", "--ownership-check", "SENTINEL-ORDER-1")]
    [InlineData("support", "unfreeze", "--order=SENTINEL-ORDER-1")]
    [InlineData("support", "unfreeze", "--SENTINEL-ORDER-1")]
    [InlineData("support", "unfreeze", "SENTINEL-ORDER-1")]
    [InlineData("support", "unfreeze", "-o", "SENTINEL-ORDER-1")]
    public void AnyWayOfPassingTheOrderIdOnTheCommandLineIsRefusedWithoutEchoingIt(params string[] args)
    {
        var outcome = CommandLine.Parse(args, Registry.All);

        Assert.Null(outcome.Args);
        Assert.NotNull(outcome.Error);
        Assert.DoesNotContain("SENTINEL", outcome.Error, StringComparison.Ordinal);
    }

    [Fact]
    public void TheCliReadsNoEnvironmentVariableBeyondItsSettingsAndNeverAnOrderId()
    {
        Assert.All(OpsConfig.EnvironmentVariables, name =>
        {
            Assert.StartsWith("ZAGHLOL_OPS_", name, StringComparison.Ordinal);
            Assert.DoesNotContain("ORDER", name, StringComparison.Ordinal);
            Assert.DoesNotContain("OWNER", name, StringComparison.Ordinal);
        });

        var allowed = new HashSet<string>(OpsConfig.EnvironmentVariables.Append("XDG_CONFIG_HOME"), StringComparer.Ordinal);
        var reads = 0;
        foreach (var file in SourceFiles())
        {
            foreach (Match call in EnvironmentRead().Matches(File.ReadAllText(file)))
            {
                reads++;
                var argument = call.Groups["arg"].Value.Trim();
                Assert.True(
                    Path.GetFileName(file) == "OpsEnvironment.cs" && (argument == "name" || (argument.StartsWith('"') && allowed.Contains(argument.Trim('"')))),
                    $"{Path.GetFileName(file)} reads an environment variable that is not on the list: {argument}");
            }
        }

        Assert.True(reads >= 2, "the scan found no environment reads at all (is the source path right?)");
    }

    [Fact]
    public void TheCliWritesNoFiles()
    {
        // Tokens live in memory or the OS credential store, never in a file (R3-9, design note section 2).
        var files = SourceFiles().ToList();
        Assert.True(files.Count >= 15);
        foreach (var file in files)
        {
            Assert.DoesNotMatch(@"File\.(Write|Create|Append|Open|Copy|Move|Replace)|FileStream|StreamWriter|FileMode\.", File.ReadAllText(file));
        }
    }

    [Fact]
    public void EveryAdminOperationOfTheSpecHasACommandAndNoCommandNamesAMissingOperation()
    {
        var spec = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "openapi", "zaghlol-v1.yaml"));
        var operations = SpecOperation().Matches(spec).Select(m => m.Groups["id"].Value).ToHashSet(StringComparer.Ordinal);
        var commands = Registry.All.Where(c => c.OperationId is not null && c.OperationId.StartsWith("admin", StringComparison.Ordinal))
            .Select(c => c.OperationId!).ToList();

        Assert.True(operations.Count >= 17, $"only {operations.Count} admin operations found in the spec");
        Assert.Empty(operations.Except(commands, StringComparer.Ordinal));
        Assert.Empty(commands.Except(operations, StringComparer.Ordinal));
        Assert.Equal(commands.Count, commands.Distinct(StringComparer.Ordinal).Count());
    }

    [Fact]
    public void CommandPathsAreUniqueAndEveryCommandHasUsageAndSummary()
    {
        Assert.Equal(Registry.All.Count, Registry.All.Select(c => c.Path).Distinct(StringComparer.Ordinal).Count());
        Assert.All(Registry.All, c =>
        {
            Assert.StartsWith(c.Path, c.Usage, StringComparison.Ordinal);
            Assert.NotEmpty(c.Summary);
            Assert.Equal(c.Options.Count, c.Options.Select(o => o.Name).Distinct(StringComparer.Ordinal).Count());
        });
    }

    [Fact]
    public void ParsesOptionsWithSpaceOrEqualsFlagsAndPositionals()
    {
        var outcome = CommandLine.Parse(["catalog", "draft", "list", "merchants", "--limit=50", "--all", "--cursor", "-abc"], Registry.All);

        Assert.Null(outcome.Error);
        Assert.Equal("catalog draft list", outcome.Spec!.Path);
        Assert.Equal(["merchants"], outcome.Args!.Positionals);
        Assert.Equal("50", outcome.Args.Get("limit"));
        Assert.True(outcome.Args.Has("all"));
        Assert.Equal("-abc", outcome.Args.Get("cursor"));
    }

    [Theory]
    [InlineData("flags", "get")]
    [InlineData("flags", "get", "a", "b")]
    [InlineData("flags", "set", "x", "--value")]
    [InlineData("flags", "set", "x", "--value", "true", "--value", "false")]
    [InlineData("flags", "set", "x", "--all")]
    [InlineData("metrics", "daily-active", "--days=3", "--days=4")]
    [InlineData("metrics", "daily-active", "--help=1")]
    public void BadShapesAreUsageErrors(params string[] args)
    {
        var outcome = CommandLine.Parse(args, Registry.All);

        Assert.Null(outcome.Args);
        Assert.NotNull(outcome.Error);
        Assert.False(outcome.Help);
    }

    [Fact]
    public void ADashedNumberIsAPositionalAndNotAnUnknownOption()
    {
        var outcome = CommandLine.Parse(["flags", "get", "-5"], Registry.All);

        Assert.Null(outcome.Error);
        Assert.Equal(["-5"], outcome.Args!.Positionals);
    }

    [Fact]
    public async Task APositionalOrderIdOnTheRealCommandLineSendsNothingAndPrintsNothing()
    {
        var called = false;
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(new StubHandler((_, _) => { called = true; return StubHandler.Json(200, "{}"); }), idp, "GPA.UNUSED-0001");

        var code = await env.RunAsync("support", "unfreeze", "--purchase", Guid.NewGuid().ToString(), "--ticket", "ZG-1", "--order-id", "GPA.SENTINEL-4242");

        Assert.Equal(OpsCli.UsageError, code);
        Assert.False(called);
        Assert.Empty(idp.Requests);
        Assert.DoesNotContain("SENTINEL", env.AllOutput, StringComparison.Ordinal);
    }

    private static IEnumerable<string> SourceFiles()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "src", "Zaghlol.Ops", "Zaghlol.Ops.csproj")))
        {
            directory = directory.Parent;
        }

        Assert.NotNull(directory);
        return Directory.EnumerateFiles(Path.Combine(directory.FullName, "src", "Zaghlol.Ops"), "*.cs", SearchOption.AllDirectories)
            .Where(f => !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.Ordinal)
                && !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}", StringComparison.Ordinal));
    }

    [GeneratedRegex(@"Environment\.GetEnvironmentVariable\((?<arg>[^)]*)\)", RegexOptions.CultureInvariant)]
    private static partial Regex EnvironmentRead();

    [GeneratedRegex(@"operationId:\s*(?<id>admin\w+)", RegexOptions.CultureInvariant)]
    private static partial Regex SpecOperation();
}
