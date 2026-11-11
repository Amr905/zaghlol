using System.Globalization;
using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Polly.CircuitBreaker;
using Polly.Timeout;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.GooglePlay;

/// <summary>Metric tag values of <c>zaghlol.store.call</c> (fixed sets).</summary>
public static class StoreCallTags
{
    public static IReadOnlyList<string> Apis { get; } = ["sub_get", "prod_get", "sub_ack", "prod_ack", "orders_get", "voided_list"];

    public static IReadOnlyList<string> Outcomes { get; } =
        ["ok", "client_error", "auth_error", "rate_limited", "server_error", "timeout", "circuit_open", "budget_denied"];

    public static string Api(PlayApi api) => api switch
    {
        PlayApi.SubscriptionGet => "sub_get",
        PlayApi.ProductGet => "prod_get",
        PlayApi.SubscriptionAcknowledge => "sub_ack",
        PlayApi.ProductAcknowledge => "prod_ack",
        PlayApi.OrderGet => "orders_get",
        PlayApi.VoidedList => "voided_list",
        _ => "invalid",
    };

    public static string Outcome(PlayCallOutcome outcome) => outcome switch
    {
        PlayCallOutcome.Ok => "ok",
        PlayCallOutcome.ClientError => "client_error",
        PlayCallOutcome.AuthError => "auth_error",
        PlayCallOutcome.RateLimited => "rate_limited",
        PlayCallOutcome.ServerError => "server_error",
        PlayCallOutcome.Timeout => "timeout",
        PlayCallOutcome.CircuitOpen => "circuit_open",
        PlayCallOutcome.BudgetDenied => "budget_denied",
        _ => "invalid",
    };
}

