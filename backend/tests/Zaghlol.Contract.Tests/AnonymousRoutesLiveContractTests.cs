using System.Security.Claims;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Metadata;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.Routing.Patterns;
using Microsoft.Extensions.DependencyInjection;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// T-175 L-6: authentication is on by default (a fallback authorization policy), and the routes the API leaves open are
/// exactly the OpenAPI operations that declare <c>security: []</c>. A new <c>/v1</c> route is therefore either
/// authenticated or a deliberate, spec-documented exception.
/// </summary>
public class AnonymousRoutesLiveContractTests(ContractApiFixture fixture) : IClassFixture<ContractApiFixture>
{
    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    [Fact]
    public async Task TheFallbackPolicyRefusesAnAnonymousCallerOfAnyRouteEndpointButNotUnmatchedRequests()
    {
        var policies = fixture.Services.GetRequiredService<IAuthorizationPolicyProvider>();
        var fallback = await policies.GetFallbackPolicyAsync();
        Assert.NotNull(fallback);

        var authorization = fixture.Services.GetRequiredService<IAuthorizationService>();
        var anonymous = new ClaimsPrincipal(new ClaimsIdentity());
        var signedIn = new ClaimsPrincipal(new ClaimsIdentity("test"));
        var route = new RouteEndpoint(_ => Task.CompletedTask, RoutePatternFactory.Parse("/v1/new-route"), 0, EndpointMetadataCollection.Empty, "new route");

        Assert.False((await authorization.AuthorizeAsync(anonymous, Context(route), fallback)).Succeeded);
        Assert.True((await authorization.AuthorizeAsync(signedIn, Context(route), fallback)).Succeeded);
        // No route matched (404) or the 405 endpoint: not ours to protect; the documented problem answers stay.
        Assert.True((await authorization.AuthorizeAsync(anonymous, Context(null), fallback)).Succeeded);
        Assert.True((await authorization.AuthorizeAsync(anonymous, Context(new Endpoint(_ => Task.CompletedTask, EndpointMetadataCollection.Empty, "405 HTTP Method Not Supported")), fallback)).Succeeded);
    }

    private static DefaultHttpContext Context(Endpoint? endpoint)
    {
        var context = new DefaultHttpContext();
        context.SetEndpoint(endpoint);
        return context;
    }

    [Fact]
    public void TheAnonymousRoutesOfTheApiAreExactlyTheSpecOperationsWithEmptySecurity()
    {
        var spec = Spec.Operations()
            .Where(o => o.Body["security"] is null || (o.Body["security"] is JsonArray security && security.Count == 0))
            .Select(o => o.Method.ToUpperInvariant() + " " + o.Path)
            .Order(StringComparer.Ordinal)
            .ToList();

        var source = fixture.Services.GetRequiredService<EndpointDataSource>();
        var code = new SortedSet<string>(StringComparer.Ordinal);
        var unprotected = new List<string>();
        foreach (var endpoint in source.Endpoints.OfType<RouteEndpoint>())
        {
            var route = Template(endpoint.RoutePattern);
            if (!route.StartsWith("/v1/", StringComparison.Ordinal) && !route.StartsWith("/admin/", StringComparison.Ordinal))
            {
                continue;
            }

            var anonymous = endpoint.Metadata.GetMetadata<IAllowAnonymous>() is not null;
            var hasPolicy = endpoint.Metadata.GetOrderedMetadata<IAuthorizeData>().Any();
            foreach (var method in endpoint.Metadata.GetMetadata<IHttpMethodMetadata>()?.HttpMethods ?? new[] { "*" })
            {
                var key = method.ToUpperInvariant() + " " + route;
                if (anonymous)
                {
                    code.Add(key);
                }
                else if (!hasPolicy)
                {
                    unprotected.Add(key); // only the fallback policy protects it: allowed, but it must not be a spec-anonymous operation
                }
            }
        }

        Assert.True(code.Count >= 4, $"only {code.Count} anonymous routes found");
        Assert.Equal(spec, code.ToList());
        Assert.DoesNotContain(unprotected, spec.Contains);
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
