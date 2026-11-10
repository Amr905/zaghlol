using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Primitives;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Api.Signing;
using Zaghlol.Application.Prices;
using Zaghlol.Application.Sync;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// <c>POST /v1/sync</c> (backend-api §4.2, T-128 design note). Filters: install token, then <c>Zaghlol-Time-Nonce</c>, then the
/// response signature; deliberately no idempotency filter (the throttle is the idempotency mechanism, design note §3). The body
/// is shape-checked before any database access, also when the call will be throttled. Every 200, full or throttled, is signed
/// and echoes the request's nonce.
/// </summary>
internal static partial class SyncEndpoints
{
    public const string AppHeader = "Zaghlol-App";

    /// <summary>The OpenAPI <c>ZaghlolApp</c> <c>maxLength</c>.</summary>
    public const int AppHeaderMaxLength = 64;

    /// <summary><c>Retry-After</c> of a 503 from the sync (design note §5).</summary>
    public const int RetryAfterSeconds = 30;

    public static IEndpointRouteBuilder MapSync(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapInstallScoped()
            .MapPost("/sync", SyncAsync)
            .WithName("sync")
            .WithTimeNonce()
            .RequireResponseSignature();
        return endpoints;
    }

    private static async Task<IResult> SyncAsync(
        HttpContext context,
        [FromServices] SyncService sync,
        [FromServices] ISyncTelemetry telemetry,
        [FromServices] ZaghlolMetrics metrics,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        var read = await StrictJson.ReadAsync<SyncRequest>(context);
        if (read.Value is not { } request)
        {
            telemetry.Request(SyncTags.Rejected);
            return read.Error!;
        }

        if (!TryValidate(request) || !TryReadAppVersion(context.Request.Headers[AppHeader], out var appVersion))
        {
            telemetry.Request(SyncTags.Rejected);
            return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        SyncResult result;
        try
        {
            result = await sync.SyncAsync(InstallTokenAuthentication.InstallIdOf(context.User), appVersion, ToData(request), cancellationToken);
        }
        catch (Exception ex) when (ex is SyncSourceUnavailableException || GlobalExceptionHandler.IsTransientDatabaseFailure(ex))
        {
            return Unavailable(context);
        }

        var nonce = context.TimeNonce();
        switch (result)
        {
            case SyncThrottled throttled:
                var answer = new SyncThrottledResponse
                {
                    ServerTime = throttled.ServerTime,
                    NextSyncNotBefore = throttled.NextSyncNotBefore,
                    TimeNonce = nonce,
                };
                return new AnchoredJsonResult(answer, JsonSerializer.SerializeToUtf8Bytes(answer, ApiJsonContext.Default.SyncThrottledResponse));

            case SyncCompleted completed:
                var response = ToResponse(completed, nonce);
                var bytes = JsonSerializer.SerializeToUtf8Bytes(response, ApiJsonContext.Default.SyncResponse);
                metrics.SyncResponse(bytes.Length, completed.UpToDate);
                return new AnchoredJsonResult(response, bytes);

            default:
                // The install was tombstoned after authentication: the same answer as an unknown token.
                context.Response.Headers.WWWAuthenticate = "Bearer";
                return ApiProblems.Of(StatusCodes.Status401Unauthorized, ErrorCodes.InstallTokenInvalid);
        }
    }

    /// <summary>Rules the JSON shape can't express: non-negative cursors and the per-call caps (the whole call, never truncation).</summary>
    internal static bool TryValidate(SyncRequest request) =>
        request.CatalogVersion >= 0
        && request.FlagsVersion >= 0
        && request.RegistryVersion is null or >= 0
        && (request.Contributions?.Count ?? 0) <= SyncRequest.MaxContributions
        && (request.BankRequests?.Count ?? 0) <= SyncRequest.MaxBankRequests;

    /// <summary>
    /// <c>Zaghlol-App: &lt;platform&gt;/&lt;appVersion&gt; (&lt;build&gt;)</c>, exactly one value of printable ASCII, at most 64
    /// characters, the app version in the OpenAPI <c>appVersion</c> form. Only the app version is used: the platform comes from
    /// the install row (a header that disagrees with it is ignored).
    /// </summary>
    internal static bool TryReadAppVersion(StringValues values, out string appVersion)
    {
        appVersion = string.Empty;
        if (values.Count != 1 || values[0] is not { Length: > 0 and <= AppHeaderMaxLength } header || !header.All(c => c is >= ' ' and <= '~'))
        {
            return false;
        }

        var match = AppHeaderRegex().Match(header);
        if (!match.Success)
        {
            return false;
        }

        appVersion = match.Groups["version"].Value;
        return true;
    }

    private static SyncRequestData ToData(SyncRequest request) => new(
        request.CatalogVersion,
        request.FlagsVersion,
        request.PricesAsOf,
        request.EntitlementIssuedAt,
        (request.Contributions ?? []).Select(c => new SyncContribution(c.MerchantNorm, c.InstitutionCode, c.CategoryCode)).ToList(),
        (request.BankRequests ?? []).Select(b => new SyncBankRequest(b.InstitutionName, b.Country, b.Channel)).ToList());

    private static SyncResponse ToResponse(SyncCompleted completed, string? nonce) => new()
    {
        ServerTime = completed.ServerTime,
        NextSyncNotBefore = completed.NextSyncNotBefore,
        Catalog = completed.Catalog is { } catalog
            ? new SyncCatalogDto
            {
                FromVersion = catalog.FromVersion,
                ToVersion = catalog.ToVersion,
                Mode = catalog.Mode,
                FullUrl = catalog.FullUrl,
                Ops = catalog.Ops,
            }
            : null,
        Flags = completed.Flags is { } flags ? new SyncFlagsDto { Version = flags.Version, Values = flags.Values } : null,
        Prices = completed.Prices is { } prices ? ToDto(prices) : null,
        Entitlement = completed.Entitlement.Entitlement is { } token ? new SyncEntitlementDto { Token = token } : null,
        Accepted = new SyncAcceptedDto { Contributions = completed.Accepted.Contributions, BankRequests = completed.Accepted.BankRequests },
        AccountToken = completed.Entitlement.AccountToken,
        SupportNotice = completed.Entitlement.SupportNotice,
        TimeNonce = nonce,
    };

    private static SyncPricesDto ToDto(PricesBlock prices) => new()
    {
        AsOf = SyncComposer.WholeSecond(prices.AsOf),
        Stale = prices.Stale,
        Gold = prices.Gold
            .Select(g => new SyncGoldPriceDto { Symbol = g.Symbol, Currency = g.Currency, Price = PriceWire.Format(g.Price) })
            .ToList(),
        Fx = new SyncFxDto
        {
            Base = prices.FxBaseCurrency,
            Rates = prices.Fx.ToDictionary(f => f.Quote, f => PriceWire.Format(f.Rate), StringComparer.Ordinal),
        },
    };

    private static IResult Unavailable(HttpContext context)
    {
        context.Response.Headers.RetryAfter = RetryAfterSeconds.ToString(CultureInfo.InvariantCulture);
        return TypedResults.Problem(
            statusCode: StatusCodes.Status503ServiceUnavailable,
            extensions: new Dictionary<string, object?> { ["code"] = ErrorCodes.UpstreamUnavailable, ["retryAfterSeconds"] = RetryAfterSeconds });
    }

    // The OpenAPI ZaghlolApp pattern ^(android|ios)/\S+ \(\S+\)$ with the version narrowed to InstallRequest.appVersion
    // (ASCII digits only; \z, so no trailing newline).
    [GeneratedRegex(@"^(?:android|ios)/(?<version>[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}(?:[-+][0-9A-Za-z.-]{1,32})?) \([!-~]+\)\z", RegexOptions.CultureInvariant)]
    private static partial Regex AppHeaderRegex();
}

/// <summary>
/// A signed endpoint's 200 whose JSON was serialized once by the handler (so its length feeds the size metric). Exposes the
/// body object, so <see cref="TimeNonceFilter"/> checks the echo, and writes the exact bytes through <c>Response.Body</c>.
/// </summary>
internal sealed class AnchoredJsonResult(IAnchoredResponse value, byte[] body) : IResult, IValueHttpResult, IStatusCodeHttpResult
{
    public object? Value => value;

    public int? StatusCode => StatusCodes.Status200OK;

    public Task ExecuteAsync(HttpContext httpContext) => new JsonBytesResult(body).ExecuteAsync(httpContext);
}
