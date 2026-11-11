using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization.Metadata;
using Polly.CircuitBreaker;
using Polly.Timeout;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Infrastructure.AppStore;

/// <summary>Metric tag values of App Store calls on <c>zaghlol.store.call</c> (fixed sets).</summary>
public static class AppStoreCallTags
{
    public static IReadOnlyList<string> Apis { get; } = ["tx_get", "sub_status", "order_lookup", "notification_history"];

    public static string Api(AppStoreApi api) => api switch
    {
        AppStoreApi.TransactionInfo => "tx_get",
        AppStoreApi.SubscriptionStatuses => "sub_status",
        AppStoreApi.OrderLookup => "order_lookup",
        AppStoreApi.NotificationHistory => "notification_history",
        _ => "invalid",
    };

    public static string Outcome(AppStoreCallOutcome outcome) => outcome switch
    {
        AppStoreCallOutcome.Ok => "ok",
        AppStoreCallOutcome.ClientError => "client_error",
        AppStoreCallOutcome.AuthError => "auth_error",
        AppStoreCallOutcome.RateLimited => "rate_limited",
        AppStoreCallOutcome.ServerError => "server_error",
        AppStoreCallOutcome.Timeout => "timeout",
        AppStoreCallOutcome.CircuitOpen => "circuit_open",
        AppStoreCallOutcome.BudgetDenied => "budget_denied",
        _ => "invalid",
    };
}

/// <summary>
/// The App Store Server API over two named <see cref="HttpClient"/>s, one per environment, each with its own resilience pipeline
/// (T-131 design note §6). The environment of the signed transaction picks the client; nothing ever falls back from one to the
/// other. Identifiers are URL-escaped into the path and each request names its URL template, so spans and pipeline logs never carry
/// them; request logging is off. Response bodies are capped and never read into an exception or a log: only Apple's numeric
/// <c>errorCode</c> is read from an error. Failures are <see cref="AppStoreApiException"/> with a constant message.
/// </summary>
internal sealed class AppStoreServerApiClient(IHttpClientFactory clients, ZaghlolMetrics metrics) : IAppStoreServerApi
{
    public const string ProductionClient = "app-store-production";
    public const string SandboxClient = "app-store-sandbox";

    public const string TransactionTemplate = "/inApps/v1/transactions/{transactionId}";
    public const string SubscriptionsTemplate = "/inApps/v1/subscriptions/{transactionId}";
    public const string LookupTemplate = "/inApps/v1/lookup/{orderId}";
    public const string HistoryTemplate = "/inApps/v1/notifications/history";

    /// <summary>The largest response read (a status or lookup answer with its JWSs is tens of KB).</summary>
    public const int MaxResponseBytes = 1024 * 1024;

    public async Task<Sensitive<string>> GetTransactionInfoAsync(PurchaseEnvironment environment, Sensitive<string> transactionId, StoreLane lane, CancellationToken cancellationToken)
    {
        var dto = await ReadAsync(
            AppStoreApi.TransactionInfo,
            environment,
            lane,
            HttpMethod.Get,
            "inApps/v1/transactions/" + Escape(transactionId),
            null,
            TransactionTemplate,
            AppleJsonContext.Default.TransactionInfoResponseDto,
            cancellationToken);
        return dto.SignedTransactionInfo is { Length: > 0 } signed
            ? new Sensitive<string>(signed)
            : throw Fail(AppStoreApi.TransactionInfo, environment, AppStoreCallOutcome.ServerError, 200);
    }

    public async Task<IReadOnlyList<AppleLastTransaction>> GetAllSubscriptionStatusesAsync(
        PurchaseEnvironment environment,
        Sensitive<string> transactionId,
        StoreLane lane,
        CancellationToken cancellationToken)
    {
        var dto = await ReadAsync(
            AppStoreApi.SubscriptionStatuses,
            environment,
            lane,
            HttpMethod.Get,
            "inApps/v1/subscriptions/" + Escape(transactionId),
            null,
            SubscriptionsTemplate,
            AppleJsonContext.Default.StatusResponseDto,
            cancellationToken);
        return
        [
            .. (dto.Data ?? []).SelectMany(g => g.LastTransactions ?? []).Select(t => new AppleLastTransaction(
                t.Status,
                Wrap(t.OriginalTransactionId),
                Wrap(t.SignedTransactionInfo),
                Wrap(t.SignedRenewalInfo))),
        ];
    }

    public async Task<AppleOrderLookupResult> LookUpOrderIdAsync(Sensitive<string> orderId, StoreLane lane, CancellationToken cancellationToken)
    {
        var dto = await ReadAsync(
            AppStoreApi.OrderLookup,
            PurchaseEnvironment.Production,
            lane,
            HttpMethod.Get,
            "inApps/v1/lookup/" + Escape(orderId),
            null,
            LookupTemplate,
            AppleJsonContext.Default.OrderLookupResponseDto,
            cancellationToken);
        return new AppleOrderLookupResult(dto.Status, [.. (dto.SignedTransactions ?? []).Select(s => new Sensitive<string>(s))]);
    }

