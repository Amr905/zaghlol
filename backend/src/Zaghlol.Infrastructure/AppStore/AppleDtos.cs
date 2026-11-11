using System.Text.Json.Serialization;

namespace Zaghlol.Infrastructure.AppStore;

// Apple's JWS payloads and App Store Server API bodies (Apple defines them, so unknown members are ignored). Each DTO declares
// only the fields the server reads (T-131 design note §3 step 2, backend-api §4.5): no [JsonExtensionData], no JsonElement
// catch-all. Dates are Apple's UNIX milliseconds.

/// <summary><c>JWSTransactionDecodedPayload</c>: the read fields only.</summary>
internal sealed class TransactionPayloadDto
{
    public string? BundleId { get; init; }

    public string? Environment { get; init; }

    public string? ProductId { get; init; }

    public string? Type { get; init; }

    public string? TransactionId { get; init; }

    public string? OriginalTransactionId { get; init; }

    public string? AppAccountToken { get; init; }

    public string? InAppOwnershipType { get; init; }

    public string? TransactionReason { get; init; }

    public long? PurchaseDate { get; init; }

    public long? ExpiresDate { get; init; }

    public long? RevocationDate { get; init; }

    public int? RevocationReason { get; init; }

    public long? SignedDate { get; init; }
}

/// <summary><c>JWSRenewalInfoDecodedPayload</c>: the read fields only.</summary>
internal sealed class RenewalPayloadDto
{
    public string? OriginalTransactionId { get; init; }

    public string? Environment { get; init; }

    public int? AutoRenewStatus { get; init; }

    public long? GracePeriodExpiresDate { get; init; }

    public long? SignedDate { get; init; }
}

/// <summary><c>TransactionInfoResponse</c>.</summary>
internal sealed class TransactionInfoResponseDto
{
    public string? SignedTransactionInfo { get; init; }
}

/// <summary><c>StatusResponse</c>: only <c>data[].lastTransactions[]</c>.</summary>
internal sealed class StatusResponseDto
{
    public List<SubscriptionGroupDto>? Data { get; init; }
}

internal sealed class SubscriptionGroupDto
{
    public List<LastTransactionDto>? LastTransactions { get; init; }
}

internal sealed class LastTransactionDto
{
    public int? Status { get; init; }

    public string? OriginalTransactionId { get; init; }

    public string? SignedTransactionInfo { get; init; }

    public string? SignedRenewalInfo { get; init; }
}

/// <summary><c>OrderLookupResponse</c>.</summary>
internal sealed class OrderLookupResponseDto
{
    public int? Status { get; init; }

    public List<string>? SignedTransactions { get; init; }
}

/// <summary>
/// <c>responseBodyV2DecodedPayload</c> (ASSN V2): the read fields only (T-134 design note §1 step 4). Not read, and so never stored or
/// logged: <c>appData</c>, <c>summary</c>, <c>externalPurchaseToken</c>, <c>unclaimInfo</c> and anything Apple adds.
/// </summary>
internal sealed class NotificationPayloadDto
{
    public string? NotificationType { get; init; }

    public string? Subtype { get; init; }

    [JsonPropertyName("notificationUUID")]
    public string? NotificationUuid { get; init; }

    public string? Version { get; init; }

    public long? SignedDate { get; init; }

    public NotificationDataDto? Data { get; init; }
}

/// <summary>The notification's <c>data</c>: the read fields only (no <c>appAppleId</c>, <c>bundleVersion</c>, <c>consumptionRequestReason</c>, ...).</summary>
internal sealed class NotificationDataDto
{
    public string? BundleId { get; init; }

    public string? Environment { get; init; }

    public int? Status { get; init; }

    public string? SignedTransactionInfo { get; init; }

    public string? SignedRenewalInfo { get; init; }
}

/// <summary><c>NotificationHistoryRequest</c>: dates in UNIX milliseconds; only failed deliveries.</summary>
internal sealed class NotificationHistoryRequestDto
{
    public required long StartDate { get; init; }

    public required long EndDate { get; init; }

    public required bool OnlyFailures { get; init; }
}

/// <summary><c>NotificationHistoryResponse</c>: only the payloads and the continuation (no <c>sendAttempts</c>).</summary>
internal sealed class NotificationHistoryResponseDto
{
    public List<NotificationHistoryItemDto>? NotificationHistory { get; init; }

    public bool? HasMore { get; init; }

    public string? PaginationToken { get; init; }
}

internal sealed class NotificationHistoryItemDto
{
    public string? SignedPayload { get; init; }
}

/// <summary>An App Store Server API error body: only the numeric code (the message is never read or logged).</summary>
internal sealed class ErrorPayloadDto
{
    public long? ErrorCode { get; init; }
}

[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    UnmappedMemberHandling = JsonUnmappedMemberHandling.Skip,
    NumberHandling = JsonNumberHandling.Strict,
    AllowDuplicateProperties = false)]
[JsonSerializable(typeof(TransactionPayloadDto))]
[JsonSerializable(typeof(RenewalPayloadDto))]
[JsonSerializable(typeof(TransactionInfoResponseDto))]
[JsonSerializable(typeof(StatusResponseDto))]
[JsonSerializable(typeof(OrderLookupResponseDto))]
[JsonSerializable(typeof(ErrorPayloadDto))]
[JsonSerializable(typeof(NotificationPayloadDto))]
[JsonSerializable(typeof(NotificationHistoryRequestDto))]
[JsonSerializable(typeof(NotificationHistoryResponseDto))]
internal sealed partial class AppleJsonContext : JsonSerializerContext;
