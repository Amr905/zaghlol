using System.Net;
using System.Text;

namespace Zaghlol.Ops.Tests.Support;

/// <summary>A stand-in admin API: records every request (with its body) and answers from a function.</summary>
internal sealed class StubHandler(Func<HttpRequestMessage, string, HttpResponseMessage> respond) : HttpMessageHandler
{
    public List<(HttpMethod Method, string Url, string Body, string Authorization)> Calls { get; } = [];

    public static HttpResponseMessage Json(int status, string body, string mediaType = "application/json") =>
        new((HttpStatusCode)status) { Content = new StringContent(body, Encoding.UTF8, mediaType) };

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var body = request.Content is null ? string.Empty : await request.Content.ReadAsStringAsync(cancellationToken);
        Calls.Add((request.Method, request.RequestUri!.PathAndQuery, body, request.Headers.Authorization?.ToString() ?? string.Empty));
        return respond(request, body);
    }
}
