using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests;

/// <summary>Process-level rules: the KMS fails closed, and every API test class runs in <see cref="ApiHostGroup"/>.</summary>
[Collection(ApiHostGroup.Name)]
public class HostStartupTests
{
    private const string Unreachable = "Host=127.0.0.1;Port=1;Database=none;Username=none";

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    public void TheApiRefusesToStartWithTheLocalKmsOutsideDevelopment(string environment)
    {
        using var kms = FakeKms.CreateDefault();
        using var factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment(environment);
            builder.UseSetting("ConnectionStrings:App", Unreachable);
            builder.UseSetting("ConnectionStrings:Admin", Unreachable);
            builder.UseSetting("Kms:Provider", "Local");
            builder.UseSetting("Kms:Local:KeyDirectory", Path.GetTempPath());
            foreach (var (key, value) in kms.Settings())
            {
                builder.UseSetting(key, value);
            }
        });

        var error = Assert.ThrowsAny<Exception>(() => factory.CreateClient());

        Assert.Contains(Chain(error), e => e is KmsConfigurationException && e.Message.Contains("Development and Testing", StringComparison.Ordinal));
    }

    [Fact]
    public void TheApiRefusesToStartWithoutAKeyRing()
    {
        using var factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseSetting("ConnectionStrings:App", Unreachable);
            builder.UseSetting("ConnectionStrings:Admin", Unreachable);
        });

        var error = Assert.ThrowsAny<Exception>(() => factory.CreateClient());

        Assert.Contains(Chain(error), e => e is KmsConfigurationException);
    }

    [Fact]
    public void EveryTestClassThatCanBootAHostIsInTheApiHostGroup()
    {
        // FU-026: Serilog's request logging writes to the process-wide logger, which each host replaces; two hosts in
        // parallel steal each other's logs. Every test class of this assembly therefore runs in the one collection.
        var testClasses = typeof(HostStartupTests).Assembly.GetTypes()
            .Where(t => t.IsClass && !t.IsAbstract)
            .Where(t => t.GetMethods().Any(m => m.IsDefined(typeof(FactAttribute), inherit: true)))
            .ToList();

        var outside = testClasses
            .Where(t => !t.GetCustomAttributesData().Any(a =>
                a.AttributeType == typeof(CollectionAttribute)
                && a.ConstructorArguments.Count == 1
                && Equals(a.ConstructorArguments[0].Value, ApiHostGroup.Name)))
            .Select(t => t.Name)
            .ToList();

        Assert.True(testClasses.Count >= 5, $"found only {testClasses.Count} test classes");
        Assert.Empty(outside);
    }

    private static IEnumerable<Exception> Chain(Exception error)
    {
        var pending = new Stack<Exception>([error]);
        while (pending.TryPop(out var current))
        {
            yield return current;
            if (current is AggregateException aggregate)
            {
                foreach (var inner in aggregate.InnerExceptions)
                {
                    pending.Push(inner);
                }
            }
            else if (current.InnerException is not null)
            {
                pending.Push(current.InnerException);
            }
        }
    }
}
