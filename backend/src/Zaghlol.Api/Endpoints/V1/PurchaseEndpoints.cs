using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Idempotency;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Api.Signing;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// <c>POST /v1/purchases/verify</c> (backend-api §4.3, T-130 design note §1). Filters in order: install token, time nonce,
/// idempotency (claim, then complete), response signature. Android runs the Play verifier with the install-binding check;
/// iOS answers <c>503 UPSTREAM_UNAVAILABLE</c> until T-131 registers the App Store verifier. Store outages are
/// <c>502 STORE_UNAVAILABLE</c> (our own budget: <c>503 UPSTREAM_UNAVAILABLE</c>), both with <c>Retry-After</c>, never stored and
/// never a grant. A rejected purchase is a final <c>422</c>. The grant (seat and entitlement) is <see cref="IVerifyGrant"/>.
/// </summary>
internal static partial class PurchaseEndpoints
{
    public const string AccountHeader = "Zaghlol-Account";

    /// <summary>The OpenAPI <c>productId</c> pattern (<c>^[a-z0-9_.]{3,100}$</c>), anchored with <c>\z</c>.</summary>
    public const string ProductIdPattern = @"^[a-z0-9_.]{3,100}\z";

    /// <summary><c>Retry-After</c> for iOS until T-131.</summary>
    public const int IosUnavailableRetryAfterSeconds = 3600;

    public static IEndpointRouteBuilder MapPurchases(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapInstallScoped()
            .MapPost("/purchases/verify", VerifyAsync)
            .WithName("verifyPurchase")
            .WithTimeNonce()
            .WithIdempotency(IdempotentOperation.VerifyPurchase)
            .RequireResponseSignature();
        return endpoints;
    }

    private static async Task<IResult> VerifyAsync(
        HttpContext context,
        [FromServices] IEnumerable<IStoreVerification> verifiers,
        [FromServices] IVerifyGrant grant,
        [FromServices] IPurchaseTelemetry telemetry,
        [FromServices] TimeProvider clock,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var read = await StrictJson.ReadAsync<PurchaseVerifyRequest>(context);
        if (read.Value is not { } request)
        {
            return read.Error!;
        }

        PurchaseStore store;
        StorePurchaseRef purchase;
        switch (request.Platform)
        {
            case "android":
                if (request.SignedTransaction is not null || request.SeatKeys is not null)
                {
                    return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.UnknownField);
                }

                if (request.ProductId is not { } productId || !ProductId().IsMatch(productId)
                    || request.PurchaseToken?.Reveal() is not { Length: > 0 })
                {
                    return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
                }

                // A token outside ^[A-Za-z0-9._-]{1,512}$ is a final 422 PURCHASE_TOKEN_INVALID from the verifier, with no Play call.
                store = PurchaseStore.GooglePlay;
                purchase = new StorePurchaseRef(productId, request.PurchaseToken.Value);
                break;

            case "ios":
                if (request.ProductId is not null || request.PurchaseToken is not null)
                {
                    return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.UnknownField);
                }

                if (request.SignedTransaction?.Reveal() is not { Length: > 0 })
                {
                    return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
                }

                // T-131 adds the App Store verifier; until then iOS verify is an outage the app retries, never a rejection.
                telemetry.Verified(PurchaseTags.AppStore, PurchaseTags.Failure, ErrorCodes.UpstreamUnavailable);
                return Unavailable(context, StatusCodes.Status503ServiceUnavailable, ErrorCodes.UpstreamUnavailable, IosUnavailableRetryAfterSeconds);

            default:
                return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        var storeName = PurchaseTags.StoreName(store);
        var verifier = verifiers.FirstOrDefault(v => v.Store == store);
        if (verifier is null)
        {
            telemetry.Verified(storeName, PurchaseTags.Failure, ErrorCodes.UpstreamUnavailable);
            return Unavailable(context, StatusCodes.Status503ServiceUnavailable, ErrorCodes.UpstreamUnavailable, IosUnavailableRetryAfterSeconds);
        }

        var installId = InstallTokenAuthentication.InstallIdOf(context.User);
        StoreVerificationResult result;
        try
        {
            result = await verifier.VerifyAsync(purchase, installId, BindingCheck.RequireCaller, cancellationToken);
        }
        catch (StoreUnavailableException unavailable)
        {
            var (status, code) = unavailable.Kind == StoreFailureKind.Budget
                ? (StatusCodes.Status503ServiceUnavailable, ErrorCodes.UpstreamUnavailable)
                : (StatusCodes.Status502BadGateway, ErrorCodes.StoreUnavailable);
            telemetry.Verified(storeName, PurchaseTags.Failure, code);
            return Unavailable(context, status, code, unavailable.RetryAfterSeconds);
        }

        if (result.Status == VerifyStatus.Invalid)
        {
            var code = result.ProblemCode ?? ErrorCodes.PurchaseTokenInvalid;
            telemetry.Verified(storeName, PurchaseTags.Failure, code);
            return ApiProblems.Of(StatusCodes.Status422UnprocessableEntity, code);
        }

        var now = clock.GetUtcNow();
        var account = context.Request.Headers[AccountHeader] is { Count: 1 } header && header[0] is { Length: > 0 } value
            ? new Sensitive<string>(value)
            : (Sensitive<string>?)null;
        // Never grant on doubt: only an active purchase that was written may reach the grant step (pending, expired and
        // refunded answer entitlement: null whatever the grant would say).
        var granted = result is { Status: VerifyStatus.Active, PurchaseId: not null }
            ? await grant.ComposeAsync(result, new VerifyContext(installId, account, now), cancellationToken)
            : VerifyGrantResult.None;
        telemetry.Verified(storeName, PurchaseTags.Success, PurchaseTags.NoCode);

        var response = new PurchaseVerifyResponse
        {
            Status = StatusText(result.Status),
            Entitlement = granted.EntitlementToken is { } token ? new PurchaseEntitlementDto { Token = token } : null,
            SeatHeldElsewhere = granted.SeatHeldElsewhere,
            AccountRequired = granted.AccountRequired,
            NextMoveAt = granted.NextMoveAt,
            ServerTime = WholeSecond(now),
            TimeNonce = context.TimeNonce(),
        };
        return new AnchoredJsonResult(response, JsonSerializer.SerializeToUtf8Bytes(response, ApiJsonContext.Default.PurchaseVerifyResponse));
    }

    internal static string StatusText(VerifyStatus status) => status switch
    {
        VerifyStatus.Active => "active",
        VerifyStatus.Pending => "pending",
        VerifyStatus.Expired => "expired",
        VerifyStatus.Refunded => "refunded",
        _ => "invalid",
    };

    private static Microsoft.AspNetCore.Http.HttpResults.ProblemHttpResult Unavailable(HttpContext context, int status, string code, int retryAfterSeconds)
    {
        context.Response.Headers.RetryAfter = retryAfterSeconds.ToString(CultureInfo.InvariantCulture);
        return TypedResults.Problem(
            statusCode: status,
            extensions: new Dictionary<string, object?> { ["code"] = code, ["retryAfterSeconds"] = retryAfterSeconds });
    }

    private static DateTimeOffset WholeSecond(DateTimeOffset value)
    {
        var utc = value.ToUniversalTime();
        return new DateTimeOffset(utc.Ticks - (utc.Ticks % TimeSpan.TicksPerSecond), TimeSpan.Zero);
    }

    [GeneratedRegex(ProductIdPattern, RegexOptions.CultureInvariant)]
    private static partial Regex ProductId();
}
