using Zaghlol.Domain;

namespace Zaghlol.Api.Problems;

internal static class ProblemCodes
{
    /// <summary>Default stable error code for an HTTP status when no domain-specific code was supplied.</summary>
    public static string ForStatus(int status) => status switch
    {
        StatusCodes.Status400BadRequest => ErrorCodes.ValidationFailed,
        StatusCodes.Status401Unauthorized => ErrorCodes.Unauthorized,
        StatusCodes.Status403Forbidden => ErrorCodes.Forbidden,
        StatusCodes.Status404NotFound => ErrorCodes.NotFound,
        StatusCodes.Status405MethodNotAllowed => ErrorCodes.MethodNotAllowed,
        StatusCodes.Status413PayloadTooLarge => ErrorCodes.PayloadTooLarge,
        StatusCodes.Status415UnsupportedMediaType => ErrorCodes.UnsupportedMediaType,
        StatusCodes.Status429TooManyRequests => ErrorCodes.RateLimited,
        StatusCodes.Status502BadGateway or StatusCodes.Status503ServiceUnavailable => ErrorCodes.UpstreamUnavailable,
        >= 500 => ErrorCodes.Internal,
        _ => ErrorCodes.ValidationFailed,
    };
}
