using System.Globalization;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Unicode;
using Zaghlol.Ops.Api;
using Zaghlol.Ops.Cli;

namespace Zaghlol.Ops.Commands;

/// <summary>
/// Review of the automatic categories (llm-categorise §6; role <c>catalog_editor</c>). Groups only: the server never lists an install
/// or a hash. One command per action; the three corrections actions share the <c>adminResolveLlmCatCorrection</c> operation, so only
/// <c>promote</c> names it (the spec-coverage test wants each operation named once).
/// </summary>
internal static class LlmCatCommands
{
    private const string Corrections = "/admin/v1/llm-cat/corrections/";
    private const string Confirmed = "/admin/v1/llm-cat/confirmed/";
    private static readonly string[] Statuses = ["open", "promoted", "rejected", "prompt_issue"];

    private static readonly JsonSerializerOptions Scalar = new() { Encoder = JavaScriptEncoder.Create(UnicodeRanges.BasicLatin, UnicodeRanges.Arabic) };

    private static readonly IReadOnlyList<Opt> GroupOptions = [new("merchant-norm"), new("ai-category"), new("user-category")];

    private static readonly IReadOnlyList<Opt> ConfirmedOptions = [new("merchant-norm"), new("category")];

    public static IReadOnlyList<CommandSpec> Specs { get; } =
    [
        new("llmcat corrections list",
            "List groups of user corrections of automatic categories, open first, most installs first (adminQueryLlmCatCorrections). Counts only.",
            "llmcat corrections list [--status open|promoted|rejected|prompt_issue] [--limit 1-100] [--cursor C]",
            [new("status"), new("limit"), new("cursor")], 0, 0, ListCorrectionsAsync, "adminQueryLlmCatCorrections"),
        new("llmcat corrections promote",
            "Promote a correction group into the DRAFT catalog (merchant + exact alias in the user's category); publish separately. Not for 'custom' (adminResolveLlmCatCorrection).",
            "llmcat corrections promote --merchant-norm TEXT --ai-category CODE --user-category CODE",
            GroupOptions, 0, 0, ctx => ResolveCorrectionAsync(ctx, "promote"), "adminResolveLlmCatCorrection"),
        new("llmcat corrections reject",
            "Reject a correction group (the AI's category stays as is). Works for 'custom' too.",
            "llmcat corrections reject --merchant-norm TEXT --ai-category CODE --user-category CODE|custom",
            GroupOptions, 0, 0, ctx => ResolveCorrectionAsync(ctx, "reject")),
        new("llmcat corrections prompt-issue",
            "Mark a correction group as a prompt issue (a candidate eval case; see export-prompt-issues).",
            "llmcat corrections prompt-issue --merchant-norm TEXT --ai-category CODE --user-category CODE|custom",
            GroupOptions, 0, 0, ctx => ResolveCorrectionAsync(ctx, "prompt_issue")),
        new("llmcat corrections export-prompt-issues",
            "Print the prompt-issue groups as YAML eval candidates. The merchant name is shown only as a comment: replace it with a synthetic look-alike before it enters the eval set.",
            "llmcat corrections export-prompt-issues",
            [], 0, 0, ExportPromptIssuesAsync),
        new("llmcat confirmed list",
            "List AI-confirmed merchants: at least cat.confirm_n distinct installs agree and no correction is open (adminQueryLlmCatConfirmed). Counts only.",
            "llmcat confirmed list [--limit 1-100] [--cursor C]",
            [new("limit"), new("cursor")], 0, 0, ListConfirmedAsync, "adminQueryLlmCatConfirmed"),
        new("llmcat confirmed promote",
            "Promote an AI-confirmed merchant into the DRAFT catalog (merchant + exact alias); publish separately (adminResolveLlmCatConfirmed).",
            "llmcat confirmed promote --merchant-norm TEXT --category CODE",
            ConfirmedOptions, 0, 0, ctx => ResolveConfirmedAsync(ctx, "promote"), "adminResolveLlmCatConfirmed"),
        new("llmcat confirmed reject",
            "Reject an AI-confirmed merchant (it leaves the list; nothing is added to the catalog).",
            "llmcat confirmed reject --merchant-norm TEXT --category CODE",
            ConfirmedOptions, 0, 0, ctx => ResolveConfirmedAsync(ctx, "reject")),
    ];

    private static bool Merchant(string? text) => text is { Length: >= 2 and <= 64 } && text.All(c => !char.IsControl(c));

    private static bool Page(CommandContext ctx, out int? limit, out string? cursor)
    {
        limit = null;
        cursor = ctx.Args.Get("cursor");
        if (ctx.Args.Get("limit") is { } raw)
        {
            if (!Validate.PositiveInt(raw, 100, out var parsed))
            {
                return false;
            }

            limit = parsed;
        }

        return cursor is null || (cursor.Length is >= 1 and <= 9 && cursor.All(char.IsAsciiDigit));
    }

    private static Task<int> ListCorrectionsAsync(CommandContext ctx)
    {
        var status = ctx.Args.Get("status");
        if (!Page(ctx, out var limit, out var cursor) || (status is not null && !Statuses.Contains(status)))
        {
            return Task.FromResult(ctx.Usage("--status must be open, promoted, rejected or prompt_issue; --limit 1-100; --cursor the next-cursor of the last page."));
        }

        return ctx.CallAsync(HttpMethod.Post, Corrections + "query", (w, _) => WriteQuery(w, status, limit, cursor));
    }

