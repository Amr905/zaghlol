using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Zaghlol.Application.Llm;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.Llm;

/// <summary>
/// Anthropic Messages API over a plain <see cref="HttpClient"/> (T-338). The plan schema has more <c>anyOf</c> parameters than strict
/// structured output allows (16 per request), so the schema is the <c>input_schema</c> of one forced tool, without
/// <c>strict</c>: the reply is the tool's <c>input</c>, and the server-side plan validation is the gate (ask-llm.md §3).
/// The body has <c>max_tokens</c>, the static system prompt, the question as the only message and the tool; no <c>metadata</c>, no
/// thinking, no identifier. Headers: <c>x-api-key</c> (the key, never in a URL) and the API version.
/// </summary>
public sealed class AnthropicMessagesProvider(
    HttpClient http,
    LlmProviderOptions options,
    ILlmApiKeyProvider keys,
    ILlmPromptCatalog prompts,
    LlmCallGuard guard) : ILlmProvider
{
    public const string Path = "v1/messages";
    public const string ApiVersion = "2023-06-01";
    public const string ToolName = "reply_json";
    public const int MaxResponseBytes = 256 * 1024;

    public string Id => options.Id;

    public Task<LlmResult> CompleteAsync(LlmCall request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (!keys.HasKey(options.Id))
        {
            throw new LlmServicePausedException();
        }

        return guard.RunAsync(ct => SendOnceAsync(request, ct), cancellationToken);
    }

    internal JsonObject BuildBody(LlmCall call) => new()
    {
        ["model"] = options.Model,
        ["max_tokens"] = call.MaxOutputTokens,
        ["system"] = prompts.GetSystemPrompt(call.PromptId),
        ["messages"] = new JsonArray(new JsonObject { ["role"] = "user", ["content"] = call.UserText.Reveal() }),
        ["tools"] = new JsonArray(new JsonObject
        {
            ["name"] = ToolName,
            ["description"] = "Return the answer as this JSON object.",
            ["input_schema"] = LlmSchemaTransforms.ForProvider(call.OutputSchema),
        }),
        ["tool_choice"] = new JsonObject { ["type"] = "tool", ["name"] = ToolName },
    };

    private async Task<LlmResult> SendOnceAsync(LlmCall call, CancellationToken ct)
    {
        var key = await keys.GetKeyAsync(options.Id, ct);
        using var request = new HttpRequestMessage(HttpMethod.Post, Path)
        {
            Content = new StringContent(BuildBody(call).ToJsonString(), Encoding.UTF8, "application/json"),
        };
        request.Headers.Add("x-api-key", key.Reveal());
        request.Headers.Add("anthropic-version", ApiVersion);

        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
        if (!response.IsSuccessStatusCode)
        {
            return LlmResult.Failed(LlmOutcome.Upstream);
        }

        var bytes = await LlmReplyReader.ReadCappedAsync(response, MaxResponseBytes, ct);
        return bytes is null ? LlmResult.Failed(LlmOutcome.Invalid) : Parse(bytes);
    }

    /// <summary>Maps a Messages reply; anything unexpected is <see cref="LlmOutcome.Invalid"/>.</summary>
    internal static LlmResult Parse(byte[] body)
    {
        JsonDocument doc;
        try
        {
            // The whole envelope is parsed without duplicates, which covers the tool input too.
            doc = JsonDocument.Parse(body, LlmReplyReader.NoDuplicates);
        }
        catch (JsonException)
        {
            return LlmResult.Failed(LlmOutcome.Invalid);
        }

        using (doc)
        {
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return LlmResult.Failed(LlmOutcome.Invalid);
            }

            var usage = ReadUsage(root);
            switch (LlmReplyReader.Str(root, "stop_reason"))
            {
                case "refusal":
                    return LlmResult.Failed(LlmOutcome.Refused, usage);
                case "tool_use":
                    break;
                default:
                    // max_tokens (cut off), end_turn (answered in prose), pause_turn, context window, missing or unknown.
                    return LlmResult.Failed(LlmOutcome.Invalid, usage);
            }

            if (root.TryGetProperty("content", out var content) && content.ValueKind == JsonValueKind.Array)
            {
                foreach (var block in content.EnumerateArray())
                {
                    if (LlmReplyReader.Str(block, "type") == "tool_use" && LlmReplyReader.Str(block, "name") == ToolName
                        && block.TryGetProperty("input", out var input) && input.ValueKind == JsonValueKind.Object)
                    {
                        return new LlmResult(LlmOutcome.Ok, new LlmSensitive<byte[]>(Encoding.UTF8.GetBytes(input.GetRawText())), usage);
                    }
                }
            }

            return LlmResult.Failed(LlmOutcome.Invalid, usage);
        }
    }

    /// <summary>Anthropic's <c>input_tokens</c> excludes cache reads and writes; <see cref="LlmUsage"/> input includes cached tokens.</summary>
    private static LlmUsage ReadUsage(JsonElement root)
    {
        if (!root.TryGetProperty("usage", out var usage) || usage.ValueKind != JsonValueKind.Object)
        {
            return LlmUsage.None;
        }

        var read = LlmReplyReader.Int(usage, "cache_read_input_tokens");
        var input = LlmReplyReader.Clamp((long)LlmReplyReader.Int(usage, "input_tokens") + read + LlmReplyReader.Int(usage, "cache_creation_input_tokens"));
        return new LlmUsage(input, read, LlmReplyReader.Int(usage, "output_tokens"));
    }
}
