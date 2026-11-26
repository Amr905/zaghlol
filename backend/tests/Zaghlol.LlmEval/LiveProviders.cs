using System.Globalization;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Prompts;
using Zaghlol.Application.Llm.Spend;
using Zaghlol.Infrastructure.Llm;

namespace Zaghlol.LlmEval;

/// <summary>
/// Provider keys for the live run, read once from environment variables <c>LLM_EVAL_KEY_&lt;ID&gt;</c> (the id upper-cased, every character
/// that is not a letter or digit an underscore). The workflow fills them from GitHub environment secrets. Values are held as
/// <see cref="LlmSensitive{T}"/> and are never printed; <see cref="EnvName"/> is the only thing a message may name.
/// </summary>
public sealed class EnvLlmApiKeys : ILlmApiKeyProvider
{
    private readonly Dictionary<string, LlmSensitive<string>> keys = new(StringComparer.Ordinal);

    public EnvLlmApiKeys(IEnumerable<string> providerIds, Func<string, string?> environment)
    {
        foreach (var id in providerIds)
        {
            if (environment(EnvName(id)) is { Length: > 0 } value)
            {
                keys[id] = new LlmSensitive<string>(value);
            }
        }
    }

    public static string EnvName(string providerId) =>
        "LLM_EVAL_KEY_" + new string([.. providerId.ToUpperInvariant().Select(c => char.IsAsciiLetterOrDigit(c) ? c : '_')]);

    public bool HasKey(string providerId) => keys.ContainsKey(providerId);

    public ValueTask<LlmSensitive<string>> GetKeyAsync(string providerId, CancellationToken cancellationToken) =>
        keys.TryGetValue(providerId, out var key) ? ValueTask.FromResult(key) : throw new LlmServicePausedException();
}

/// <summary>
/// FU-430: records the shape of the usage object each provider returns (property names and JSON kinds, never a value), by looking at
/// the response on its way through. The body is read from the buffered copy and is not stored or printed.
/// </summary>
public sealed class UsageShapeHandler(HttpMessageHandler inner) : DelegatingHandler(inner)
{
    private readonly SortedSet<string> shapes = new(StringComparer.Ordinal);

    public IReadOnlyList<string> Shapes
    {
        get
        {
            lock (shapes)
            {
                return [.. shapes];
            }
        }
    }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var response = await base.SendAsync(request, cancellationToken).ConfigureAwait(false);
        try
        {
            if (response.IsSuccessStatusCode)
            {
                await response.Content.LoadIntoBufferAsync(256 * 1024, cancellationToken).ConfigureAwait(false);
                var body = await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);
                Record(body);
            }
        }
#pragma warning disable CA1031 // Shape capture is best effort and must never change the call.
        catch (Exception)
#pragma warning restore CA1031
        {
        }

        return response;
    }

    /// <summary>The shapes of the <c>usage</c> / <c>usageMetadata</c> objects of one reply body (exposed for the tests).</summary>
    public static IReadOnlyList<string> ShapesOf(byte[] body)
    {
        var list = new SortedSet<string>(StringComparer.Ordinal);
        using var doc = JsonDocument.Parse(body);
        if (doc.RootElement.ValueKind == JsonValueKind.Object)
        {
            foreach (var p in doc.RootElement.EnumerateObject().Where(p => p.Name is "usage" or "usageMetadata"))
            {
                Walk(p.Name, p.Value, 0, list);
            }
        }

        return [.. list];
    }

    private void Record(byte[] body)
    {
        var found = ShapesOf(body);
        lock (shapes)
        {
            shapes.UnionWith(found);
        }
    }

    private static void Walk(string path, JsonElement value, int depth, SortedSet<string> into)
    {
        if (value.ValueKind == JsonValueKind.Object && depth < 4)
        {
            foreach (var p in value.EnumerateObject())
            {
                Walk(path + "." + p.Name, p.Value, depth + 1, into);
            }

            return;
        }

        if (value.ValueKind == JsonValueKind.Array)
        {
            into.Add(path + ":array");
            return;
        }

        into.Add(path + ":" + value.ValueKind.ToString().ToLowerInvariant());
    }
}

/// <summary>A configured provider ready for the live run.</summary>
public sealed record LiveProvider(LlmProviderOptions Options, ILlmProvider Adapter, UsageShapeHandler Shapes)
{
    public LlmPrices Prices => new(Options.PriceInPerMTok, Options.PriceCachedPerMTok, Options.PriceOutPerMTok);
}