    public async Task<AppleNotificationHistoryPage> GetNotificationHistoryAsync(
        PurchaseEnvironment environment,
        DateTimeOffset startDate,
        DateTimeOffset endDate,
        Sensitive<string>? paginationToken,
        StoreLane lane,
        CancellationToken cancellationToken)
    {
        // The continuation goes in the query (Apple's contract); the span carries only the template, and request logging is off.
        var path = "inApps/v1/notifications/history"
            + (paginationToken?.Reveal() is { Length: > 0 } token ? "?paginationToken=" + Uri.EscapeDataString(token) : string.Empty);
        var body = new NotificationHistoryRequestDto
        {
            StartDate = startDate.ToUnixTimeMilliseconds(),
            EndDate = endDate.ToUnixTimeMilliseconds(),
            OnlyFailures = true,
        };
        var dto = await ReadAsync(
            AppStoreApi.NotificationHistory,
            environment,
            lane,
            HttpMethod.Post,
            path,
            JsonContent.Create(body, AppleJsonContext.Default.NotificationHistoryRequestDto),
            HistoryTemplate,
            AppleJsonContext.Default.NotificationHistoryResponseDto,
            cancellationToken);
        Sensitive<string>? next = dto.HasMore == true && dto.PaginationToken is { Length: > 0 } more ? new Sensitive<string>(more) : null;
        return new AppleNotificationHistoryPage(
            [.. (dto.NotificationHistory ?? []).Select(i => i.SignedPayload).OfType<string>().Select(p => new Sensitive<string>(p))],
            next is not null,
            next);
    }

    private static string Escape(Sensitive<string> value) => Uri.EscapeDataString(value.Reveal() ?? string.Empty);

    private static Sensitive<string>? Wrap(string? value) => value is null ? null : new Sensitive<string>(value);

    private static string Env(PurchaseEnvironment environment) => environment == PurchaseEnvironment.Sandbox ? "sandbox" : "production";

    private async Task<T> ReadAsync<T>(
        AppStoreApi api,
        PurchaseEnvironment environment,
        StoreLane lane,
        HttpMethod method,
        string path,
        HttpContent? content,
        string template,
        JsonTypeInfo<T> type,
        CancellationToken cancellationToken)
        where T : class
    {
        var http = clients.CreateClient(environment == PurchaseEnvironment.Sandbox ? SandboxClient : ProductionClient);
        using var request = new HttpRequestMessage(method, path) { Content = content }.SetUrlTemplate(template);
        request.Options.Set(AppleRequestLane.Key, lane);

        HttpResponseMessage response;
        try
        {
            // Buffered, so MaxResponseContentBufferSize caps every body, chunked ones included.
            response = await http.SendAsync(request, HttpCompletionOption.ResponseContentRead, cancellationToken);
        }
        catch (AppleBudgetDeniedException)
        {
            throw Fail(api, environment, AppStoreCallOutcome.BudgetDenied, null, null, TimeSpan.FromSeconds(60));
        }
        catch (BrokenCircuitException)
        {
            throw Fail(api, environment, AppStoreCallOutcome.CircuitOpen, null, null, TimeSpan.FromSeconds(30));
        }
        catch (TimeoutRejectedException)
        {
            throw Fail(api, environment, AppStoreCallOutcome.Timeout);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw Fail(api, environment, AppStoreCallOutcome.Timeout);
        }
        catch (HttpRequestException)
        {
            throw Fail(api, environment, AppStoreCallOutcome.ServerError);
        }
        catch (AppStoreApiTokenException)
        {
            throw Fail(api, environment, AppStoreCallOutcome.AuthError);
        }

        using (response)
        {
            var status = (int)response.StatusCode;
            var outcome = status switch
            {
                >= 200 and < 300 => AppStoreCallOutcome.Ok,
                401 or 403 => AppStoreCallOutcome.AuthError,
                408 => AppStoreCallOutcome.Timeout,
                429 => AppStoreCallOutcome.RateLimited,
                >= 500 => AppStoreCallOutcome.ServerError,
                _ => AppStoreCallOutcome.ClientError,
            };

            if (outcome != AppStoreCallOutcome.Ok)
            {
                var errorCode = outcome == AppStoreCallOutcome.ClientError ? await ErrorCodeAsync(response, cancellationToken) : null;
                var retryAfter = response.Headers.RetryAfter?.Delta
                    ?? (response.Headers.RetryAfter?.Date is { } date ? date - DateTimeOffset.UtcNow : null);
                throw Fail(api, environment, outcome, status, errorCode, retryAfter);
            }

            try
            {
                var dto = await response.Content.ReadFromJsonAsync(type, cancellationToken)
                    ?? throw Fail(api, environment, AppStoreCallOutcome.ServerError, status);
                metrics.StoreCall(PurchaseTags.AppStore, AppStoreCallTags.Api(api), AppStoreCallTags.Outcome(AppStoreCallOutcome.Ok), Env(environment));
                return dto;
            }
            catch (JsonException)
            {
                // A 2xx we can't parse says nothing about the purchase: an outage, never a grant or a rejection.
                throw Fail(api, environment, AppStoreCallOutcome.ServerError, status);
            }
        }
    }

    /// <summary>Apple's numeric <c>errorCode</c>; the message and anything else in the body are never read.</summary>
    private static async Task<int?> ErrorCodeAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        try
        {
            var error = await response.Content.ReadFromJsonAsync(AppleJsonContext.Default.ErrorPayloadDto, cancellationToken);
            return error?.ErrorCode is { } code && code is > 0 and <= int.MaxValue ? (int)code : null;
        }
        catch (Exception reading) when (reading is JsonException or NotSupportedException or InvalidOperationException)
        {
            return null;
        }
    }

    private AppStoreApiException Fail(
        AppStoreApi api,
        PurchaseEnvironment environment,
        AppStoreCallOutcome outcome,
        int? status = null,
        int? errorCode = null,
        TimeSpan? retryAfter = null)
    {
        metrics.StoreCall(PurchaseTags.AppStore, AppStoreCallTags.Api(api), AppStoreCallTags.Outcome(outcome), Env(environment));
        return new AppStoreApiException(api, outcome, status, errorCode, retryAfter is { } delay && delay > TimeSpan.Zero ? delay : null);
    }
}
