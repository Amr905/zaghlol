using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;
using Zaghlol.Infrastructure.Operators;

namespace Zaghlol.Api.Auth;

internal static class OperatorAuthServiceCollectionExtensions
{
    /// <summary>The longest wait for the IdP's discovery document or JWKS.</summary>
    public static readonly TimeSpan IdpTimeout = TimeSpan.FromSeconds(10);

    /// <summary>The largest discovery document or JWKS accepted.</summary>
    public const int MaxIdpDocumentBytes = 64 * 1024;

    /// <summary>
    /// Operator OIDC (T-136): <c>OperatorAuth:*</c>, the operator directory (Admin login), the JWKS cache, the startup check,
    /// and the validator. When <c>OperatorAuth:Enabled</c> is set and the settings are valid,
    /// <see cref="OidcOperatorTokenValidator"/> replaces the reject-all default of <c>AddOperatorAuthentication</c>; otherwise
    /// every operator call stays refused (and outside Development and Testing the startup check stops the host). The choice is
    /// made when the validator is first resolved, from the bound options. Call after <c>AddZaghlolHttp</c> and after
    /// <c>AddZaghlolDatabase</c> with <c>DatabaseRole.Admin</c>. There is no bypass validator: tests and local runs use the
    /// same validator against a fake issuer.
    /// </summary>
    public static IServiceCollection AddZaghlolOperatorAuth(this IServiceCollection services)
    {
        services.AddOptions<OperatorAuthOptions>().BindConfiguration(OperatorAuthOptions.Section);
        services.AddZaghlolOperators();
        services.TryAddSingleton(TimeProvider.System);
        services.AddHttpClient(OidcKeyCache.HttpClientName, client =>
        {
            client.Timeout = IdpTimeout;
            client.MaxResponseContentBufferSize = MaxIdpDocumentBytes;
        });
        services.TryAddSingleton<OidcKeyCache>();
        services.Replace(ServiceDescriptor.Singleton<IOperatorTokenValidator>(provider =>
        {
            var settings = provider.GetRequiredService<IOptions<OperatorAuthOptions>>().Value;
            return settings.Enabled && settings.Problem() is null
                ? (IOperatorTokenValidator)ActivatorUtilities.CreateInstance<OidcOperatorTokenValidator>(provider)
                : new RejectAllOperatorTokenValidator();
        }));
        services.AddHostedService<OperatorAuthStartupCheck>();
        return services;
    }
}
