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
    public const string InstallTokenInvalid = "INSTALL_TOKEN_INVALID";
    public const string Forbidden = "FORBIDDEN";
    public const string NotFound = "NOT_FOUND";
    public const string CatalogVersionUnknown = "CATALOG_VERSION_UNKNOWN";
    public const string MethodNotAllowed = "METHOD_NOT_ALLOWED";
    public const string InstallExists = "INSTALL_EXISTS";
    public const string IdempotencyKeyReused = "IDEMPOTENCY_KEY_REUSED";
    public const string AdminConflict = "ADMIN_CONFLICT";
    public const string PayloadTooLarge = "PAYLOAD_TOO_LARGE";
    public const string UnsupportedMediaType = "UNSUPPORTED_MEDIA_TYPE";
    public const string RateLimited = "RATE_LIMITED";
    public const string UpstreamUnavailable = "UPSTREAM_UNAVAILABLE";

    /// <summary>502: Google Play or the App Store failed or is unreachable (T-130); the app keeps the purchase pending.</summary>
    public const string StoreUnavailable = "STORE_UNAVAILABLE";
    public const string PurchaseTokenInvalid = "PURCHASE_TOKEN_INVALID";
    public const string PurchaseNotOwned = "PURCHASE_NOT_OWNED";
    public const string PurchaseWrongApp = "PURCHASE_WRONG_APP";

    /// <summary>422 (restore only, T-185): the Play Integrity token or App Attest assertion is missing, invalid, replayed, stale or not bound to this install and body.</summary>
    public const string DeviceAttestationFailed = "DEVICE_ATTESTATION_FAILED";

    /// <summary>409 (restore only, T-185): every move was refused by the 30-day cooldown and nothing else grants Gold.</summary>
    public const string MoveCooldown = "MOVE_COOLDOWN";

    /// <summary>400 (restore, T-185): element 0 of <c>seatKeys</c> isn't this install's registered key.</summary>
    public const string SeatKeyMismatch = "SEAT_KEY_MISMATCH";
    public const string Internal = "INTERNAL";
}
