using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Zaghlol.Application.Llm;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.Llm;

/// <summary>Mints the OAuth access token for a Vertex call from the service-account JSON (T-338); the JSON never leaves this boundary.</summary>
public interface IVertexAccessTokenSource
{
    ValueTask<LlmSensitive<string>> GetTokenAsync(LlmSensitive<string> serviceAccountJson, CancellationToken cancellationToken);
}

/// <summary>
/// Vertex AI Gemini <c>generateContent</c> over a plain <see cref="HttpClient"/> on a regional (EU) endpoint (ask-llm.md §3). The body
/// has <c>systemInstruction</c> (static, first), the question as the only content, <c>responseMimeType:application/json</c>,
/// <c>responseJsonSchema</c>, <c>maxOutputTokens</c> and minimal thinking; no <c>cachedContent</c>, no tools or grounding, no labels.
/// The only header beyond the standard ones is the bearer access token; the service-account JSON and the token are never in a URL,
/// log or exception.
/// </summary>
public sealed partial class VertexGeminiProvider(
    HttpClient http,
    LlmProviderOptions options,
    ILlmApiKeyProvider keys,
    IVertexAccessTokenSource tokens,
    ILlmPromptCatalog prompts,
    LlmCallGuard guard) : ILlmProvider
{
    public const int MaxResponseBytes = 256 * 1024;

    /// <summary>Gemini 3 thinking control; the lowest level (a plan needs no reasoning).</summary>
    public const string ThinkingLevel = "MINIMAL";

    public string Id => options.Id;

    /// <summary>Project, region and model go into the path, so they are checked (configuration, but never trusted into a URL).</summary>
    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\\z", RegexOptions.CultureInvariant)]
    internal static partial Regex PathPart();

    public Task<LlmResult> CompleteAsync(LlmCall request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (!keys.HasKey(options.Id))
        {
            throw new LlmServicePausedException();
        }

        return guard.RunAsync(ct => SendOnceAsync(request, ct), cancellationToken);
    }

    internal string RequestPath =>
        $"v1/projects/{options.Project}/locations/{options.Region}/publishers/google/models/{options.Model}:generateContent";

    internal JsonObject BuildBody(LlmCall call) => new()
    {
        ["systemInstruction"] = new JsonObject { ["parts"] = new JsonArray(new JsonObject { ["text"] = prompts.GetSystemPrompt(call.PromptId) }) },
        ["contents"] = new JsonArray(new JsonObject
        {
            ["role"] = "user",
            ["parts"] = new JsonArray(new JsonObject { ["text"] = call.UserText.Reveal() }),
        }),
        ["generationConfig"] = new JsonObject
        {
            ["responseMimeType"] = "application/json",
            ["responseJsonSchema"] = LlmSchemaTransforms.ForProvider(call.OutputSchema),
            ["maxOutputTokens"] = call.MaxOutputTokens,
            ["thinkingConfig"] = new JsonObject { ["thinkingLevel"] = ThinkingLevel },
        },
    };

    private async Task<LlmResult> SendOnceAsync(LlmCall call, CancellationToken ct)
    {
        var key = await keys.GetKeyAsync(options.Id, ct);
        LlmSensitive<string> token;
        try
        {
            token = await tokens.GetTokenAsync(key, ct);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
#pragma warning disable CA1031 // The credential library's message can carry key details; any failure is an upstream (auth) failure.
        catch (Exception)
#pragma warning restore CA1031
        {
            return LlmResult.Failed(LlmOutcome.Upstream);
        }

        using var request = new HttpRequestMessage(HttpMethod.Post, RequestPath)
        {
            Content = new StringContent(BuildBody(call).ToJsonString(), Encoding.UTF8, "application/json"),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Reveal());

        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
        if (!response.IsSuccessStatusCode)
        {
            return LlmResult.Failed(LlmOutcome.Upstream);
        }

        var bytes = await LlmReplyReader.ReadCappedAsync(response, MaxResponseBytes, ct);
        return bytes is null ? LlmResult.Failed(LlmOutcome.Invalid) : Parse(bytes);
    }

    /// <summary>Maps a <c>generateContent</c> reply; anything unexpected is <see cref="LlmOutcome.Invalid"/>.</summary>
    internal static LlmResult Parse(byte[] body)
    {
        JsonDocument doc;
        try
        {
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
            if (root.TryGetProperty("promptFeedback", out var feedback) && LlmReplyReader.Str(feedback, "blockReason") is not null)
            {
                return LlmResult.Failed(LlmOutcome.Refused, usage);
            }

            if (!root.TryGetProperty("candidates", out var candidates) || candidates.ValueKind != JsonValueKind.Array || candidates.GetArrayLength() == 0)
            {
                return LlmResult.Failed(LlmOutcome.Invalid, usage);
            }

            var candidate = candidates[0];
            switch (LlmReplyReader.Str(candidate, "finishReason"))
            {
                case "STOP":
                    break;
                case "SAFETY" or "PROHIBITED_CONTENT" or "BLOCKLIST" or "SPII" or "IMAGE_SAFETY":
                    return LlmResult.Failed(LlmOutcome.Refused, usage);
                default:
                    // MAX_TOKENS (cut off), RECITATION, LANGUAGE, OTHER, MALFORMED_*, missing or unknown.
                    return LlmResult.Failed(LlmOutcome.Invalid, usage);
            }

            var text = new StringBuilder();
            if (candidate.TryGetProperty("content", out var content) && content.ValueKind == JsonValueKind.Object
                && content.TryGetProperty("parts", out var parts) && parts.ValueKind == JsonValueKind.Array)
            {
                foreach (var part in parts.EnumerateArray())
                {
                    // Thought summaries are not the answer.
                    if (part.ValueKind == JsonValueKind.Object && part.TryGetProperty("thought", out var thought) && thought.ValueKind == JsonValueKind.True)
                    {
                        continue;
                    }

                    text.Append(LlmReplyReader.Str(part, "text"));
                }
            }

            var reply = text.ToString();
            return reply.Length > 0 && LlmReplyReader.IsJsonObject(reply)
                ? new LlmResult(LlmOutcome.Ok, new LlmSensitive<byte[]>(Encoding.UTF8.GetBytes(reply)), usage)
                : LlmResult.Failed(LlmOutcome.Invalid, usage);
        }
    }

    /// <summary>Output = candidates + thinking tokens (both are billed as output).</summary>
    private static LlmUsage ReadUsage(JsonElement root)
    {
        if (!root.TryGetProperty("usageMetadata", out var usage) || usage.ValueKind != JsonValueKind.Object)
        {
            return LlmUsage.None;
        }

        var input = LlmReplyReader.Int(usage, "promptTokenCount");
        var cached = Math.Min(LlmReplyReader.Int(usage, "cachedContentTokenCount"), input);
        var output = LlmReplyReader.Clamp((long)LlmReplyReader.Int(usage, "candidatesTokenCount") + LlmReplyReader.Int(usage, "thoughtsTokenCount"));
        return new LlmUsage(input, cached, output);
    }
}
