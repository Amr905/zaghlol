using System.Reflection;
using System.Xml.Linq;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Installs;

/// <summary>
/// T-182 design note §8: test support (<c>FakeKms</c>, <c>SeatKeyTestSigner</c>, other fakes) never ships. No type of the
/// Domain, Application, Infrastructure or Api assembly is in namespace <c>Zaghlol.Testing</c> or named <c>Fake*</c> /
/// <c>*TestSigner</c> (Workers and Ops are checked in their own test projects), and no project under <c>src/</c> compiles or
/// references anything under <c>tests/</c>.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class TestSupportExclusionTests
{
    public static TheoryData<string> ProductionAssemblies() =>
    [
        typeof(InstallId).Assembly.GetName().Name!,
        typeof(SeatKeyProofVerifier).Assembly.GetName().Name!,
        typeof(IKeyedHasher).Assembly.GetName().Name!,
        typeof(ApiPipeline).Assembly.GetName().Name!,
    ];

    [Theory]
    [MemberData(nameof(ProductionAssemblies))]
    public void NoProductionAssemblyContainsTestSupport(string name)
    {
        Assert.Empty(TestSupportExclusion.Offenders(Assembly.Load(name)));
    }

    [Fact]
    public void TheRuleRecognisesTestSupport()
    {
        // The rule itself must catch the shared test types (a rule that matches nothing proves nothing).
        var offenders = TestSupportExclusion.Offenders(typeof(TestSupportExclusionTests).Assembly);

        Assert.Contains("Zaghlol.Testing.FakeKms", offenders);
        Assert.Contains("Zaghlol.Testing.SeatKeyTestSigner", offenders);
    }

    [Fact]
    public void NoSourceProjectReachesIntoTests()
    {
        var src = Path.Combine(FindBackend(), "src");
        var projects = Directory.GetFiles(src, "*.csproj", SearchOption.AllDirectories);
        Assert.True(projects.Length >= 6, $"found {projects.Length} projects");

        foreach (var project in projects)
        {
            var paths = XDocument.Load(project).Descendants()
                .SelectMany(e => e.Attributes().Where(a => a.Name.LocalName is "Include" or "Update" or "Link"))
                .Select(a => a.Value.Replace('\\', '/'));
            Assert.DoesNotContain(paths, p => p.Contains("/tests/", StringComparison.OrdinalIgnoreCase) || p.StartsWith("tests/", StringComparison.OrdinalIgnoreCase) || p.Contains("Shared/", StringComparison.Ordinal));
        }
    }

    private static string FindBackend()
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        {
            if (File.Exists(Path.Combine(dir.FullName, "Zaghlol.sln")))
            {
                return dir.FullName;
            }
        }

        throw new InvalidOperationException("backend/Zaghlol.sln not found above the test output directory.");
    }
}
