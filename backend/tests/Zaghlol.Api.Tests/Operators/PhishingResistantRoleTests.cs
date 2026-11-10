using System.Net;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Tests.Installs;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Testing;
using OperatorRoles = Zaghlol.Application.Operators.OperatorRoles;

namespace Zaghlol.Api.Tests.Operators;

/// <summary>
/// T-136 AC3 (R4-6) and AC5 over HTTP, through the real operator scheme, validator and per-role policies. The support write
/// endpoints are T-186's, so this host maps one probe endpoint per role, the way they will be mapped. Enforced: a
/// <c>support_agent</c> and a <c>support_lead</c> token without the authentication context get 403 and with it 200.
/// Advisory: 200, and the diag counter counts. Roles imply nothing: <c>support_lead</c> is not <c>support_agent</c>, and
/// neither is <c>support_viewer</c>.
/// </summary>
[Collection(ApiHostGroup.Name)]
public sealed class PhishingResistantRoleTests : IDisposable
{
    private const string ContextId = "c1";

    private readonly FakeOidcIssuer issuer = new();
    private readonly FakeOperatorDirectory directory = new();

    public void Dispose() => issuer.Dispose();

    [Theory]
    [InlineData(OperatorRoles.SupportAgent)]
    [InlineData(OperatorRoles.SupportLead)]
    public async Task EnforcedModeAnswers403WithoutTheContextAnd200WithIt(string role)
    {
        await using var app = await StartAsync("Enforced");
        using var client = app.GetTestClient();
        var subject = "enforced-" + role;
        directory.Add(subject, role);

        var without = await SendAsync(client, role, Token(subject, acrs: null));
        var otherContext = await SendAsync(client, role, Token(subject, acrs: ["c2"]));
        var with = await SendAsync(client, role, Token(subject, acrs: ["c2", ContextId]));

        Assert.Equal(HttpStatusCode.Forbidden, without);
        Assert.Equal(HttpStatusCode.Forbidden, otherContext);
        Assert.Equal(HttpStatusCode.OK, with);
    }

    [Theory]
    [InlineData(OperatorRoles.SupportAgent)]
    [InlineData(OperatorRoles.SupportLead)]
    public async Task AdvisoryModeAnswers200AndCountsTheUnprovenRequest(string role)
    {
        using var counters = new CounterRecorder();
        await using var app = await StartAsync("Advisory");
        using var client = app.GetTestClient();
        var subject = "advisory-" + role;
        directory.Add(subject, role);

        var status = await SendAsync(client, role, Token(subject, acrs: null));

        Assert.Equal(HttpStatusCode.OK, status);
        Assert.Equal(1, counters.Total("zaghlol.diag.operator_phishing_resistant_unproven", role));
    }

    [Fact]
    public async Task RolesImplyNothing()
    {
        await using var app = await StartAsync("Enforced");
        using var client = app.GetTestClient();
        directory.Add("lead", OperatorRoles.SupportLead);
        directory.Add("agent", OperatorRoles.SupportAgent);
        directory.Add("viewer", OperatorRoles.SupportViewer);

        Assert.Equal(HttpStatusCode.Forbidden, await SendAsync(client, OperatorRoles.SupportAgent, Token("lead", [ContextId])));
        Assert.Equal(HttpStatusCode.Forbidden, await SendAsync(client, OperatorRoles.SupportViewer, Token("lead", [ContextId])));
        Assert.Equal(HttpStatusCode.Forbidden, await SendAsync(client, OperatorRoles.SupportLead, Token("agent", [ContextId])));
        Assert.Equal(HttpStatusCode.Forbidden, await SendAsync(client, OperatorRoles.SupportViewer, Token("agent", [ContextId])));
        Assert.Equal(HttpStatusCode.Forbidden, await SendAsync(client, OperatorRoles.SupportAgent, Token("viewer", [ContextId])));
        Assert.Equal(HttpStatusCode.Forbidden, await SendAsync(client, OperatorRoles.SupportLead, Token("viewer", [ContextId])));
        Assert.Equal(HttpStatusCode.OK, await SendAsync(client, OperatorRoles.SupportViewer, Token("viewer", null)));
    }

    [Fact]
    public async Task ARefusedTokenIs401AndATokenWithoutTheMfaSignalToo()
    {
        await using var app = await StartAsync("Advisory");
        using var client = app.GetTestClient();
        directory.Add("viewer", OperatorRoles.SupportViewer);

        var noMfa = issuer.Mint(new OperatorTokenSpec { Subject = "viewer", Amr = ["pwd"] }, DateTimeOffset.UtcNow);

        Assert.Equal(HttpStatusCode.Unauthorized, await SendAsync(client, OperatorRoles.SupportViewer, noMfa));
        Assert.Equal(HttpStatusCode.Unauthorized, await SendAsync(client, OperatorRoles.SupportViewer, null));
    }

    private string Token(string subject, IReadOnlyList<string>? acrs) =>
        issuer.Mint(new OperatorTokenSpec { Subject = subject, Acrs = acrs }, DateTimeOffset.UtcNow);

    private static async Task<HttpStatusCode> SendAsync(HttpClient client, string role, string? token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/probe/" + role);
        if (token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        }

        using var response = await client.SendAsync(request);
        return response.StatusCode;
    }

    private async Task<Microsoft.AspNetCore.Builder.WebApplication> StartAsync(string mode)
    {
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = "Testing" });
        builder.WebHost.UseTestServer();
        builder.Configuration.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["OperatorAuth:Enabled"] = "true",
            ["OperatorAuth:Profile"] = "Entra",
            ["OperatorAuth:Issuer"] = FakeOidcIssuer.DefaultIssuer,
            ["OperatorAuth:Audiences:0"] = FakeOidcIssuer.CliAudience,
            ["OperatorAuth:PhishingResistantMode"] = mode,
            ["OperatorAuth:RequiredAcrs"] = ContextId,
        });
        builder.Services.AddSingleton<ZaghlolMetrics>();
        builder.Services.AddProblemDetails();
        // Before AddZaghlolOperatorAuth, whose TryAdd then keeps the fake (Development validates the whole graph).
        builder.Services.AddSingleton<Application.Operators.IOperatorDirectory>(directory);
        builder.Services.AddOperatorAuthentication();
        builder.Services.AddZaghlolOperatorAuth();
        builder.Services.AddSingleton<TimeProvider>(new ManualClock());
        builder.Services.AddHttpClient(OidcKeyCache.HttpClientName).ConfigurePrimaryHttpMessageHandler(() => issuer.CreateHandler());

        var app = builder.Build();
        app.UseRouting();
        app.UseAuthentication();
        app.UseAuthorization();
        foreach (var role in OperatorRoles.All)
        {
            app.MapPost("/probe/" + role, () => Results.Ok()).RequireOperatorRole(role);
        }

        await app.StartAsync();
        return app;
    }
}
