using System.Globalization;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Plans;
using Zaghlol.Application.Llm.Prompts;
using Zaghlol.Infrastructure.Llm;

namespace Zaghlol.LlmEval;

/// <summary>
/// <c>dotnet run --project tests/Zaghlol.LlmEval -c Release -- live --providers providers.live.json --out results [--only id,id] [--record dir]</c>.
/// Reads keys from <c>LLM_EVAL_KEY_&lt;ID&gt;</c>. Writes <c>report.md</c> and <c>report.json</c> (numbers, ids and reason codes only).
/// Exit 0: every evaluated provider passed. 1: one failed the pass rule. 2: nothing could be evaluated (bad arguments, no key, UNSET model).
/// </summary>
public static class Program
{
    public static async Task<int> Main(string[] args)
    {
        ArgumentNullException.ThrowIfNull(args);
        var options = ParseArgs(args);
        if (options is null || options.GetValueOrDefault("_cmd") != "live")
        {
            await Console.Error.WriteLineAsync("usage: live --providers <file> --out <dir> [--only id,id] [--record <dir>]").ConfigureAwait(false);
            return 2;
        }

        try
        {
            return await RunLiveAsync(options).ConfigureAwait(false);
        }
#pragma warning disable CA1031 // Only the exception type is printed: a message could quote a key, a URL or a question.
        catch (Exception ex)
#pragma warning restore CA1031
        {
            await Console.Error.WriteLineAsync("llm-eval failed: " + ex.GetType().Name).ConfigureAwait(false);
            return 2;
        }
    }

    /// <summary>The schema as an adapter sends it: compact, without the <c>$schema</c>, <c>$id</c> and <c>$comment</c> members (the contract file's own comment is about 3 KB).</summary>
    public static string ProviderSchemaText()
    {
        var node = (System.Text.Json.Nodes.JsonObject)System.Text.Json.Nodes.JsonNode.Parse(AskPlanContract.Schema.GetRawText())!;
        node.Remove("$schema");
        node.Remove("$id");
        node.Remove("$comment");
        return node.ToJsonString();
    }

    public static string PromptSizeNote()
    {
        var prompt = new EmbeddedLlmPromptCatalog().GetSystemPrompt(LlmPromptIds.AskPlanV1);
        var promptBytes = System.Text.Encoding.UTF8.GetByteCount(prompt);
        var schemaBytes = System.Text.Encoding.UTF8.GetByteCount(ProviderSchemaText());
        return string.Create(CultureInfo.InvariantCulture,
            $"Static input: prompt {promptBytes} bytes + schema {schemaBytes} bytes (one token per byte is the upper bound; the spend guard prices {Zaghlol.Application.Llm.Spend.SpendGuardOptions.PromptAndSchemaTokens} for both, and {PassRule.InputTokenBound} input tokens per call).");
    }

    private static async Task<int> RunLiveAsync(Dictionary<string, string> options)
    {
        var all = LiveProviders.ReadOptions(await File.ReadAllTextAsync(options["--providers"]).ConfigureAwait(false));
        var only = options.TryGetValue("--only", out var o) ? o.Split(',', StringSplitOptions.RemoveEmptyEntries) : null;
        var chosen = all.Where(p => only is null || only.Contains(p.Id, StringComparer.Ordinal)).ToList();
        var keys = new EnvLlmApiKeys(chosen.Select(p => p.Id), Environment.GetEnvironmentVariable);
        var set = EvalSet.Load(Path.Combine(AppContext.BaseDirectory, "data", "questions-v1.yaml"));
        var runner = new EvalRunner(new PlanValidator());
        var reports = new List<ProviderReport>();
        var recorders = new Dictionary<string, RecordingProvider>(StringComparer.Ordinal);

        foreach (var provider in chosen)
        {
            if (!keys.HasKey(provider.Id))
            {
                await Console.Error.WriteLineAsync($"skipped {provider.Id}: no key in {EnvLlmApiKeys.EnvName(provider.Id)}").ConfigureAwait(false);
                continue;
            }

            var live = LiveProviders.Build(provider, keys, options.ContainsKey("--record") ? a => recorders[provider.Id] = new RecordingProvider(a) : null);
            var items = await runner.RunAsync(set, live.Adapter, live.Prices, CancellationToken.None).ConfigureAwait(false);
            reports.Add(new ProviderReport(provider.Id, "live", provider.Model, items, live.Shapes.Shapes));
        }

        if (reports.Count == 0)
        {
            await Console.Error.WriteLineAsync("no provider could be evaluated").ConfigureAwait(false);
            return 2;
        }

        var markdown = EvalReportWriter.Markdown(reports, LlmPromptIds.AskPlanV1, PromptSizeNote());
        Directory.CreateDirectory(options["--out"]);
        await File.WriteAllTextAsync(Path.Combine(options["--out"], "report.md"), markdown).ConfigureAwait(false);
        await File.WriteAllTextAsync(Path.Combine(options["--out"], "report.json"), EvalReportWriter.Json(reports)).ConfigureAwait(false);
        if (options.TryGetValue("--record", out var dir))
        {
            Directory.CreateDirectory(dir);
            foreach (var (id, recorder) in recorders)
            {
                await File.WriteAllTextAsync(Path.Combine(dir, id + ".json"), recorder.ToJson()).ConfigureAwait(false);
            }
        }

        Console.WriteLine(markdown.Split("\n## ", 2)[0]);
        return reports.All(r => r.Passed) ? 0 : 1;
    }

    private static Dictionary<string, string>? ParseArgs(string[] args)
    {
        if (args.Length == 0)
        {
            return null;
        }

        var map = new Dictionary<string, string>(StringComparer.Ordinal) { ["_cmd"] = args[0] };
        for (var i = 1; i + 1 < args.Length; i += 2)
        {
            map[args[i]] = args[i + 1];
        }

        return map.ContainsKey("--providers") && map.ContainsKey("--out") ? map : null;
    }
}
