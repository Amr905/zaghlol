using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Idempotency;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Api.Signing;
using Zaghlol.Application.Accounts;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;
using IdempotentOperation = Zaghlol.Infrastructure.Persistence.Entities.IdempotentOperation;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// <c>POST /v1/accounts/signin</c>, <c>POST /v1/accounts/signout</c> and <c>DELETE /v1/accounts/me</c> (backend-api §4.6, T-135).
/// Sign-in: install token, time nonce, idempotency, response signature; the body is parsed strictly (only the members of
/// <see cref="SignInRequestDto"/>) and every pattern the OpenAPI file declares is checked before any token work; everything else is
/// <see cref="SignInService"/>. Sign-out: install token, time nonce, response signature; delete: install token. Both need a valid
/// <c>Zaghlol-Account</c> token, else <c>401 ACCOUNT_TOKEN_EXPIRED</c> (R3-6). No answer carries a token, key or proof the caller
/// didn't earn, and nothing from the request is logged.
/// </summary>
internal static partial class AccountEndpoints
{
    /// <summary>The OpenAPI <c>nonce</c> pattern, anchored with <c>\z</c>.</summary>
    public const string NoncePattern = @"^[A-Za-z0-9_-]{22,128}\z";

    /// <summary><c>Retry-After</c> when the provider's keys or Apple's revocation endpoint are unavailable.</summary>
    public const int UnavailableRetryAfterSeconds = 30;

    private const int MaxIdTokenLength = 16384;
    private const int MaxAuthorizationCodeLength = 2048;

    public static IEndpointRouteBuilder MapAccounts(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        var scoped = endpoints.MapInstallScoped();
        scoped.MapPost("/accounts/signin", SignInAsync)
            .WithName("signIn")
            .WithTimeNonce()
            .WithIdempotency(IdempotentOperation.SignIn)
            .RequireResponseSignature();
        scoped.MapPost("/accounts/signout", SignOutAsync)
            .WithName("signOut")
            .WithTimeNonce()
            .RequireResponseSignature();
        scoped.MapDelete("/accounts/me", DeleteAsync).WithName("deleteAccount");
        endpoints.MapAppleCallback();
        return endpoints;
    }

