using System.Globalization;
using Microsoft.Extensions.Configuration;
using Zaghlol.Application.Llm;

namespace Zaghlol.Infrastructure.Llm;

/// <summary>The kinds of provider adapter.</summary>
public enum LlmProviderKind
{
    OpenAiResponses,
    VertexGemini,
    AnthropicMessages,
}

/// <summary>
/// <c>Llm:Providers:&lt;id&gt;:*</c>. Model id, endpoint, region and prices come only from configuration (ask-llm.md §3); the
/// prices are USD per million tokens as <see cref="decimal"/>. The API key is never configuration (<see cref="ILlmApiKeyProvider"/>).
/// </summary>
public sealed record LlmProviderOptions(
    string Id,
    LlmProviderKind Kind,
    string Model,
    Uri? Endpoint,
    string? Region,
    TimeSpan AttemptTimeout,
    decimal PriceInPerMTok,
    decimal PriceCachedPerMTok,
    decimal PriceOutPerMTok,
    string? Project = null)
{
    public const string SectionName = "Llm";
    public const string ActiveKey = "Llm:ActiveProvider";

    /// <summary>Reads every provider under <c>Llm:Providers</c>; anything missing or malformed throws a constant-message <see cref="LlmConfigurationException"/>.</summary>
    public static IReadOnlyList<LlmProviderOptions> ReadAll(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        return [.. configuration.GetSection("Llm:Providers").GetChildren().Select(s => Read(s.Key, s))];
    }

    private static LlmProviderOptions Read(string id, IConfigurationSection section)
    {
        if (!Enum.TryParse<LlmProviderKind>(section["Kind"], ignoreCase: false, out var kind) || !Enum.IsDefined(kind))
        {
            throw new LlmConfigurationException($"Llm:Providers:{id}:Kind is missing or not a known provider kind.");
        }

        var model = section["Model"];
        if (string.IsNullOrWhiteSpace(model))
        {
            throw new LlmConfigurationException($"Llm:Providers:{id}:Model is required.");
        }

        if (!Uri.TryCreate(section["Endpoint"], UriKind.Absolute, out var endpoint) || endpoint.Scheme is not ("https" or "http"))
        {
            throw new LlmConfigurationException($"Llm:Providers:{id}:Endpoint must be an absolute http(s) URL.");
        }

        if (!string.IsNullOrEmpty(endpoint.UserInfo) || !string.IsNullOrEmpty(endpoint.Query))
        {
            throw new LlmConfigurationException($"Llm:Providers:{id}:Endpoint must not carry credentials or a query.");
        }

        var timeoutMs = section["TimeoutMs"] is { Length: > 0 } t
            ? ParseInt(t, id, "TimeoutMs")
            : 8000;
        if (timeoutMs is < 100 or > 8000)
        {
            throw new LlmConfigurationException($"Llm:Providers:{id}:TimeoutMs must be 100..8000.");
        }

        var project = section["Project"];
        if (kind == LlmProviderKind.VertexGemini
            && (!VertexGeminiProvider.PathPart().IsMatch(project ?? string.Empty)
                || !VertexGeminiProvider.PathPart().IsMatch(section["Region"] ?? string.Empty)))
        {
            throw new LlmConfigurationException($"Llm:Providers:{id}:Project and :Region are required for a Vertex provider.");
        }

        if (kind != LlmProviderKind.OpenAiResponses && !VertexGeminiProvider.PathPart().IsMatch(model))
        {
            throw new LlmConfigurationException($"Llm:Providers:{id}:Model has characters a model id cannot have.");
        }

        return new LlmProviderOptions(
            id,
            kind,
            model,
            endpoint,
            section["Region"],
            TimeSpan.FromMilliseconds(timeoutMs),
            Price(section, id, "PriceInPerMTok"),
            Price(section, id, "PriceCachedPerMTok"),
            Price(section, id, "PriceOutPerMTok"),
            project);
    }

    private static int ParseInt(string value, string id, string name) =>
        int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var n)
            ? n
            : throw new LlmConfigurationException($"Llm:Providers:{id}:{name} must be a whole number.");

    private static decimal Price(IConfigurationSection section, string id, string name) =>
        decimal.TryParse(section[name], NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var price) && price >= 0
            ? price
            : throw new LlmConfigurationException($"Llm:Providers:{id}:{name} must be a non-negative decimal.");
}
