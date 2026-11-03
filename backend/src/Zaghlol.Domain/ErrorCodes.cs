namespace Zaghlol.Domain;

/// <summary>
/// Stable, client-visible error codes (UPPER_SNAKE). Values are part of the public API contract
/// (docs/03-technical/backend-api.md section 6) and must never change once released.
/// </summary>
public static class ErrorCodes
{
    public const string ValidationFailed = "VALIDATION_FAILED";
    public const string UnknownField = "UNKNOWN_FIELD";
    public const string Unauthorized = "UNAUTHORIZED";
    public const string Forbidden = "FORBIDDEN";
    public const string NotFound = "NOT_FOUND";
    public const string MethodNotAllowed = "METHOD_NOT_ALLOWED";
    public const string PayloadTooLarge = "PAYLOAD_TOO_LARGE";
    public const string UnsupportedMediaType = "UNSUPPORTED_MEDIA_TYPE";
    public const string RateLimited = "RATE_LIMITED";
    public const string UpstreamUnavailable = "UPSTREAM_UNAVAILABLE";
    public const string Internal = "INTERNAL";
}