/// <summary>
/// The Google Play Developer API v3 over a typed <see cref="HttpClient"/> (T-130 design note §7). The package comes from
/// configuration; the token or order ID is URL-escaped into the path and each request names its redacted URL template, so spans
/// and the resilience pipeline's logs never carry it. Only <c>subscriptionsv2.get</c>, <c>productsv2.getproductpurchasev2</c>,
/// the two acknowledge calls, <c>orders.get</c> and <c>voidedpurchases.list</c> (T-133) exist here: the v1 <c>products.get</c> and
/// <c>subscriptions.get</c> can't be called. A response body is never read into an exception or a log; errors are
/// <see cref="PlayApiException"/> with a constant message. Each request names its budget lane; <see cref="PlayBudgetHandler"/> inside
/// the resilience pipeline charges one permit per attempt (T-133 §6).
/// </summary>
internal sealed class PlayDeveloperApiClient(
    HttpClient http,
    GooglePlayOptions options,
    ZaghlolMetrics metrics,
    TimeProvider clock) : IPlayDeveloperApi
{
    public const string ApplicationsPath = "androidpublisher/v3/applications/";
    public const string TemplatePrefix = "/androidpublisher/v3/applications/{packageName}";
    public const string SubscriptionGetTemplate = TemplatePrefix + "/purchases/subscriptionsv2/tokens/{token}";
    public const string ProductGetTemplate = TemplatePrefix + "/purchases/productsv2/tokens/{token}";
    public const string SubscriptionAcknowledgeTemplate = TemplatePrefix + "/purchases/subscriptions/{subscriptionId}/tokens/{token}:acknowledge";
    public const string ProductAcknowledgeTemplate = TemplatePrefix + "/purchases/products/{productId}/tokens/{token}:acknowledge";
    public const string OrderGetTemplate = TemplatePrefix + "/orders/{orderId}";
    public const string VoidedListTemplate = TemplatePrefix + "/purchases/voidedpurchases";

    /// <summary>Play's largest page (T-133 §4).</summary>
    public const int VoidedPageSize = 1000;

    /// <summary>The largest Play response read (a subscription or order is a few KB).</summary>
    public const int MaxResponseBytes = 256 * 1024;

    private const string Acknowledged = "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED";

    private string Package => Uri.EscapeDataString(options.Catalog.PackageName);

    public async Task<PlaySubscription> GetSubscriptionAsync(Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken)
    {
        var path = $"{ApplicationsPath}{Package}/purchases/subscriptionsv2/tokens/{Escape(token)}";
        var dto = await ReadAsync(PlayApi.SubscriptionGet, lane, HttpMethod.Get, path, SubscriptionGetTemplate, PlayJsonContext.Default.SubscriptionPurchaseV2Dto, cancellationToken);
        return new PlaySubscription(
            SubscriptionState(dto.SubscriptionState),
            [.. (dto.LineItems ?? []).Select(i => new PlayLineItem(i.ProductId, PlayTime.Parse(i.ExpiryTime), Wrap(i.LatestSuccessfulOrderId)))],
            Wrap(dto.LinkedPurchaseToken),
            dto.AcknowledgementState == Acknowledged,
            dto.TestPurchase is not null,
            dto.ExternalAccountIdentifiers?.ObfuscatedExternalAccountId,
            PlayTime.Parse(dto.StartTime));
    }

    public async Task<PlayProduct> GetProductAsync(Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken)
    {
        var path = $"{ApplicationsPath}{Package}/purchases/productsv2/tokens/{Escape(token)}";
        var dto = await ReadAsync(PlayApi.ProductGet, lane, HttpMethod.Get, path, ProductGetTemplate, PlayJsonContext.Default.ProductPurchaseV2Dto, cancellationToken);
        return new PlayProduct(
            [.. (dto.ProductLineItem ?? []).Select(i => i.ProductId).OfType<string>()],
            ProductState(dto.PurchaseStateContext?.PurchaseState),
            dto.TestPurchaseContext is not null,
            Wrap(dto.OrderId),
            dto.ObfuscatedExternalAccountId,
            dto.AcknowledgementState == Acknowledged,
            PlayTime.Parse(dto.PurchaseCompletionTime));
    }

    public Task AcknowledgeSubscriptionAsync(string productId, Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken) =>
        SendAsync(
            PlayApi.SubscriptionAcknowledge,
            lane,
            $"{ApplicationsPath}{Package}/purchases/subscriptions/{Uri.EscapeDataString(productId)}/tokens/{Escape(token)}:acknowledge",
            SubscriptionAcknowledgeTemplate,
            cancellationToken);

    public Task AcknowledgeProductAsync(string productId, Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken) =>
        SendAsync(
            PlayApi.ProductAcknowledge,
            lane,
            $"{ApplicationsPath}{Package}/purchases/products/{Uri.EscapeDataString(productId)}/tokens/{Escape(token)}:acknowledge",
            ProductAcknowledgeTemplate,
            cancellationToken);

    public async Task<PlayOrder> GetOrderAsync(Sensitive<string> orderId, StoreLane lane, CancellationToken cancellationToken)
    {
        var path = $"{ApplicationsPath}{Package}/orders/{Escape(orderId)}";
        var dto = await ReadAsync(PlayApi.OrderGet, lane, HttpMethod.Get, path, OrderGetTemplate, PlayJsonContext.Default.OrderDto, cancellationToken);
        return new PlayOrder(Wrap(dto.PurchaseToken), OrderState(dto.State));
    }

    public async Task<PlayVoidedPage> ListVoidedPurchasesAsync(
        DateTimeOffset from,
        DateTimeOffset until,
        Sensitive<string>? pageToken,
        StoreLane lane,
        CancellationToken cancellationToken)
    {
        // type=1: one-time products and subscriptions (renewals share a token, so the job keys each void by orderId too).
        var query = new StringBuilder("?type=1&maxResults=")
            .Append(VoidedPageSize.ToString(CultureInfo.InvariantCulture))
            .Append("&startTime=").Append(from.ToUnixTimeMilliseconds().ToString(CultureInfo.InvariantCulture))
            .Append("&endTime=").Append(until.ToUnixTimeMilliseconds().ToString(CultureInfo.InvariantCulture));
        if (pageToken?.Reveal() is { Length: > 0 } token)
        {
            query.Append("&token=").Append(Uri.EscapeDataString(token));
        }

        var path = $"{ApplicationsPath}{Package}/purchases/voidedpurchases{query}";
        var dto = await ReadAsync(PlayApi.VoidedList, lane, HttpMethod.Get, path, VoidedListTemplate, PlayJsonContext.Default.VoidedPurchasesListDto, cancellationToken);
        return new PlayVoidedPage(
            [.. (dto.VoidedPurchases ?? []).Select(v => new PlayVoidedPurchase(Wrap(v.PurchaseToken), Wrap(v.OrderId), v.VoidedTimeMillis))],
            Wrap(dto.TokenPagination?.NextPageToken));
    }

    internal static PlaySubscriptionState SubscriptionState(string? value) => value switch
    {
        "SUBSCRIPTION_STATE_PENDING" => PlaySubscriptionState.Pending,
        "SUBSCRIPTION_STATE_ACTIVE" => PlaySubscriptionState.Active,
        "SUBSCRIPTION_STATE_PAUSED" => PlaySubscriptionState.Paused,
        "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" => PlaySubscriptionState.InGracePeriod,
        "SUBSCRIPTION_STATE_ON_HOLD" => PlaySubscriptionState.OnHold,
        "SUBSCRIPTION_STATE_CANCELED" => PlaySubscriptionState.Canceled,
        "SUBSCRIPTION_STATE_EXPIRED" => PlaySubscriptionState.Expired,
        "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED" => PlaySubscriptionState.PendingPurchaseCanceled,
        _ => PlaySubscriptionState.Unknown,
    };

    internal static PlayProductState ProductState(string? value) => value switch
    {
        "PURCHASED" => PlayProductState.Purchased,
        "CANCELLED" => PlayProductState.Cancelled,
        "PENDING" => PlayProductState.Pending,
        _ => PlayProductState.Unknown,
    };

    internal static PlayOrderState OrderState(string? value) => value switch
    {
        "PENDING" => PlayOrderState.Pending,
        "PROCESSED" => PlayOrderState.Processed,
        "CANCELED" => PlayOrderState.Canceled,
        "PENDING_REFUND" => PlayOrderState.PendingRefund,
        "PARTIALLY_REFUNDED" => PlayOrderState.PartiallyRefunded,
        "REFUNDED" => PlayOrderState.Refunded,
        _ => PlayOrderState.Unknown,
    };

    private static string Escape(Sensitive<string> value) => Uri.EscapeDataString(value.Reveal() ?? string.Empty);

    private static Sensitive<string>? Wrap(string? value) => value is null ? null : new Sensitive<string>(value);

    private async Task<T> ReadAsync<T>(
        PlayApi api,
        StoreLane lane,
        HttpMethod method,
        string path,
        string template,
        System.Text.Json.Serialization.Metadata.JsonTypeInfo<T> typeInfo,
        CancellationToken cancellationToken)
        where T : class
    {
        using var response = await CallAsync(api, lane, method, path, template, cancellationToken);
        try
        {
            return await response.Content.ReadFromJsonAsync(typeInfo, cancellationToken) ?? throw Fail(api, PlayCallOutcome.ServerError, (int)response.StatusCode);
        }
        catch (JsonException)
        {
            // A 2xx we can't parse says nothing about the purchase: an outage, never a grant or a rejection.
            throw Fail(api, PlayCallOutcome.ServerError, (int)response.StatusCode);
        }
    }

    private async Task SendAsync(PlayApi api, StoreLane lane, string path, string template, CancellationToken cancellationToken)
    {
        using var response = await CallAsync(api, lane, HttpMethod.Post, path, template, cancellationToken);
    }

    private async Task<HttpResponseMessage> CallAsync(
        PlayApi api,
        StoreLane lane,
        HttpMethod method,
        string path,
        string template,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(method, new Uri(options.BaseUrl, path)).SetUrlTemplate(template);
        request.Options.Set(PlayRequestLane.Key, lane);
        if (method == HttpMethod.Post)
        {
            request.Content = new StringContent("{}", Encoding.UTF8, "application/json");
        }

        HttpResponseMessage response;
        try
        {
            // Buffered, so MaxResponseContentBufferSize (256 KB) caps every body, chunked ones included.
            response = await http.SendAsync(request, HttpCompletionOption.ResponseContentRead, cancellationToken);
        }
        catch (PlayBudgetDeniedException)
        {
            // Our own budget, per attempt (possibly mid-retry): never retried by the pipeline.
            throw Fail(api, PlayCallOutcome.BudgetDenied, null, TimeSpan.FromSeconds(60));
        }
        catch (BrokenCircuitException)
        {
            throw Fail(api, PlayCallOutcome.CircuitOpen, null, TimeSpan.FromSeconds(30));
        }
        catch (TimeoutRejectedException)
        {
            throw Fail(api, PlayCallOutcome.Timeout);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw Fail(api, PlayCallOutcome.Timeout);
        }
        catch (HttpRequestException)
        {
            throw Fail(api, PlayCallOutcome.ServerError);
        }
        catch (PlayAccessTokenException)
        {
            throw Fail(api, PlayCallOutcome.AuthError);
        }

        var status = (int)response.StatusCode;
        var outcome = status switch
        {
            >= 200 and < 300 => PlayCallOutcome.Ok,
            401 or 403 => PlayCallOutcome.AuthError,
            408 => PlayCallOutcome.Timeout,
            429 => PlayCallOutcome.RateLimited,
            >= 500 => PlayCallOutcome.ServerError,
            _ => PlayCallOutcome.ClientError,
        };

        if (outcome == PlayCallOutcome.Ok)
        {
            metrics.StoreCall(PurchaseTags.GooglePlay, StoreCallTags.Api(api), StoreCallTags.Outcome(outcome));
            return response;
        }

        var retryAfter = RetryAfter(response, clock);
        response.Dispose();
        throw Fail(api, outcome, status, retryAfter);
    }

    /// <summary><c>Retry-After</c> as a delay; the date form against the injected clock (FU-098 nit 7).</summary>
    internal static TimeSpan? RetryAfter(HttpResponseMessage response, TimeProvider clock) =>
        response.Headers.RetryAfter?.Delta
        ?? (response.Headers.RetryAfter?.Date is { } date ? date - clock.GetUtcNow() : null);

    private PlayApiException Fail(PlayApi api, PlayCallOutcome outcome, int? status = null, TimeSpan? retryAfter = null)
    {
        metrics.StoreCall(PurchaseTags.GooglePlay, StoreCallTags.Api(api), StoreCallTags.Outcome(outcome));
        return new PlayApiException(api, outcome, status, retryAfter is { } delay && delay > TimeSpan.Zero ? delay : null);
    }
}
