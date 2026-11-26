using System.Text.Json.Nodes;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// T-349: <c>backend/contracts/institution-aliases-v1.json</c> (embedded in the plan validator, ask-llm §2.4 step 2) is generated from the app's
/// institution registry: every <c>names</c> value and <c>walletCardNames</c> entry of <c>app/assets/registry/institutions/*.json</c> of at least three
/// characters, sorted ordinally. The test fails when the two drift apart, so a new bank in the app is also refused inside a plan.
/// </summary>
public class InstitutionAliasesTests
{
    [Fact]
    public void TheBundledAliasListMatchesTheAppRegistry()
    {
        var registry = FindRegistry();
        var expected = new SortedSet<string>(StringComparer.Ordinal);
        foreach (var file in Directory.EnumerateFiles(registry, "*.json"))
        {
            var institution = JsonNode.Parse(File.ReadAllText(file))!.AsObject();
            foreach (var name in institution["names"]!.AsObject().Select(n => n.Value!.GetValue<string>())
                         .Concat(institution["walletCardNames"]?.AsArray().Select(n => n!.GetValue<string>()) ?? []))
            {
                if (name.Trim().Length >= 3)
                {
                    expected.Add(name.Trim());
                }
            }
        }

        var bundled = LlmContractFiles.Contract("institution-aliases-v1.json")["aliases"]!.AsArray().Select(a => a!.GetValue<string>()).ToList();

        Assert.True(expected.Count > 100, "the registry was not found or is empty");
        Assert.Equal([.. expected], bundled);
    }

    private static string FindRegistry()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var candidate = Path.Combine(directory.FullName, "app", "assets", "registry", "institutions");
            if (Directory.Exists(candidate))
            {
                return candidate;
            }

            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException("app/assets/registry/institutions was not found above the test output.");
    }
}
