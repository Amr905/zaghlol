using System.Globalization;
using System.Text.Json.Serialization;

namespace Zaghlol.Infrastructure.GooglePlay;

// Play Developer API v3 response bodies (Google defines them, so unknown members are ignored). Each DTO declares only the
// fields the server reads (T-130 design note §1 step 3): no [JsonExtensionData], no JsonElement catch-all, and the deprecated
// subscriptionsv2 latestOrderId is deliberately absent, so it can't be read by mistake (R5-8).

/// <summary><c>SubscriptionPurchaseV2</c> (<c>purchases.subscriptionsv2.get</c>).</summary>
internal sealed class SubscriptionPurchaseV2Dto
{
    public string? SubscriptionState { get; init; }

    public List<SubscriptionLineItemDto>? LineItems { get; init; }

    public string? LinkedPurchaseToken { get; init; }

    public string? AcknowledgementState { get; init; }

    /// <summary>An empty object, present only for a license-tester purchase.</summary>
    public PresenceDto? TestPurchase { get; init; }

    public ExternalAccountIdentifiersDto? ExternalAccountIdentifiers { get; init; }

    public string? StartTime { get; init; }
}

internal sealed class SubscriptionLineItemDto
{
    public string? ProductId { get; init; }

    public string? ExpiryTime { get; init; }

    public string? LatestSuccessfulOrderId { get; init; }
}

internal sealed class ExternalAccountIdentifiersDto
{
    public string? ObfuscatedExternalAccountId { get; init; }
}

/// <summary>A member whose presence is the signal (<c>testPurchase</c>, <c>testPurchaseContext</c>); its fields are not read.</summary>
internal sealed class PresenceDto;

/// <summary><c>ProductPurchaseV2</c> (<c>purchases.productsv2.getproductpurchasev2</c>).</summary>
internal sealed class ProductPurchaseV2Dto
{
    public List<ProductLineItemDto>? ProductLineItem { get; init; }

    public PurchaseStateContextDto? PurchaseStateContext { get; init; }

    public PresenceDto? TestPurchaseContext { get; init; }

    public string? OrderId { get; init; }

    public string? ObfuscatedExternalAccountId { get; init; }

    public string? AcknowledgementState { get; init; }

    public string? PurchaseCompletionTime { get; init; }
}

internal sealed class ProductLineItemDto
{
    public string? ProductId { get; init; }
}

internal sealed class PurchaseStateContextDto
{
    public string? PurchaseState { get; init; }
}

/// <summary><c>Order</c> (<c>orders.get</c>): only the token and the state.</summary>
internal sealed class OrderDto
{
    public string? PurchaseToken { get; init; }

    public string? State { get; init; }
}

/// <summary>
/// <c>VoidedPurchasesListResponse</c> (T-133 §4): only <c>voidedPurchases[].{purchaseToken, orderId, voidedTimeMillis}</c> and
/// <c>tokenPagination.nextPageToken</c>; no catch-all member (T-133 AC 5).
/// </summary>
internal sealed class VoidedPurchasesListDto
{
    public List<VoidedPurchaseDto>? VoidedPurchases { get; init; }

    public TokenPaginationDto? TokenPagination { get; init; }
}

internal sealed class VoidedPurchaseDto
{
    public string? PurchaseToken { get; init; }

    public string? OrderId { get; init; }

    /// <summary>An int64 Google writes as a string.</summary>
    [JsonNumberHandling(JsonNumberHandling.AllowReadingFromString)]
    public long? VoidedTimeMillis { get; init; }
}

internal sealed class TokenPaginationDto
{
    public string? NextPageToken { get; init; }
}

[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    UnmappedMemberHandling = JsonUnmappedMemberHandling.Skip,
    NumberHandling = JsonNumberHandling.Strict)]
[JsonSerializable(typeof(VoidedPurchasesListDto))]
[JsonSerializable(typeof(SubscriptionPurchaseV2Dto))]
[JsonSerializable(typeof(ProductPurchaseV2Dto))]
[JsonSerializable(typeof(OrderDto))]
internal sealed partial class PlayJsonContext : JsonSerializerContext;

/// <summary>RFC 3339 timestamps as Google writes them (up to nanoseconds); anything else is <c>null</c>.</summary>
internal static class PlayTime
{
    public static DateTimeOffset? Parse(string? text)
    {
        if (string.IsNullOrEmpty(text) || text.Length > 40)
        {
            return null;
        }

        // .NET parses at most 7 fractional digits: cut nanoseconds to 100 ns ticks before parsing.
        var dot = text.IndexOf('.', StringComparison.Ordinal);
        if (dot > 0)
        {
            var end = dot + 1;
            while (end < text.Length && char.IsAsciiDigit(text[end]))
            {
                end++;
            }

            if (end - dot - 1 > 7)
            {
                text = string.Concat(text.AsSpan(0, dot + 8), text.AsSpan(end));
            }
        }

        return DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var value)
            ? value
            : null;
    }
}
