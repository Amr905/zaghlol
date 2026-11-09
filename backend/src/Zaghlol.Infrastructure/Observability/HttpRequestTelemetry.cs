namespace Zaghlol.Infrastructure.Observability;

/// <summary>
/// Outbound calls carry secrets in the URL path (Play <c>…/tokens/{token}</c>, App Store <c>…/transactions/{id}</c>), so each
/// request names its own URL template for spans; there is no guessing from the real URL. A request without one is
/// <c>unknown</c>.
/// </summary>
public static class HttpRequestTelemetry
{
    public const string UnknownTemplate = "unknown";

    private static readonly HttpRequestOptionsKey<string> TemplateKey = new("zaghlol.url_template");

    /// <summary>E.g. <c>/androidpublisher/v3/applications/{packageName}/purchases/subscriptionsv2/tokens/{token}</c>.</summary>
    public static HttpRequestMessage SetUrlTemplate(this HttpRequestMessage request, string template)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentException.ThrowIfNullOrWhiteSpace(template);
        request.Options.Set(TemplateKey, template);
        return request;
    }

    internal static string UrlTemplateOf(HttpRequestMessage request) =>
        request.Options.TryGetValue(TemplateKey, out var template) && !string.IsNullOrWhiteSpace(template)
            ? template
            : UnknownTemplate;
}
