using System.Reflection;
using System.Runtime.CompilerServices;

namespace Zaghlol.Testing;

/// <summary>
/// T-182 design note §8: test support (fake KMS, test signers, other fakes) never ships in a production assembly. Each test
/// project that references production assemblies checks them with <see cref="Offenders"/>.
/// </summary>
public static class TestSupportExclusion
{
    /// <summary>
    /// Production types whose name matches the rule on purpose. <c>FakePriceProvider</c> (T-127) is the deterministic price
    /// stand-in while D-41 is open: selected only by <c>Prices:Providers = fake</c> and refused in Production.
    /// </summary>
    public static IReadOnlySet<string> Allowed { get; } = new HashSet<string>(StringComparer.Ordinal)
    {
        "Zaghlol.Infrastructure.Prices.FakePriceProvider",
    };

    /// <summary>
    /// Types of <paramref name="assembly"/> in namespace <c>Zaghlol.Testing</c> or named <c>Fake*</c> / <c>*TestSigner</c>,
    /// and references to a test assembly. Empty for a clean production assembly.
    /// </summary>
    public static IReadOnlyList<string> Offenders(Assembly assembly)
    {
        ArgumentNullException.ThrowIfNull(assembly);

        var types = assembly.GetTypes()
            .Where(t => !t.IsDefined(typeof(CompilerGeneratedAttribute), inherit: false))
            .Where(t => IsTestNamespace(t.Namespace) || IsTestName(t.Name))
            .Select(t => t.FullName ?? t.Name)
            .Where(name => !Allowed.Contains(name));
        var references = assembly.GetReferencedAssemblies()
            .Where(a => a.Name is { } name && (name.EndsWith(".Tests", StringComparison.Ordinal) || name.Contains("Testing", StringComparison.Ordinal)))
            .Select(a => "reference " + a.Name);
        return [.. types, .. references];
    }

    private static bool IsTestNamespace(string? ns) =>
        ns is not null && (ns == "Zaghlol.Testing" || ns.StartsWith("Zaghlol.Testing.", StringComparison.Ordinal));

    private static bool IsTestName(string name)
    {
        var bare = name.Split('`')[0];
        return bare.StartsWith("Fake", StringComparison.Ordinal) || bare.EndsWith("TestSigner", StringComparison.Ordinal);
    }
}