    private static Task<int> ListConfirmedAsync(CommandContext ctx)
    {
        if (!Page(ctx, out var limit, out var cursor))
        {
            return Task.FromResult(ctx.Usage("--limit must be 1-100; --cursor the next-cursor of the last page."));
        }

        return ctx.CallAsync(HttpMethod.Post, Confirmed + "query", (w, _) => WriteQuery(w, null, limit, cursor));
    }

    private static void WriteQuery(Utf8JsonWriter w, string? status, int? limit, string? cursor)
    {
        w.WriteStartObject();
        if (status is not null)
        {
            w.WriteString("status", status);
        }

        if (limit is { } n)
        {
            w.WriteNumber("limit", n);
        }

        if (cursor is not null)
        {
            w.WriteString("cursor", cursor);
        }

        w.WriteEndObject();
    }

    private static Task<int> ResolveCorrectionAsync(CommandContext ctx, string action)
    {
        var norm = ctx.Args.Get("merchant-norm");
        var ai = ctx.Args.Get("ai-category");
        var user = ctx.Args.Get("user-category");
        if (!Merchant(norm) || !Validate.Match(Validate.CategoryCode(), ai) || !Validate.Match(Validate.CategoryCode(), user))
        {
            return Task.FromResult(ctx.Usage("--merchant-norm (2-64 characters), --ai-category and --user-category (a category code, or custom) are required."));
        }

        if (action == "promote" && user == "custom")
        {
            return Task.FromResult(ctx.Usage("A 'custom' user category can't be promoted: use reject or prompt-issue."));
        }

        return ctx.CallAsync(HttpMethod.Post, Corrections + "resolve", (w, _) =>
        {
            w.WriteStartObject();
            w.WriteString("merchantNorm", norm);
            w.WriteString("aiCategory", ai);
            w.WriteString("userCategory", user);
            w.WriteString("action", action);
            w.WriteEndObject();
        });
    }

    private static Task<int> ResolveConfirmedAsync(CommandContext ctx, string action)
    {
        var norm = ctx.Args.Get("merchant-norm");
        var category = ctx.Args.Get("category");
        if (!Merchant(norm) || !Validate.Match(Validate.CategoryCode(), category))
        {
            return Task.FromResult(ctx.Usage("--merchant-norm (2-64 characters) and --category (a category code) are required."));
        }

        return ctx.CallAsync(HttpMethod.Post, Confirmed + "resolve", (w, _) =>
        {
            w.WriteStartObject();
            w.WriteString("merchantNorm", norm);
            w.WriteString("category", category);
            w.WriteString("action", action);
            w.WriteEndObject();
        });
    }

    /// <summary>Pages through the <c>prompt_issue</c> groups and prints them as YAML (JSON-escaped scalars are valid YAML).</summary>
    private static async Task<int> ExportPromptIssuesAsync(CommandContext ctx)
    {
        var yaml = new StringBuilder();
        yaml.Append("# Candidate eval cases from prompt_issue corrections. The merchant name is a comment only:\n");
        yaml.Append("# write a synthetic look-alike into `merchant` before adding a case to the eval set.\n");
        string? cursor = null;
        var count = 0;
        for (var pageNumber = 0; pageNumber < 50; pageNumber++)
        {
            var buffer = new System.Buffers.ArrayBufferWriter<byte>(128);
            using (var writer = new Utf8JsonWriter(buffer))
            {
                WriteQuery(writer, "prompt_issue", 100, cursor);
            }

            ApiResponse response;
            try
            {
                response = await ctx.Api.SendAsync(HttpMethod.Post, Corrections + "query", buffer.WrittenSpan.ToArray(), ctx.CancellationToken).ConfigureAwait(false);
            }
            catch (Auth.LoginException e)
            {
                ctx.Printer.Err("error: sign-in failed: " + e.Message);
                return ExitCode.Auth;
            }
            catch (ApiUnreachableException e)
            {
                ctx.Printer.Err("error: " + e.Message);
                return ExitCode.Unreachable;
            }

            if (!response.IsSuccess)
            {
                return ctx.Report(response);
            }

            foreach (var item in (response.Body?["items"] as JsonArray) ?? [])
            {
                count++;
                yaml.Append(CultureInfo.InvariantCulture, $"- id: prompt-issue-{count}\n");
                yaml.Append("  merchant: \"REPLACE-WITH-SYNTHETIC-NAME\"\n");
                yaml.Append("  # seen as: ").Append(Quote(item?["merchantNorm"]?.GetValue<string>())).Append('\n');
                yaml.Append("  ai_category: ").Append(Quote(item?["aiCategory"]?.GetValue<string>())).Append('\n');
                yaml.Append("  expected_category: ").Append(Quote(item?["userCategory"]?.GetValue<string>())).Append('\n');
                yaml.Append(CultureInfo.InvariantCulture, $"  votes: {item?["votes"]?.GetValue<int>() ?? 0}\n");
                yaml.Append("  first_seen: ").Append(Quote(item?["firstSeen"]?.GetValue<string>())).Append('\n');
                yaml.Append("  last_seen: ").Append(Quote(item?["lastSeen"]?.GetValue<string>())).Append('\n');
            }

            cursor = response.Body?["nextCursor"]?.GetValue<string>();
            if (cursor is null)
            {
                break;
            }
        }

        if (count == 0)
        {
            yaml.Append("[]\n");
        }

        ctx.Printer.Out(yaml.ToString().TrimEnd('\n'));
        return ExitCode.Success;
    }

    private static string Quote(string? text) => JsonSerializer.Serialize(text ?? string.Empty, Scalar);
}
