using System.Text.Json.Nodes;
using Zaghlol.Ops.Tests.Support;

namespace Zaghlol.Ops.Tests;

/// <summary>
/// D-57 end to end: a sentinel order ID typed at the prompt reaches the API in exactly one request body and appears nowhere else:
/// not in stdout, stderr, the prompt text, any URL or header, whatever the API answers, even if the API echoes it back.
/// </summary>
public class OrderIdSentinelTests
{
    private const string Sentinel = "GPA.SENTINEL-4242-9917-0001";
    private static readonly string Purchase = "0193f2c4-7a10-7c52-9d3e-5b1f8a2c6e01";
    private static readonly string Install = "0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77";

    public static TheoryData<string[], string> Commands => new()
    {
        { ["support", "move", "--purchase", Purchase, "--to", Install, "--reason", "lost_or_broken_phone", "--ticket", "ZG-10422"], "/admin/v1/support/seat:move" },
        { ["support", "move", "--purchase", Purchase, "--to", Install, "--reason", "correction", "--corrects", "48211", "--ticket", "ZG-10422"], "/admin/v1/support/seat:move" },
        { ["support", "detach", "--purchase", Purchase, "--ticket", "ZG-10431", "--corrects", "48211"], "/admin/v1/support/purchase:detach" },
        { ["support", "unfreeze", "--purchase", Purchase, "--ticket", "ZG-10457"], "/admin/v1/support/purchase:unfreeze" },
    };

    public static TheoryData<int, string, int> Outcomes => new()
    {
        { 200, "{\"purchaseId\":\"" + Purchase + "\",\"moved\":true,\"attached\":false,\"auditId\":7}", 0 },
        { 409, "{\"type\":\"about:blank\",\"title\":\"Conflict\",\"status\":409,\"code\":\"ADMIN_CONFLICT\"}", 1 },
        { 422, "{\"type\":\"about:blank\",\"title\":\"Ownership check failed\",\"status\":422,\"code\":\"OWNERSHIP_CHECK_FAILED\"}", 1 },
        { 503, "{\"type\":\"about:blank\",\"title\":\"Unavailable\",\"status\":503,\"code\":\"UPSTREAM_UNAVAILABLE\",\"retryAfterSeconds\":5}", 1 },
        { 403, "{\"type\":\"about:blank\",\"title\":\"Forbidden\",\"status\":403,\"code\":\"FORBIDDEN\"}", 3 },
        { 500, "<html>boom</html>", 1 },
    };

    [Theory]
    [MemberData(nameof(Commands))]
    public async Task TheOrderIdIsSentOnceInTheBodyAndNowhereElseForEveryOutcome(string[] args, string path)
    {
        foreach (var data in Outcomes.Select(o => (Status: (int)o[0], Body: (string)o[1], Exit: (int)o[2])))
        {
            var handler = new StubHandler((_, _) => StubHandler.Json(data.Status, data.Body, data.Status >= 400 ? "application/problem+json" : "application/json"));
            using var idp = new CliTestIdp();
            using var env = new TestEnvironment(handler, idp, Sentinel);
            SetTemptingVariables(env);

            var code = await env.RunAsync(args);

            Assert.Equal(data.Exit, code);
            AssertSentOnceOnly(handler, path, env);
        }
    }

