using Google.Apis.Auth.OAuth2;
using Zaghlol.Application.Llm;

namespace Zaghlol.Infrastructure.Llm;

/// <summary>
/// Google.Apis.Auth mints (and caches) the access token from the service-account JSON (T-338). Only the service-account type is
/// accepted (<see cref="CredentialFactory"/>), so a secret can't make the library run a program. The credential is built on the
/// first call; a key rotation is a restart (T-333). Accepted residual, as for Play: the private key lives in this process.
/// </summary>
public sealed class GoogleVertexAccessTokenSource : IVertexAccessTokenSource, IDisposable
{
    public const string Scope = "https://www.googleapis.com/auth/cloud-platform";

    private readonly SemaphoreSlim gate = new(1, 1);
    private ITokenAccess? credential;

    public async ValueTask<LlmSensitive<string>> GetTokenAsync(LlmSensitive<string> serviceAccountJson, CancellationToken cancellationToken)
    {
        var access = credential ?? await CreateAsync(serviceAccountJson, cancellationToken);
        return new LlmSensitive<string>(await access.GetAccessTokenForRequestAsync(cancellationToken: cancellationToken));
    }

    public void Dispose() => gate.Dispose();

    private async Task<ITokenAccess> CreateAsync(LlmSensitive<string> json, CancellationToken cancellationToken)
    {
        await gate.WaitAsync(cancellationToken);
        try
        {
            return credential ??= CredentialFactory.FromJson<ServiceAccountCredential>(json.Reveal()).ToGoogleCredential().CreateScoped(Scope);
        }
        finally
        {
            gate.Release();
        }
    }
}
