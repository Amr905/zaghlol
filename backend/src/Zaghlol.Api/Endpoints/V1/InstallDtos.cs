using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// <c>InstallRequest</c> (backend-api §4.1). The only data the backend accepts at registration (BR-SYNC-03): the install ID,
/// the platform and the app version. Closed: any other member is <c>400 UNKNOWN_FIELD</c>.
/// </summary>
public sealed class InstallRequest
{
    public required InstallId InstallId { get; init; }

    public required string Platform { get; init; }

    public required string AppVersion { get; init; }
}

/// <summary><c>InstallResponse</c>: the install token appears only here, never stored, logged or traced.</summary>
public sealed record InstallResponse(Sensitive<string> InstallToken, DateTimeOffset ServerTime);
