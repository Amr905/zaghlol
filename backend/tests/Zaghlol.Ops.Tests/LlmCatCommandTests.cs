using System.Text.Json.Nodes;
using Zaghlol.Ops.Commands;
using Zaghlol.Ops.Tests.Support;

namespace Zaghlol.Ops.Tests;

/// <summary>T-354 (AC5): the <c>llmcat</c> commands mirror the four admin operations, have help text, and refuse a bad shape before any call.</summary>
public class LlmCatCommandTests
{
    private static readonly string[] Paths =
    [
        "llmcat corrections list", "llmcat corrections promote", "llmcat corrections reject", "llmcat corrections prompt-issue",
        "llmcat corrections export-prompt-issues", "llmcat confirmed list", "llmcat confirmed promote", "llmcat confirmed reject",
    ];

    [Fact]
    public void EveryLlmCatCommandIsRegisteredWithUsageAndSummary()
    {
        foreach (var path in Paths)
        {
            var spec = Registry.All.SingleOrDefault(s => s.Path == path);
            Assert.NotNull(spec);
            Assert.StartsWith(path, spec.Usage, StringComparison.Ordinal);
            Assert.True(spec.Summary.Length > 30, path);
        }
    }

    [Fact]
    public async Task CommandHelpIsPrintedWithoutACall()
    {
        var called = false;
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(new StubHandler((_, _) => { called = true; return StubHandler.Json(200, "{}"); }), idp, "GPA.UNUSED-0001");

        Assert.Equal(OpsCli.Success, await env.RunAsync("llmcat", "corrections", "promote", "--help"));

        Assert.Contains("--user-category", env.Output.ToString(), StringComparison.Ordinal);
        Assert.Contains("DRAFT", env.Output.ToString(), StringComparison.Ordinal);
        Assert.False(called);
    }

    [Theory]
    [InlineData("llmcat", "corrections", "promote", "--merchant-norm", "zawya coffee", "--ai-category", "dining", "--user-category", "custom")]
    [InlineData("llmcat", "corrections", "promote", "--merchant-norm", "z", "--ai-category", "dining", "--user-category", "education")]
    [InlineData("llmcat", "corrections", "reject", "--merchant-norm", "zawya coffee", "--ai-category", "Dining", "--user-category", "education")]
    [InlineData("llmcat", "corrections", "list", "--status", "collecting")]
    [InlineData("llmcat", "corrections", "list", "--limit", "101")]
    [InlineData("llmcat", "confirmed", "list", "--cursor", "-1")]
    [InlineData("llmcat", "confirmed", "promote", "--merchant-norm", "zawya coffee")]
    public async Task ABadShapeIsAUsageErrorAndSendsNothing(params string[] args)
    {
        var called = false;
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(new StubHandler((_, _) => { called = true; return StubHandler.Json(200, "{}"); }), idp, "GPA.UNUSED-0001");

        Assert.Equal(OpsCli.UsageError, await env.RunAsync(args));

        Assert.False(called);
    }

