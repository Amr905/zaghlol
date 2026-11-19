namespace Zaghlol.Testing;

/// <summary>
/// Adds a valid <c>Zaghlol-App</c> header (required on every <c>/v1</c> app operation, BUG-004) to a test client's requests that
/// carry none. A test that needs the header absent sets <see cref="Omit"/> on the request.
/// </summary>
public sealed class AppHeaderHandler : DelegatingHandler
{
    public const string HeaderName = "Zaghlol-App";

    public const string ValidValue = "android/1.0.0 (1)";

    public static readonly HttpRequestOptionsKey<bool> Omit = new("zaghlol.test.omit-app-header");

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (!request.Options.TryGetValue(Omit, out var omit) || !omit)
        {
            if (!request.Headers.Contains(HeaderName))
            {
                request.Headers.TryAddWithoutValidation(HeaderName, ValidValue);
            }
        }

        return base.SendAsync(request, cancellationToken);
    }
}
