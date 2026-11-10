using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Metadata;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.Routing.Patterns;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Api.Auth;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// T-136 (live form of <c>AdminOperationRolesMatchTheSpecRequiredRoles</c>): every <c>/admin/v1</c> endpoint the running API
/// maps is an operation of the OpenAPI file, and the operator roles its authorization policies demand are exactly that
/// operation's <c>x-required-roles</c>. Every role the code knows has a policy.
/// </summary>
public class AdminRolesLiveContractTests(ContractApiFixture fixture) : IClassFixture<ContractApiFixture>
{
    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    [Fact]
    public void AdminOperationRolesInCodeMatchTheSpecRequiredRoles()
    {
        var spec = Spec.Operations()
            .Where(o => o.Path.StartsWith("/admin/v1/", StringComparison.Ordinal))
            .ToDictionary(
                o => o.Method.ToUpperInvariant() + " " + o.Path,
                o => (o.Body["x-required-roles"] as JsonArray ?? new JsonArray()).Select(n => n!.GetValue<string>()).Order(StringComparer.Ordinal).ToList(),
                StringComparer.Ordinal);

        var source = fixture.Services.GetRequiredService<EndpointDataSource>();
        var failures = new List<string>();
        var mapped = 0;
        foreach (var endpoint in source.Endpoints.OfType<RouteEndpoint>())
        {
            var route = Template(endpoint.RoutePattern);
            if (!route.StartsWith("/admin/v1/", StringComparison.Ordinal))
            {
                continue;
            }

            var roles = endpoint.Metadata.GetOrderedMetadata<IAuthorizeData>()
                .Select(a => a.Policy)
                .OfType<string>()
                .Where(p => p.StartsWith(OperatorAuthentication.PolicyPrefix, StringComparison.Ordinal))
                .Select(p => p[OperatorAuthentication.PolicyPrefix.Length..])
                .Distinct(StringComparer.Ordinal)
                .Order(StringComparer.Ordinal)
                .ToList();
            foreach (var method in endpoint.Metadata.GetMetadata<IHttpMethodMetadata>()?.HttpMethods ?? new[] { "*" })
            {
                mapped++;
                var key = method + " " + route;
                if (!spec.TryGetValue(key, out var required))
                {
                    failures.Add($"{key}: mapped by the API but not an operation of the spec");
                }
                else if (!required.SequenceEqual(roles, StringComparer.Ordinal))
                {
                    failures.Add($"{key}: the code requires [{string.Join(", ", roles)}], x-required-roles is [{string.Join(", ", required)}]");
                }
            }
        }

        Assert.True(mapped >= 7, $"only {mapped} admin operations mapped");
        Assert.Empty(failures);
    }

    [Fact]
    public async Task EveryKnownRoleHasAPolicy()
    {
        var policies = fixture.Services.GetRequiredService<IAuthorizationPolicyProvider>();
        foreach (var role in OperatorRoles.All)
        {
            Assert.NotNull(await policies.GetPolicyAsync(OperatorAuthentication.PolicyFor(role)));
        }

        Assert.Equal(6, OperatorRoles.All.Count);
    }

    private static string Template(RoutePattern pattern) =>
        "/" + string.Join('/', pattern.PathSegments.Select(segment => string.Concat(segment.Parts.Select(part => part switch
        {
            RoutePatternLiteralPart literal => literal.Content,
            RoutePatternParameterPart parameter => "{" + parameter.Name + "}",
            RoutePatternSeparatorPart separator => separator.Content,
            _ => "?",
        }))));
}
