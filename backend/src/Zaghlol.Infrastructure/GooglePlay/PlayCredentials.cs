using System.Net.Http.Headers;
using Google.Apis.Auth.OAuth2;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.GooglePlay;

/// <summary>An OAuth access token for the <c>androidpublisher</c> scope; <c>null</c> when no credential is configured (Dev/Testing).</summary>
public interface IPlayAccessTokenSource
{
    Task<Sensitive<string>?> GetTokenAsync(CancellationToken cancellationToken);
}

/// <summary>The credential could not produce an access token (alerted as <c>auth_error</c>). Constant message.</summary>
public sealed class PlayAccessTokenException : SafeException
{
    public PlayAccessTokenException()
        : base("No access token for the Google Play Developer API could be obtained.")
    {
    }

    public PlayAccessTokenException(string message)
        : base(message)
    {
    }

    public PlayAccessTokenException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>
/// Google.Apis.Auth, used only to mint and cache access tokens (T-130 design note §7). Application Default Credentials cover
/// workload identity federation and the platform identity (no key in the deployment, preferred); otherwise the service-account
/// JSON from the secrets manager is loaded with <see cref="CredentialFactory"/>, which accepts only the service-account type
/// (an external-account configuration from a secret can't make the library run a program). Accepted residual: for the JSON
/// source the private key lives in this process for its lifetime, because the library needs it to sign token requests.
/// </summary>
internal sealed class GoogleAccessTokenSource(GooglePlayOptions options) : IPlayAccessTokenSource, IDisposable
{
    public const string Scope = "https://www.googleapis.com/auth/androidpublisher";

    private readonly SemaphoreSlim gate = new(1, 1);
    private ITokenAccess? credential;

    public async Task<Sensitive<string>?> GetTokenAsync(CancellationToken cancellationToken)
    {
        if (options.CredentialSource == PlayCredentialSource.None)
        {
            return null;
        }

        try
        {
            var access = credential ?? await CreateAsync(cancellationToken);
            return new Sensitive<string>(await access.GetAccessTokenForRequestAsync(cancellationToken: cancellationToken));
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
#pragma warning disable CA1031 // Any failure of the credential library is an auth failure; its message may carry key details.
        catch (Exception)
#pragma warning restore CA1031
        {
            throw new PlayAccessTokenException();
        }
    }

    public void Dispose() => gate.Dispose();

    private async Task<ITokenAccess> CreateAsync(CancellationToken cancellationToken)
    {
        await gate.WaitAsync(cancellationToken);
        try
        {
            if (credential is not null)
            {
                return credential;
            }

            GoogleCredential google = options.CredentialSource == PlayCredentialSource.ServiceAccountJson
                ? CredentialFactory.FromJson<ServiceAccountCredential>(options.CredentialJson!.Value.Reveal()).ToGoogleCredential()
                : await GoogleCredential.GetApplicationDefaultAsync(cancellationToken);
            credential = google.CreateScoped(Scope);
            return credential;
        }
        finally
        {
            gate.Release();
        }
    }
}

/// <summary>Adds <c>Authorization: Bearer</c> to each attempt (inside the resilience pipeline, so a retry gets a valid token).</summary>
internal sealed class PlayAuthenticationHandler(IPlayAccessTokenSource tokens) : DelegatingHandler
{
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (await tokens.GetTokenAsync(cancellationToken) is { } token)
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Reveal());
        }

        return await base.SendAsync(request, cancellationToken);
    }
}
