using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Zaghlol.Application.Llm;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.Llm;

/// <summary>
/// OpenAI Responses API over a plain <see cref="HttpClient"/> (no vendor SDK; ask-llm.md §3, ADR-027). The request is
/// <c>POST v1/responses</c> with <c>store:false</c>, a strict <c>json_schema</c> text format, <c>reasoning.effort:none</c> and
/// <c>max_output_tokens</c>; the static system prompt comes first and the question last (prefix caching). Nothing identifying the
/// install, the account, the network or the app goes into the body, the headers or the URL: the only header beyond the standard
/// ones is the bearer key. The question and the reply are <see cref="LlmSensitive{T}"/>; an exception or log never carries a body.
/// </summary>
public sealed class OpenAiResponsesProvider(
    HttpClient http,
    LlmProviderOptions options,
    ILlmApiKeyProvider keys,
    ILlmPromptCatalog prompts,
    LlmCallGuard guard) : ILlmProvider
{
    public const string Path = "v1/responses";

    /// <summary>The largest provider reply read (a plan is a few hundred bytes; the envelope adds metadata).</summary>
    public const int MaxResponseBytes = 256 * 1024;

    public string Id => options.Id;

    public Task<LlmResult> CompleteAsync(LlmCall request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        return guard.RunAsync(ct => SendOnceAsync(request, ct), cancellationToken);
    }

    internal JsonObject BuildBody(LlmCall call) => new()
    {
        ["model"] = options.Model,
        ["input"] = new JsonArray(
            new JsonObject { ["role"] = "system", ["content"] = prompts.GetSystemPrompt(call.PromptId) },
            new JsonObject { ["role"] = "user", ["content"] = call.UserText.Reveal() }),
        ["store"] = false,
        ["text"] = new JsonObject
        {
            ["format"] = new JsonObject
            {
                ["type"] = "json_schema",
                ["name"] = SchemaName(call.PromptId),
                ["strict"] = true,
                ["schema"] = JsonNode.Parse(call.OutputSchema.GetRawText()),
            },
        },
        ["reasoning"] = new JsonObject { ["effort"] = "none" },
        ["max_output_tokens"] = call.MaxOutputTokens,
    };

    private async Task<LlmResult> SendOnceAsync(LlmCall call, CancellationToken ct)
    {
        var key = await keys.GetKeyAsync(options.Id, ct);
        using var request = new HttpRequestMessage(HttpMethod.Post, Path)
        {
            Content = new StringContent(BuildBody(call).ToJsonString(), Encoding.UTF8, "application/json"),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key.Reveal());

        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
        if (!response.IsSuccessStatusCode)
        {
            return LlmResult.Failed(LlmOutcome.Upstream);
        }

        var bytes = await ReadCappedAsync(response, ct);
        return bytes is null ? LlmResult.Failed(LlmOutcome.Invalid) : Parse(bytes);
    }

    private static async Task<byte[]?> ReadCappedAsync(HttpResponseMessage response, CancellationToken ct)
    {
        if (response.Content.Headers.ContentLength is > MaxResponseBytes)
        {
            return null;
        }

        await using var stream = await response.Content.ReadAsStreamAsync(ct);
        using var buffer = new MemoryStream();
        var chunk = new byte[8192];
        int read;
        while ((read = await stream.ReadAsync(chunk, ct)) > 0)
        {
            if (buffer.Length + read > MaxResponseBytes)
            {
                return null;
            }

            buffer.Write(chunk, 0, read);
        }

        return buffer.ToArray();
    }

    /// <summary>Maps a Responses API reply to an <see cref="LlmResult"/>; anything unexpected is <see cref="LlmOutcome.Invalid"/>.</summary>
    private static readonly JsonDocumentOptions NoDuplicates = new() { AllowDuplicateProperties = false };

    internal static LlmResult Parse(byte[] body)
    {
        JsonDocument doc;
        try
        {
            doc = JsonDocument.Parse(body);
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
            var status = Str(root, "status");
            if (status == "failed")
            {
                return LlmResult.Failed(LlmOutcome.Upstream, usage);
            }

            if (status is not (null or "completed"))
            {
                // incomplete (cut off at max_output_tokens or filtered) or any state we don't know.
                return LlmResult.Failed(LlmOutcome.Invalid, usage);
            }

            string? text = null;
            if (root.TryGetProperty("output", out var output) && output.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in output.EnumerateArray())
                {
                    if (Str(item, "type") != "message" || !item.TryGetProperty("content", out var content) || content.ValueKind != JsonValueKind.Array)
                    {
                        continue;
                    }

                    foreach (var part in content.EnumerateArray())
                    {
                        switch (Str(part, "type"))
                        {
                            case "refusal":
                                return LlmResult.Failed(LlmOutcome.Refused, usage);
                            case "output_text" when text is null:
                                text = Str(part, "text");
                                break;
                        }
                    }
                }
            }

            if (text is null)
            {
                return LlmResult.Failed(LlmOutcome.Invalid, usage);
            }

            try
            {
                using var reply = JsonDocument.Parse(text, NoDuplicates);
                if (reply.RootElement.ValueKind != JsonValueKind.Object)
                {
                    return LlmResult.Failed(LlmOutcome.Invalid, usage);
                }
            }
            catch (JsonException)
            {
                return LlmResult.Failed(LlmOutcome.Invalid, usage);
            }

            return new LlmResult(LlmOutcome.Ok, new LlmSensitive<byte[]>(Encoding.UTF8.GetBytes(text)), usage);
        }
    }

    private static LlmUsage ReadUsage(JsonElement root)
    {
        if (!root.TryGetProperty("usage", out var usage) || usage.ValueKind != JsonValueKind.Object)
        {
            return LlmUsage.None;
        }

        var cached = usage.TryGetProperty("input_tokens_details", out var details) ? Int(details, "cached_tokens") : 0;
        return new LlmUsage(Int(usage, "input_tokens"), cached, Int(usage, "output_tokens"));
    }

    private static int Int(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var n) && n >= 0
            ? n
            : 0;

    private static string? Str(JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    /// <summary>OpenAI schema names allow letters, digits, underscore and dash (max 64).</summary>
    private static string SchemaName(string promptId)
    {
        var name = new string([.. promptId.Select(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-' ? c : '_')]);
        return name.Length is > 0 and <= 64 ? name : "plan";
    }
}