    [Fact]
    public async Task AnApiThatEchoesTheOrderIdBackStillCannotShowItOnTheScreen()
    {
        var handler = new StubHandler((_, body) => StubHandler.Json(
            409,
            "{\"type\":\"about:blank\",\"title\":\"Bad " + Sentinel + "\",\"status\":409,\"code\":\"ADMIN_CONFLICT\",\"detail\":\"order " + Sentinel + " refused\",\"correlationId\":\"c-1\"}",
            "application/problem+json"));
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(handler, idp, Sentinel);

        var code = await env.RunAsync("support", "unfreeze", "--purchase", Purchase, "--ticket", "ZG-1");

        Assert.Equal(1, code);
        Assert.DoesNotContain(Sentinel, env.AllOutput, StringComparison.Ordinal);
        Assert.Contains("[redacted]", env.Error.ToString(), StringComparison.Ordinal);
        Assert.Contains("ADMIN_CONFLICT", env.Error.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task ASuccessBodyThatEchoesTheOrderIdIsRedactedToo()
    {
        var handler = new StubHandler((_, _) => StubHandler.Json(200, "{\"unfrozen\":true,\"note\":\"" + Sentinel + "\"}"));
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(handler, idp, Sentinel);

        Assert.Equal(0, await env.RunAsync("support", "unfreeze", "--purchase", Purchase, "--ticket", "ZG-1"));

        Assert.DoesNotContain(Sentinel, env.AllOutput, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ANetworkFailureAndATimeoutNeverShowTheOrderId()
    {
        var handler = new StubHandler((_, _) => throw new HttpRequestException("connect failed while sending " + Sentinel));
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(handler, idp, Sentinel);

        var code = await env.RunAsync("support", "detach", "--purchase", Purchase, "--ticket", "ZG-1", "--corrects", "5");

        Assert.Equal(4, code);
        Assert.DoesNotContain(Sentinel, env.AllOutput, StringComparison.Ordinal);
        Assert.Contains("could not be reached", env.Error.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task RedirectedInputIsRefusedBeforeSignInAndBeforeAnyRequest()
    {
        var handler = new StubHandler((_, _) => StubHandler.Json(200, "{}"));
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(handler, idp, Sentinel, interactive: false);

        var code = await env.RunAsync("support", "unfreeze", "--purchase", Purchase, "--ticket", "ZG-1");

        Assert.Equal(2, code);
        Assert.Empty(handler.Calls);
        Assert.Empty(idp.Requests);
        Assert.Equal(0, idp.Browser.Opened);
        Assert.Contains("interactive terminal", env.Error.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(Sentinel, env.AllOutput, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("ABC")]
    [InlineData("GPA_BAD_SHAPE_1")]
    public async Task ABadOrderIdSendsNothing(string typed)
    {
        var handler = new StubHandler((_, _) => StubHandler.Json(200, "{}"));
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(handler, idp, typed);

        var code = await env.RunAsync("support", "unfreeze", "--purchase", Purchase, "--ticket", "ZG-1");

        Assert.Equal(2, code);
        Assert.Empty(handler.Calls);
        Assert.DoesNotContain(typed, env.AllOutput.Replace("ZG-1", string.Empty, StringComparison.Ordinal), StringComparison.Ordinal);
    }

    [Fact]
    public async Task SignInHappensBeforeThePromptSoNoSecretWaitsOnABrowser()
    {
        var order = new List<string>();
        var handler = new StubHandler((_, _) =>
        {
            order.Add("api");
            return StubHandler.Json(200, "{\"unfrozen\":false}");
        });
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(handler, idp, Sentinel);

        await env.RunAsync("support", "unfreeze", "--purchase", Purchase, "--ticket", "ZG-1");

        Assert.Equal(1, idp.TokenRequests);
        Assert.Single(order);
        Assert.Contains("Store order ID", env.PromptText.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task EachCommandChecksItsArgumentsBeforeSigningInOrAsking()
    {
        var handler = new StubHandler((_, _) => StubHandler.Json(200, "{}"));
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(handler, idp, Sentinel);

        Assert.Equal(2, await env.RunAsync("support", "move", "--purchase", "nope", "--to", Install, "--reason", "other", "--ticket", "ZG-1"));
        Assert.Equal(2, await env.RunAsync("support", "move", "--purchase", Purchase, "--to", Install, "--reason", "bogus", "--ticket", "ZG-1"));
        Assert.Equal(2, await env.RunAsync("support", "move", "--purchase", Purchase, "--to", Install, "--reason", "correction", "--ticket", "ZG-1"));
        Assert.Equal(2, await env.RunAsync("support", "move", "--purchase", Purchase, "--to", Install, "--reason", "other", "--corrects", "3", "--ticket", "ZG-1"));
        Assert.Equal(2, await env.RunAsync("support", "move", "--purchase", Purchase, "--to", Install, "--reason", "correction", "--corrects", "3", "--attach", "--ticket", "ZG-1"));
        Assert.Equal(2, await env.RunAsync("support", "detach", "--purchase", Purchase, "--ticket", "ZG-1"));
        Assert.Equal(2, await env.RunAsync("support", "unfreeze", "--purchase", Purchase, "--ticket", "bad ticket"));

        Assert.Empty(idp.Requests);
        Assert.Empty(handler.Calls);
        Assert.Equal(string.Empty, env.PromptText.ToString());
    }

    [Fact]
    public async Task TheMoveBodyHasExactlyTheDocumentedMembers()
    {
        var handler = new StubHandler((_, _) => StubHandler.Json(200, "{\"moved\":true}"));
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(handler, idp, Sentinel);

        await env.RunAsync("support", "move", "--purchase", Purchase, "--to", Install, "--reason", "buying_phone_gone", "--ticket", "ZG-1", "--attach");

        var body = JsonNode.Parse(handler.Calls.Single().Body)!.AsObject();
        Assert.Equal(
            ["attachToAccount", "ownershipCheck", "purchaseId", "reasonCode", "ticketRef", "toInstallId"],
            body.Select(p => p.Key).Order(StringComparer.Ordinal).ToArray());
        Assert.Equal(Sentinel, body["ownershipCheck"]!.GetValue<string>());
        Assert.True(body["attachToAccount"]!.GetValue<bool>());
        Assert.StartsWith("Bearer ", handler.Calls.Single().Authorization, StringComparison.Ordinal);
    }

    private static void SetTemptingVariables(TestEnvironment env)
    {
        foreach (var name in new[] { "ORDER_ID", "ZAGHLOL_OPS_ORDER_ID", "ZAGHLOL_OPS_OWNERSHIP_CHECK", "OWNERSHIP_CHECK", "ZAGHLOL_ORDER_ID" })
        {
            env.Variables[name] = "ENV-SENTINEL-NEVER-SENT";
        }
    }

    private static void AssertSentOnceOnly(StubHandler handler, string path, TestEnvironment env)
    {
        var call = Assert.Single(handler.Calls);
        Assert.Equal(path, call.Url);
        Assert.Equal(1, call.Body.Split(Sentinel, StringSplitOptions.None).Length - 1);
        Assert.DoesNotContain("ENV-SENTINEL", call.Body, StringComparison.Ordinal);
        Assert.DoesNotContain(Sentinel, call.Url + call.Authorization, StringComparison.Ordinal);
        Assert.DoesNotContain(Sentinel, env.AllOutput, StringComparison.Ordinal);
        Assert.DoesNotContain("ENV-SENTINEL", env.AllOutput, StringComparison.Ordinal);
        Assert.DoesNotContain("SENTINEL-4242", env.AllOutput, StringComparison.Ordinal);
        Assert.DoesNotContain(Sentinel, env.Store.ToString() ?? string.Empty, StringComparison.Ordinal);
    }
}
