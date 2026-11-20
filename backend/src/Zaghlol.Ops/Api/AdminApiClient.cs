using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Zaghlol.Ops.Auth;
using Zaghlol.Ops.Cli;

namespace Zaghlol.Ops.Api;

/// <summary>An answer of the admin API, reduced to what the CLI prints.</summary>
internal sealed record ApiResponse(int Status, JsonNode? Body, string? Code, string? Title, string? Detail, int? RetryAfterSeconds, string? CorrelationId)
{
    public bool IsSuccess => Status is >= 200 and < 300;
}

/// <summary>The API could not be reached or did not answer in time.</summary>
internal sealed class ApiUnreachableException(string message) : Exception(message)
{
}

/// <summary>
/// The admin API over HTTPS with the operator's bearer token. Redirects are not followed (the handler is built that way), so the
/// token only ever goes to the configured origin. Responses are read with a size cap; problem bodies are reduced to
/// <c>code</c> (a fixed character set), <c>title</c>, <c>detail</c> and the correlation id, printable ASCII only.
/// </summary>
internal sealed partial class AdminApiClient(OpsConfig config, HttpClient http, TokenProvider tokens, bool openBrowser)
{
    public const int MaxResponseBytes = 4 * 1024 * 1024;

    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(60);

    /// <summary>Signs in now if there is no valid token, so that a prompt for a secret can come after the browser step.</summary>
    public async Task EnsureTokenAsync(CancellationToken cancellationToken) =>
        _ = await tokens.GetAsync(openBrowser, cancellationToken).ConfigureAwait(false);

    /// <summary>
    /// The base URL's path is kept (FU-264 F6): an API behind <c>https://host/api/</c> is called at <c>https://host/api/admin/v1/...</c>.
    /// <c>new Uri(base, "/admin/...")</c> would replace the path. The base has no query, fragment or credentials (checked at load).
    /// </summary>
    internal static Uri Endpoint(Uri baseUrl, string pathAndQuery)
    {
        var prefix = baseUrl.AbsoluteUri.TrimEnd('/');
        return new Uri(prefix + "/" + pathAndQuery.TrimStart('/'));
    }

    public async Task<ApiResponse> SendAsync(HttpMethod method, string pathAndQuery, byte[]? jsonBody, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(method);
        ArgumentException.ThrowIfNullOrEmpty(pathAndQuery);

        var token = await tokens.GetAsync(openBrowser, cancellationToken).ConfigureAwait(false);
        using var request = new HttpRequestMessage(method, Endpoint(config.ApiUrl, pathAndQuery));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/problem+json"));
        request.Headers.UserAgent.Add(new ProductInfoHeaderValue("zaghlol-ops", typeof(AdminApiClient).Assembly.GetName().Version?.ToString() ?? "0"));
        if (jsonBody is not null)
        {
            request.Content = new ByteArrayContent(jsonBody);
            request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(Timeout);
        HttpResponseMessage response;
        try
        {
            response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token).ConfigureAwait(false);
        }
        catch (HttpRequestException)
        {
            throw new ApiUnreachableException("The API could not be reached.");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new ApiUnreachableException("The API did not answer in time.");
        }

        using (response)
        {
            var status = (int)response.StatusCode;
            if (status == 401)
            {
                await tokens.ForgetAsync(cancellationToken).ConfigureAwait(false);
            }

            var text = await ReadAsync(response, timeout.Token).ConfigureAwait(false);
            JsonNode? body = null;
            if (!string.IsNullOrWhiteSpace(text))
            {
                try
                {
                    body = JsonNode.Parse(text);
                }
                catch (JsonException)
                {
                    body = null;
                }
            }

            var retry = response.Headers.RetryAfter?.Delta is { } delta ? (int?)Math.Clamp((int)delta.TotalSeconds, 0, 86400) : null;
            return status is >= 200 and < 300
                ? new ApiResponse(status, body, null, null, null, retry, null)
                : FromProblem(status, body as JsonObject, retry);
        }
    }

    private static ApiResponse FromProblem(int status, JsonObject? problem, int? retryHeader)
    {
        var code = Text(problem, "code");
        if (code is null || !CodePattern().IsMatch(code))
        {
            code = null;
        }

        var correlation = Text(problem, "correlationId");
        if (correlation is null || !CorrelationPattern().IsMatch(correlation))
        {
            correlation = null;
        }

        int? retry = retryHeader;
        if (problem is not null && problem["retryAfterSeconds"] is JsonValue value && value.TryGetValue<int>(out var seconds))
        {
            retry = Math.Clamp(seconds, 0, 86400);
        }

        return new ApiResponse(status, null, code, Printer.Plain(Text(problem, "title"), 120), Printer.Plain(Text(problem, "detail"), 300), retry, correlation);
    }

    private static string? Text(JsonObject? node, string name) =>
        node is not null && node[name] is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    private static async Task<string> ReadAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        using var buffer = new MemoryStream();
        var chunk = new byte[16 * 1024];
        int read;
        while ((read = await stream.ReadAsync(chunk, cancellationToken).ConfigureAwait(false)) > 0)
        {
            buffer.Write(chunk, 0, read);
            if (buffer.Length > MaxResponseBytes)
            {
                throw new ApiUnreachableException("The API's answer is too large.");
            }
        }

        return System.Text.Encoding.UTF8.GetString(buffer.GetBuffer(), 0, (int)buffer.Length);
    }

    [GeneratedRegex("^[A-Z][A-Z_]{1,39}$", RegexOptions.CultureInvariant, 1000)]
    private static partial Regex CodePattern();

    [GeneratedRegex("^[A-Za-z0-9_-]{1,64}$", RegexOptions.CultureInvariant, 1000)]
    private static partial Regex CorrelationPattern();
}