    private static async Task<IResult> SignInAsync(
        HttpContext context,
        [FromServices] SignInService service,
        [FromServices] TimeProvider clock,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var read = await StrictJson.ReadAsync<SignInRequestDto>(context);
        if (read.Value is not { } request)
        {
            return read.Error!;
        }

        if (Command(request) is not { } command)
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        var install = InstallTokenAuthentication.InstallIdOf(context.User);
        var result = await service.SignInAsync(command, install, cancellationToken);
        switch (result.Kind)
        {
            case SignInResultKind.IdTokenInvalid:
                return ApiProblems.Of(StatusCodes.Status422UnprocessableEntity, ErrorCodes.IdTokenInvalid);
            case SignInResultKind.ValidationFailed:
                return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
            case SignInResultKind.SeatKeyMismatch:
                return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.SeatKeyMismatch);
            case SignInResultKind.LinkedToOtherAccount:
                return ApiProblems.Of(StatusCodes.Status409Conflict, ErrorCodes.InstallLinkedToOtherAccount);
            case SignInResultKind.Unavailable:
                return Unavailable(context);
            case SignInResultKind.InstallGone:
                context.Response.Headers.WWWAuthenticate = "Bearer";
                return ApiProblems.Of(StatusCodes.Status401Unauthorized, ErrorCodes.InstallTokenInvalid);
            default:
                // The idempotency store records the account whose token this body holds (R3-6).
                context.Items[IdempotencyFilter.AccountItem] = result.AccountId;
                var response = new SignInResponse
                {
                    AccountId = result.AccountId,
                    AccountToken = result.AccountToken,
                    Entitlement = new PurchaseEntitlementDto { Token = result.EntitlementToken },
                    LinkedInstalls = result.LinkedInstalls,
                    MovedFromOtherPhone = result.MovedFromOtherPhone,
                    MoveRefused = result.MoveRefused,
                    RestoreSuggested = result.RestoreSuggested,
                    NextMoveAt = result.NextMoveAt,
                    ServerTime = WholeSecond(clock.GetUtcNow()),
                    TimeNonce = context.TimeNonce(),
                };
                return new AnchoredJsonResult(response, JsonSerializer.SerializeToUtf8Bytes(response, ApiJsonContext.Default.SignInResponse));
        }
    }

    private static async Task<IResult> SignOutAsync(
        HttpContext context,
        [FromServices] AccountLifecycleService service,
        [FromServices] TimeProvider clock,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var install = InstallTokenAuthentication.InstallIdOf(context.User);
        var result = await service.SignOutAsync(install, SyncEndpoints.AccountHeader(context), cancellationToken);
        if (result.Kind != AccountLifecycleKind.Completed)
        {
            return ApiProblems.Of(StatusCodes.Status401Unauthorized, ErrorCodes.AccountTokenExpired);
        }

        var response = new EntitlementResponse
        {
            Entitlement = new PurchaseEntitlementDto { Token = result.EntitlementToken },
            ServerTime = WholeSecond(clock.GetUtcNow()),
            TimeNonce = context.TimeNonce(),
            SupportNotice = null,
        };
        return new AnchoredJsonResult(response, JsonSerializer.SerializeToUtf8Bytes(response, ApiJsonContext.Default.EntitlementResponse));
    }

    private static async Task<IResult> DeleteAsync(
        HttpContext context,
        [FromServices] AccountLifecycleService service,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var install = InstallTokenAuthentication.InstallIdOf(context.User);
        return await service.DeleteAsync(install, SyncEndpoints.AccountHeader(context), cancellationToken) switch
        {
            AccountLifecycleKind.Completed => TypedResults.NoContent(),
            AccountLifecycleKind.Unavailable => Unavailable(context),
            _ => ApiProblems.Of(StatusCodes.Status401Unauthorized, ErrorCodes.AccountTokenExpired),
        };
    }

    /// <summary>The OpenAPI patterns and limits of <c>SignInRequest</c>; null when any is violated (a request without <c>nonce</c> passes: it is a 422).</summary>
    private static SignInCommand? Command(SignInRequestDto request)
    {
        var provider = request.Provider switch
        {
            "google" => AccountProvider.Google,
            "apple" => AccountProvider.Apple,
            _ => (AccountProvider?)null,
        };
        if (provider is null || request.IdToken.Reveal() is not { Length: > 0 and <= MaxIdTokenLength } idToken || !CompactJws().IsMatch(idToken))
        {
            return null;
        }

        if (request.Nonce is { } nonce && (nonce.Reveal() is not { } text || !Nonce().IsMatch(text)))
        {
            return null;
        }

        if (request.AuthorizationCode is { } code
            && (provider != AccountProvider.Apple || code.Reveal() is not { Length: > 0 and <= MaxAuthorizationCodeLength }))
        {
            return null;
        }

        IReadOnlyList<SeatKeyProofInput?>? seatKeys = null;
        if (request.SeatKeys is { } keys)
        {
            var list = keys.Reveal();
            if (list is null || list.Count is < 1 or > 5)
            {
                return null;
            }

            seatKeys = [.. list.Select(k => k is null ? null : new SeatKeyProofInput(k.PublicKey, k.Signature))];
        }

        return new SignInCommand(provider.Value, request.IdToken, request.Nonce, request.AuthorizationCode, request.ReplaceLink == true, seatKeys);
    }

    private static Microsoft.AspNetCore.Http.HttpResults.ProblemHttpResult Unavailable(HttpContext context)
    {
        context.Response.Headers.RetryAfter = UnavailableRetryAfterSeconds.ToString(CultureInfo.InvariantCulture);
        return TypedResults.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            extensions: new Dictionary<string, object?> { ["code"] = ErrorCodes.UpstreamUnavailable, ["retryAfterSeconds"] = UnavailableRetryAfterSeconds });
    }

    private static DateTimeOffset WholeSecond(DateTimeOffset value)
    {
        var utc = value.ToUniversalTime();
        return new DateTimeOffset(utc.Ticks - (utc.Ticks % TimeSpan.TicksPerSecond), TimeSpan.Zero);
    }

    [GeneratedRegex(NoncePattern, RegexOptions.CultureInvariant)]
    private static partial Regex Nonce();

    [GeneratedRegex(@"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\z", RegexOptions.CultureInvariant)]
    private static partial Regex CompactJws();
}
