using System.Reflection;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization.Metadata;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Api.Json;
using Zaghlol.Domain;

namespace Zaghlol.Api.Tests.Installs;

/// <summary>
/// Reflection rules over the API assembly: secret-carrying DTO members are <see cref="Sensitive{T}"/> (T-138 code #3, tests
/// m7) and <c>/v1</c> code can't reach a database role other than App (FU-021).
/// </summary>
[Collection(ApiHostGroup.Name)]
public class ArchitectureTests
{
    private static readonly string[] SensitiveNames =
    [
        "installToken", "rotateInstallToken", "purchaseToken", "idToken", "nonce", "attestation", "assertion", "code",
        "refreshToken", "orderId", "seatKeys", "signedTransaction", "signedTransactions",
    ];

    private static readonly BindingFlags Members =
        BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly;

    private static IEnumerable<Type> ApiTypes => typeof(ApiPipeline).Assembly.GetTypes()
        .Where(t => !t.IsDefined(typeof(CompilerGeneratedAttribute), inherit: false) && !t.Name.StartsWith('<'));

    [Fact]
    public void EverySecretCarryingMemberIsSensitive()
    {
        var offenders = new List<string>();
        foreach (var type in ApiTypes.Where(t => !typeof(System.Text.Json.Serialization.JsonSerializerContext).IsAssignableFrom(t)))
        {
            var members = type.GetProperties(Members).Select(p => (p.Name, p.PropertyType))
                .Concat(type.GetConstructors(Members).SelectMany(c => c.GetParameters()).Select(p => (p.Name ?? string.Empty, p.ParameterType)));
            foreach (var (name, memberType) in members)
            {
                var json = JsonNamingPolicy.CamelCase.ConvertName(name);
                if (SensitiveNames.Contains(json, StringComparer.Ordinal) && !IsSensitive(memberType))
                {
                    offenders.Add($"{type.FullName}.{name}: {memberType.Name}");
                }
            }
        }

        Assert.Empty(offenders);
        Assert.Contains(
            typeof(Endpoints.V1.InstallResponse).GetProperties(),
            p => p.Name == "InstallToken" && p.PropertyType == typeof(Sensitive<string>));
    }

    [Fact]
    public void V1CodeNeverSeesADatabaseRoleOrTheGenericFactory()
    {
        string[] namespaces = ["Zaghlol.Api.Endpoints.V1", "Zaghlol.Api.Auth", "Zaghlol.Api.Idempotency"];
        string[] forbidden = ["Zaghlol.Infrastructure.Persistence.DatabaseRole", "Zaghlol.Infrastructure.Persistence.IZaghlolDbContextFactory"];

        var types = ApiTypes.Where(t => namespaces.Contains(t.Namespace, StringComparer.Ordinal)).ToList();
        var referenced = types.SelectMany(t =>
            t.GetFields(Members).Select(f => f.FieldType)
                .Concat(t.GetProperties(Members).Select(p => p.PropertyType))
                .Concat(t.GetMethods(Members).SelectMany(m => m.GetParameters().Select(p => p.ParameterType).Append(m.ReturnType)))
                .Concat(t.GetConstructors(Members).SelectMany(c => c.GetParameters()).Select(p => p.ParameterType)))
            .Select(t => t.FullName ?? t.Name)
            .ToHashSet(StringComparer.Ordinal);

        Assert.NotEmpty(types);
        Assert.Empty(referenced.Intersect(forbidden, StringComparer.Ordinal));
        Assert.Null(typeof(ApiPipeline).Assembly.GetReferencedAssemblies().FirstOrDefault(a => a.Name == "Zaghlol.Ops"));
    }

