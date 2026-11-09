using Zaghlol.Domain;
using Zaghlol.Infrastructure.Installs;

namespace Zaghlol.Api.Auth;

/// <summary>
/// <c>rotateInstallToken</c> support (backend-api §3): a new token whose hash replaces the current one in one UPDATE. There is
/// no grace window, so a lost rotation response ends in <c>401 INSTALL_TOKEN_INVALID</c> and a silent re-register (§6).
/// Responses carrying it are emitted by T-128+.
/// </summary>
internal interface IInstallTokenRotator
{
    /// <summary>The new token, or <c>null</c> when the request's token was already replaced or the install deleted.</summary>
    Task<Sensitive<string>?> RotateAsync(HttpContext context, CancellationToken cancellationToken);
}

internal sealed class InstallTokenRotator(IInstallStore installs) : IInstallTokenRotator
{
    public async Task<Sensitive<string>?> RotateAsync(HttpContext context, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(context);

        var installId = InstallTokenAuthentication.InstallIdOf(context.User);
        var current = InstallTokenAuthentication.TokenHashOf(context.User);
        var token = InstallTokens.Generate();
        return await installs.RotateTokenAsync(installId, current, InstallTokens.Hash(token), cancellationToken)
            ? new Sensitive<string>(token)
            : null;
    }
}
