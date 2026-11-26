using System.Text.RegularExpressions;
using YamlDotNet.RepresentationModel;

namespace Zaghlol.LlmEval.Tests;

/// <summary>AC3 and AC4: the live workflow is manual only, guarded against forks, reads keys from environment secrets only and uploads numbers only.</summary>
public sealed class LiveWorkflowTests
{
    private static readonly string Path = System.IO.Path.Combine(Support.RepoRoot(), ".github", "workflows", "llm-eval-live.yml");

    private static YamlMappingNode Root()
    {
        var stream = new YamlStream();
        using var reader = new StreamReader(Path);
        stream.Load(reader);
        return (YamlMappingNode)stream.Documents[0].RootNode;
    }

    private static YamlNode Child(YamlMappingNode map, string key) =>
        map.Children.Single(kv => ((YamlScalarNode)kv.Key).Value == key).Value;

    [Fact]
    public void It_runs_on_workflow_dispatch_only()
    {
        // YAML 1.1 loaders may read the key `on` as a boolean; here it is the string "on".
        var on = (YamlMappingNode)Child(Root(), "on");
        Assert.Equal(["workflow_dispatch"], on.Children.Keys.Select(k => ((YamlScalarNode)k).Value!).ToArray());
        var code = string.Join('\n', File.ReadAllLines(Path).Where(l => !l.TrimStart().StartsWith('#')));
        foreach (var trigger in new[] { "push:", "pull_request:", "pull_request_target:", "workflow_run:", "schedule:", "issue_comment:", "workflow_call:", "repository_dispatch:" })
        {
            Assert.DoesNotContain(trigger, code, StringComparison.Ordinal);
        }
    }

    [Fact]
    public void It_cannot_run_in_a_fork_and_uses_the_protected_environment_with_read_only_permissions()
    {
        var root = Root();
        var job = (YamlMappingNode)Child((YamlMappingNode)Child(root, "jobs"), "live");
        Assert.Equal("github.event.repository.fork == false", ((YamlScalarNode)Child(job, "if")).Value);
        Assert.Equal("llm-eval", ((YamlScalarNode)Child(job, "environment")).Value);
        var permissions = (YamlMappingNode)Child(root, "permissions");
        Assert.Single(permissions.Children);
        Assert.Equal("read", ((YamlScalarNode)Child(permissions, "contents")).Value);
    }

    [Fact]
    public void Secrets_appear_only_as_environment_variables_of_the_one_run_step_and_are_never_echoed()
    {
        var text = File.ReadAllText(Path);
        var code = string.Join('\n', text.Split('\n').Where(l => !l.TrimStart().StartsWith('#')));
        var references = Regex.Matches(code, @"secrets\.([A-Za-z0-9_]+)").Select(m => m.Groups[1].Value).ToList();
        Assert.Equal(["LLM_EVAL_KEY_OPENAI", "LLM_EVAL_KEY_VERTEX", "LLM_EVAL_KEY_ANTHROPIC"], references);
        Assert.DoesNotContain("secrets[", code, StringComparison.Ordinal);
        Assert.DoesNotContain("toJSON(secrets", code, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("set -x", code, StringComparison.Ordinal);
        Assert.DoesNotContain("ACTIONS_STEP_DEBUG", code, StringComparison.Ordinal);
        Assert.DoesNotMatch(new Regex(@"echo[^\n]*\$\{?LLM_EVAL_KEY"), code);
        Assert.DoesNotMatch(new Regex(@"(env|printenv)\s*(\||$)", RegexOptions.Multiline), code);
        Assert.Contains("::add-mask::", code, StringComparison.Ordinal);

        // Every reference is `env: NAME: ${{ secrets.NAME }}`: same name, so the value goes nowhere else.
        Assert.Equal(3, Regex.Count(code, @"(LLM_EVAL_KEY_[A-Z]+): \$\{\{ secrets\.\1 \}\}"));

        // The build step has no secrets in its environment: the harness is compiled before any key is exposed.
        var build = code.Split("- name: Build the harness", 2)[1].Split("- name: Run the live evaluation", 2)[0];
        Assert.DoesNotContain("secrets.", build, StringComparison.Ordinal);
    }

    [Fact]
    public void The_artifact_is_the_two_report_files_and_a_leak_check_runs_before_it()
    {
        var code = File.ReadAllText(Path);
        var upload = code.Split("- name: Upload the results table", 2)[1];
        Assert.Contains("llm-eval-results/report.md", upload, StringComparison.Ordinal);
        Assert.Contains("llm-eval-results/report.json", upload, StringComparison.Ordinal);
        Assert.DoesNotContain("recordings", upload, StringComparison.Ordinal);
        Assert.Contains("grep -rqF", code, StringComparison.Ordinal);
        Assert.Contains("nothing is uploaded", code, StringComparison.Ordinal);
    }

    [Fact]
    public void No_secret_is_committed_in_the_workflow_or_the_harness_sources()
    {
        var root = System.IO.Path.Combine(Support.RepoRoot(), "backend", "tests");
        var files = new[] { Path }.Concat(Directory.EnumerateFiles(System.IO.Path.Combine(root, "Zaghlol.LlmEval"), "*.*", SearchOption.AllDirectories)
            .Where(f => !f.Contains("/obj/", StringComparison.Ordinal) && !f.Contains("/bin/", StringComparison.Ordinal)));
        var pattern = new Regex(@"(sk-[A-Za-z0-9_-]{16,}|AIza[0-9A-Za-z_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY|""private_key""\s*:\s*""-----|ghp_[A-Za-z0-9]{20,})");
        Assert.All(files, f => Assert.DoesNotMatch(pattern, File.ReadAllText(f)));
    }
}