/// <summary>Builds the real adapters of <c>Llm:Providers:*</c> for the live run (the same classes the API host registers).</summary>
public static class LiveProviders
{
    public const string UnsetModel = "UNSET";

    /// <summary>Reads <c>{ "Providers": { "&lt;id&gt;": { "Kind": ..., "Model": ... } } }</c> into the <c>Llm:Providers:*</c> configuration shape.</summary>
    public static IReadOnlyList<LlmProviderOptions> ReadOptions(string json)
    {
        var values = new Dictionary<string, string?>(StringComparer.Ordinal);
        using var doc = JsonDocument.Parse(json);
        foreach (var provider in doc.RootElement.GetProperty("Providers").EnumerateObject())
        {
            foreach (var field in provider.Value.EnumerateObject().Where(f => f.Value.ValueKind != JsonValueKind.Null))
            {
                values[$"Llm:Providers:{provider.Name}:{field.Name}"] = field.Value.ValueKind == JsonValueKind.String
                    ? field.Value.GetString()
                    : field.Value.GetRawText();
            }
        }

        return LlmProviderOptions.ReadAll(new ConfigurationBuilder().AddInMemoryCollection(values).Build());
    }

    public static LiveProvider Build(LlmProviderOptions options, ILlmApiKeyProvider keys, Func<ILlmProvider, ILlmProvider>? wrap = null)
    {
        ArgumentNullException.ThrowIfNull(options);
        if (string.Equals(options.Model, UnsetModel, StringComparison.Ordinal))
        {
            throw new LlmConfigurationException($"Llm:Providers:{options.Id}:Model is still UNSET in the providers file.");
        }

        var handler = new UsageShapeHandler(new HttpClientHandler());
        var endpoint = options.Endpoint!.AbsoluteUri;
        var http = new HttpClient(handler, disposeHandler: true)
        {
            BaseAddress = new Uri(endpoint.EndsWith('/') ? endpoint : endpoint + "/"),
            MaxResponseContentBufferSize = 256 * 1024,
            Timeout = Timeout.InfiniteTimeSpan,
        };
        var prompts = new EmbeddedLlmPromptCatalog();
        var guard = new LlmCallGuard(options.Id, LlmGuardOptions.Default with { AttemptTimeout = options.AttemptTimeout }, TimeProvider.System, NullLogger.Instance);
        ILlmProvider adapter = options.Kind switch
        {
            LlmProviderKind.OpenAiResponses => new OpenAiResponsesProvider(http, options, keys, prompts, guard),
            LlmProviderKind.VertexGemini => new VertexGeminiProvider(http, options, keys, new GoogleVertexAccessTokenSource(), prompts, guard),
            LlmProviderKind.AnthropicMessages => new AnthropicMessagesProvider(http, options, keys, prompts, guard),
            _ => throw new LlmConfigurationException("Unknown provider kind."),
        };
        return new LiveProvider(options, wrap is null ? adapter : wrap(adapter), handler);
    }
}

/// <summary>Writes each reply it sees in the replay format of <c>FakeLlmProvider</c> (<c>--record</c>, local refresh of the recordings).</summary>
public sealed class RecordingProvider(ILlmProvider inner) : ILlmProvider
{
    private static readonly JsonSerializerOptions WriteOptions = new() { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    private readonly List<object> entries = [];

    public string Id => inner.Id;

    public async Task<LlmResult> CompleteAsync(LlmCall request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        var result = await inner.CompleteAsync(request, cancellationToken).ConfigureAwait(false);
        var json = result.Outcome == LlmOutcome.Ok ? JsonDocument.Parse(result.Json.Reveal()).RootElement.Clone() : (JsonElement?)null;
        entries.Add(new
        {
            contains = request.UserText.Reveal(),
            outcome = result.Outcome.ToString(),
            note = "recorded from a live run of a synthetic question",
            synthetic = true,
            json,
            usage = new { inputTokens = result.Usage.InputTokens, cachedTokens = result.Usage.CachedTokens, outputTokens = result.Usage.OutputTokens },
        });
        return result;
    }

    public string ToJson() => JsonSerializer.Serialize(entries, WriteOptions);
}
