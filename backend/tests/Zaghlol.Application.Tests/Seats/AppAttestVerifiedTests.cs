using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.CompilerServices;
using Zaghlol.Application.Seats;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Seats;

/// <summary>
/// R5-2: <c>seat_key_trusted</c> is set only through <see cref="AppAttestVerified"/>, and only the restore flow (namespace
/// <see cref="AppAttestVerified.IssuerNamespace"/>, T-185) may construct one. Other assemblies can't reach the internal
/// constructor at all (only test assemblies see Application internals); inside Application every method body is scanned.
/// </summary>
public sealed class AppAttestVerifiedTests
{
    private static readonly ConstructorInfo Constructor =
        typeof(AppAttestVerified).GetConstructors(BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public).Single();

    [Fact]
    public void TheCapabilityHasNoPublicWayIn()
    {
        var type = typeof(AppAttestVerified);

        Assert.True(type.IsSealed);
        Assert.False(type.IsValueType); // default(T) of a struct would forge it
        Assert.True(Constructor.IsAssembly);
        Assert.NotEmpty(Constructor.GetParameters());
        Assert.Empty(type.GetConstructors());
        Assert.DoesNotContain(
            AllProductionTypes().SelectMany(t => t.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance | BindingFlags.DeclaredOnly)),
            m => m.ReturnType == type);
    }

    [Fact]
    public void OnlyTestAssembliesSeeApplicationInternals()
    {
        var friends = typeof(AppAttestVerified).Assembly.GetCustomAttributes<InternalsVisibleToAttribute>().Select(a => a.AssemblyName).ToArray();

        Assert.NotEmpty(friends);
        Assert.All(friends, name => Assert.EndsWith(".Tests", name, StringComparison.Ordinal));
    }

    [Fact]
    public void NoProductionCodeOutsideTheRestoreNamespaceConstructsTheCapability()
    {
        var sites = ConstructionSites(typeof(AppAttestVerified).Assembly).ToList();

        Assert.Empty(sites.Where(s => !InIssuerNamespace(s)).Select(s => s.DeclaringType?.FullName + "." + s.Name));
    }

    [Fact]
    public void TheScannerFindsAConstructionSite()
    {
        // Proves the scan isn't vacuous: this assembly constructs one in Forge below (a test namespace, so a violation).
        Assert.Contains(ConstructionSites(typeof(AppAttestVerifiedTests).Assembly), m => m.Name.Contains(nameof(Forge), StringComparison.Ordinal));
        Assert.NotNull(Forge());
    }

    private static AppAttestVerified Forge() => new(InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77"), new byte[32]);

    private static bool InIssuerNamespace(MethodBase method)
    {
        var type = method.DeclaringType;
        while (type?.DeclaringType is not null)
        {
            type = type.DeclaringType;
        }

        var ns = type?.Namespace ?? string.Empty;
        return ns == AppAttestVerified.IssuerNamespace || ns.StartsWith(AppAttestVerified.IssuerNamespace + ".", StringComparison.Ordinal);
    }

    private static Type[] AllProductionTypes() => typeof(AppAttestVerified).Assembly.GetTypes();

    /// <summary>Every method of <paramref name="assembly"/> whose IL references the capability's constructor.</summary>
    private static IEnumerable<MethodBase> ConstructionSites(Assembly assembly)
    {
        const BindingFlags all = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly;
        foreach (var type in assembly.GetTypes())
        {
            var methods = type.GetMethods(all).Cast<MethodBase>().Concat(type.GetConstructors(all));
            if (type.TypeInitializer is { } cctor)
            {
                methods = methods.Append(cctor);
            }

            foreach (var method in methods)
            {
                if (References(method, Constructor))
                {
                    yield return method;
                }
            }
        }
    }

    private static readonly Dictionary<short, OpCode> OpCodesByValue = typeof(OpCodes)
        .GetFields(BindingFlags.Public | BindingFlags.Static)
        .Select(f => (OpCode)f.GetValue(null)!)
        .ToDictionary(o => o.Value);

    private static bool References(MethodBase method, MethodBase target)
    {
        var il = method.GetMethodBody()?.GetILAsByteArray();
        if (il is null)
        {
            return false;
        }

        var typeArgs = method.DeclaringType is { IsGenericType: true } t ? t.GetGenericArguments() : null;
        var methodArgs = method.IsGenericMethod ? method.GetGenericArguments() : null;
        var i = 0;
        while (i < il.Length)
        {
            var code = il[i] == 0xFE ? OpCodesByValue[(short)(0xFE00 | il[i + 1])] : OpCodesByValue[il[i]];
            i += code.Size;
            switch (code.OperandType)
            {
                case OperandType.InlineNone:
                    break;
                case OperandType.ShortInlineBrTarget:
                case OperandType.ShortInlineI:
                case OperandType.ShortInlineVar:
                    i += 1;
                    break;
                case OperandType.InlineVar:
                    i += 2;
                    break;
                case OperandType.InlineI8:
                case OperandType.InlineR:
                    i += 8;
                    break;
                case OperandType.InlineSwitch:
                    i += 4 + (4 * BitConverter.ToInt32(il, i));
                    break;
                case OperandType.InlineMethod:
                    var token = BitConverter.ToInt32(il, i);
                    i += 4;
                    var resolved = method.Module.ResolveMethod(token, typeArgs, methodArgs);
                    if (resolved is not null && resolved.Module == target.Module && resolved.MetadataToken == target.MetadataToken)
                    {
                        return true;
                    }

                    break;
                default:
                    i += 4;
                    break;
            }
        }

        return false;
    }
}