    [Fact]
    public void IdempotentHandlersNeverTakeTheInstallTokenRotator()
    {
        // T-130 S-3: a stored, replayable body must never carry a rotated install token.
        using var kms = Zaghlol.Testing.FakeKms.CreateDefault();
        using var factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            const string Unreachable = "Host=127.0.0.1;Port=1;Database=none;Username=none";
            builder.UseSetting("ConnectionStrings:App", Unreachable);
            builder.UseSetting("ConnectionStrings:Admin", Unreachable);
            foreach (var (key, value) in kms.Settings())
            {
                builder.UseSetting(key, value);
            }

            builder.ConfigureServices(services => kms.Use(services));
        });
        using var client = factory.CreateClient();

        var idempotent = factory.Services.GetRequiredService<EndpointDataSource>().Endpoints
            .Where(e => e.Metadata.GetMetadata<Idempotency.IdempotentEndpointMetadata>() is not null)
            .ToList();

        Assert.Contains(idempotent, e => e.Metadata.GetMetadata<IEndpointNameMetadata>()?.EndpointName == "verifyPurchase");
        Assert.All(idempotent, endpoint =>
        {
            var handler = endpoint.Metadata.GetMetadata<MethodInfo>();
            Assert.NotNull(handler);
            Assert.DoesNotContain(handler.GetParameters(), p => p.ParameterType == typeof(Auth.IInstallTokenRotator));
        });
    }

    [Fact]
    public void TheUnknownFieldProbeWalksNestedObjectsAndArrays()
    {
        var options = new JsonSerializerOptions(JsonSerializerOptions.Default) { TypeInfoResolver = new DefaultJsonTypeInfoResolver() };
        options.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        var info = options.GetTypeInfo(typeof(Outer));

        Assert.False(Probe("{\"name\":\"a\",\"inner\":{\"value\":1},\"items\":[{\"value\":2}]}", info));
        Assert.True(Probe("{\"name\":\"a\",\"extra\":1}", info));
        Assert.True(Probe("{\"inner\":{\"value\":1,\"extra\":true}}", info));
        Assert.True(Probe("{\"items\":[{\"value\":1},{\"extra\":[]}]}", info));
        Assert.False(Probe("{\"inner\":[1,2]}", info));
        Assert.False(Probe("{\"name\":", info));
    }

    [Fact]
    public void TimestampsAreWrittenAndReadOnlyAsUtcZ()
    {
        var options = new JsonSerializerOptions { Converters = { new UtcZDateTimeOffsetConverter() } };
        var instant = new DateTimeOffset(2026, 11, 3, 18, 22, 1, 500, TimeSpan.Zero);

        Assert.Equal("\"2026-11-03T18:22:01Z\"", JsonSerializer.Serialize(instant, options));
        Assert.Equal(instant, JsonSerializer.Deserialize<DateTimeOffset>("\"2026-11-03T18:22:01.5Z\"", options));
        Assert.Throws<JsonException>(() => JsonSerializer.Serialize(new DateTimeOffset(2026, 11, 3, 20, 22, 1, TimeSpan.FromHours(2)), options));
        foreach (var text in new[] { "\"2026-11-03T18:22:01+00:00\"", "\"2026-11-03T20:22:01+02:00\"", "\"2026-11-03 18:22:01Z\"", "\"2026-11-03\"", "1762194121" })
        {
            Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<DateTimeOffset>(text, options));
        }
    }

    [Theory]
    [InlineData("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77", true)]
    [InlineData("0193f2c4-7a10-4c52-ad3e-5b1f8a2c6e77", true)]
    [InlineData("0193F2C4-7A10-4C52-9D3E-5B1F8A2C6E77", false)]
    [InlineData("0193f2c4-7a10-1c52-9d3e-5b1f8a2c6e77", false)]
    [InlineData("0193f2c4-7a10-4c52-cd3e-5b1f8a2c6e77", false)]
    [InlineData("{0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77}", false)]
    [InlineData("0193f2c47a104c529d3e5b1f8a2c6e77", false)]
    [InlineData("install-a", false)]
    [InlineData("", false)]
    public void InstallIdIsALowercaseUuidV4(string text, bool valid)
    {
        Assert.Equal(valid, InstallId.TryParse(text, out _));
    }

    private static bool IsSensitive(Type type)
    {
        var underlying = Nullable.GetUnderlyingType(type) ?? type;
        return underlying.IsGenericType && underlying.GetGenericTypeDefinition() == typeof(Sensitive<>);
    }

    private static bool Probe(string json, JsonTypeInfo info) => StrictJson.HasUnknownMember(Encoding.UTF8.GetBytes(json), info);

    private sealed record Inner(int Value);

    private sealed record Outer(string? Name, Inner? Inner, IReadOnlyList<Inner>? Items);
}