    [Fact]
    public async Task EachCommandPostsItsActionToTheRightRoute()
    {
        var handler = new StubHandler((_, _) => StubHandler.Json(200, "{\"status\":\"promoted\",\"rows\":1,\"merchantId\":null}"));
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(handler, idp, "GPA.UNUSED-0001");

        Assert.Equal(0, await env.RunAsync("llmcat", "corrections", "promote", "--merchant-norm", "zawya coffee", "--ai-category", "dining", "--user-category", "education"));
        Assert.Equal(0, await env.RunAsync("llmcat", "corrections", "reject", "--merchant-norm", "zawya coffee", "--ai-category", "dining", "--user-category", "custom"));
        Assert.Equal(0, await env.RunAsync("llmcat", "corrections", "prompt-issue", "--merchant-norm", "zawya coffee", "--ai-category", "dining", "--user-category", "custom"));
        Assert.Equal(0, await env.RunAsync("llmcat", "confirmed", "promote", "--merchant-norm", "zawya coffee", "--category", "dining"));
        Assert.Equal(0, await env.RunAsync("llmcat", "confirmed", "reject", "--merchant-norm", "zawya coffee", "--category", "dining"));

        var calls = handler.Calls.Where(c => c.Url.StartsWith("/admin/v1/llm-cat", StringComparison.Ordinal)).ToList();
        Assert.Equal(
            ["/admin/v1/llm-cat/corrections/resolve", "/admin/v1/llm-cat/corrections/resolve", "/admin/v1/llm-cat/corrections/resolve", "/admin/v1/llm-cat/confirmed/resolve", "/admin/v1/llm-cat/confirmed/resolve"],
            calls.Select(c => c.Url));
        Assert.Equal(["promote", "reject", "prompt_issue", "promote", "reject"], calls.Select(c => JsonNode.Parse(c.Body)!["action"]!.GetValue<string>()));
        Assert.Equal("custom", JsonNode.Parse(calls[1].Body)!["userCategory"]!.GetValue<string>());
    }

    [Fact]
    public async Task ExportPromptIssuesPagesAndPrintsYamlWithTheNameOnlyAsAComment()
    {
        var page = 0;
        var handler = new StubHandler((_, body) =>
        {
            Assert.Equal("prompt_issue", JsonNode.Parse(body)!["status"]!.GetValue<string>());
            page++;
            return page == 1
                ? StubHandler.Json(200, "{\"items\":[{\"merchantNorm\":\"zawya \\\"coffee\\\"\",\"aiCategory\":\"dining\",\"userCategory\":\"education\",\"votes\":3,\"firstSeen\":\"2026-11-20\",\"lastSeen\":\"2026-11-26\",\"status\":\"prompt_issue\"}],\"nextCursor\":\"1\"}")
                : StubHandler.Json(200, "{\"items\":[{\"merchantNorm\":\"مكتبة النور\",\"aiCategory\":\"dining\",\"userCategory\":\"custom\",\"votes\":1,\"firstSeen\":\"2026-11-21\",\"lastSeen\":\"2026-11-21\",\"status\":\"prompt_issue\"}],\"nextCursor\":null}");
        });
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(handler, idp, "GPA.UNUSED-0001");

        Assert.Equal(0, await env.RunAsync("llmcat", "corrections", "export-prompt-issues"));

        var output = env.Output.ToString();
        Assert.Equal(2, page);
        Assert.Contains("- id: prompt-issue-1", output, StringComparison.Ordinal);
        Assert.Contains("- id: prompt-issue-2", output, StringComparison.Ordinal);
        Assert.Contains("merchant: \"REPLACE-WITH-SYNTHETIC-NAME\"", output, StringComparison.Ordinal);
        Assert.Contains("# seen as: \"zawya \\u0022coffee\\u0022\"", output, StringComparison.Ordinal);
        Assert.Contains("expected_category: \"education\"", output, StringComparison.Ordinal);
        Assert.Contains("votes: 3", output, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ExportPromptIssuesWithNothingPrintsAnEmptyList()
    {
        var handler = new StubHandler((_, _) => StubHandler.Json(200, "{\"items\":[],\"nextCursor\":null}"));
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(handler, idp, "GPA.UNUSED-0001");

        Assert.Equal(0, await env.RunAsync("llmcat", "corrections", "export-prompt-issues"));

        Assert.EndsWith("[]", env.Output.ToString().TrimEnd(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task ExportPromptIssuesReportsAnApiRefusalWithTheUsualExitCode()
    {
        var handler = new StubHandler((_, _) => StubHandler.Json(403, "{\"type\":\"about:blank\",\"title\":\"Forbidden\",\"status\":403,\"code\":\"FORBIDDEN\"}", "application/problem+json"));
        using var idp = new CliTestIdp();
        using var env = new TestEnvironment(handler, idp, "GPA.UNUSED-0001");

        Assert.Equal(3, await env.RunAsync("llmcat", "corrections", "export-prompt-issues"));
    }
}
