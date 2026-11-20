using Microsoft.AspNetCore.Mvc.Testing;

namespace Zaghlol.Api.Tests;

/// <summary>
/// T-201 review I-9: "the API must refuse to start" through <see cref="WebApplicationFactory{TEntryPoint}"/>. With minimal
/// hosting, a refusal in a hosted service makes <c>Program</c>'s <c>RunAsync</c> dispose the host while the factory's
/// <c>DeferredHost.StartAsync</c> still asks it for <c>IHostApplicationLifetime</c>; that race surfaces as
/// <see cref="ObjectDisposedException"/> ("IServiceProvider") and hides the real refusal. This helper starts a fresh factory
/// and retries at most <see cref="MaxAttempts"/> times, and only for that exact race; anything else (the expected refusal,
/// or a wrong one) is returned at once for the caller to assert. A host that starts fails the test.
/// </summary>
internal static class ApiStartRefusal
{
    public const int MaxAttempts = 3;

    /// <summary>Starts the API (by default through <c>Services</c>) and returns the exception that stopped it.</summary>
    public static Exception Expect(Func<WebApplicationFactory<Program>> create, Action<WebApplicationFactory<Program>>? start = null)
    {
        ArgumentNullException.ThrowIfNull(create);
        start ??= static factory => _ = factory.Services;
        Exception? last = null;
        for (var attempt = 1; attempt <= MaxAttempts; attempt++)
        {
            using var factory = create();
            last = Assert.ThrowsAny<Exception>(() => start(factory));
            if (!IsDeferredHostDisposalRace(last))
            {
                return last;
            }
        }

        return last!;
    }

    /// <summary>The <c>DeferredHost</c> disposal race and nothing else: an <c>ObjectDisposedException</c> for the service provider thrown inside <c>DeferredHost</c>.</summary>
    internal static bool IsDeferredHostDisposalRace(Exception error) =>
        HostStartupTests.Chain(error).Any(e =>
            e is ObjectDisposedException disposed
            && string.Equals(disposed.ObjectName, "IServiceProvider", StringComparison.Ordinal)
            && (disposed.StackTrace?.Contains("DeferredHost", StringComparison.Ordinal) ?? false))
        && !HostStartupTests.Chain(error).Any(e => e is Zaghlol.Infrastructure.Kms.KmsConfigurationException);
}
