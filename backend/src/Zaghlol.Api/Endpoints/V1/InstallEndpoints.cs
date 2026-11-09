using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Idempotency;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Api.RateLimiting;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Installs;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// <c>POST /v1/installs</c> (anonymous, rate limited per /24) and <c>DELETE /v1/installs/me</c> (install token), backend-api
/// §4.1 and §4.7. Registration never stores a response holding a token (R3-6).
/// </summary>
internal static partial class InstallEndpoints
{
    /// <summary>The OpenAPI <c>InstallRequest.appVersion</c> pattern, character for character (a contract test compares them).</summary>
    public const string AppVersionPattern = @"^\d{1,4}\.\d{1,4}\.\d{1,4}([-+][0-9A-Za-z.-]{1,32})?$";

    /// <summary>The OpenAPI <c>InstallRequest.appVersion</c> <c>maxLength</c>.</summary>
    public const int AppVersionMaxLength = 48;

    /// <summary>The OpenAPI <c>Platform</c> enum.</summary>
    public static IReadOnlyList<string> Platforms { get; } = ["android", "ios"];

    public static IEndpointRouteBuilder MapInstalls(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapPost("/v1/installs", RegisterAsync)
            .WithName("registerInstall")
            .WithMetadata(RegistrationRateLimitMetadata.Instance);

        endpoints.MapInstallScoped().MapDelete("/installs/me", DeleteAsync).WithName("deleteInstall");
        return endpoints;
    }

    /// <summary>The <c>/v1</c> group whose every endpoint requires the install token (T-128+ map theirs here too).</summary>
    public static RouteGroupBuilder MapInstallScoped(this IEndpointRouteBuilder endpoints) =>
        endpoints.MapGroup("/v1").RequireInstallToken();

    private static async Task<IResult> RegisterAsync(
        HttpContext context,
        [FromServices] IInstallStore installs,
        [FromServices] TimeProvider clock,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        if (!IdempotencyKeys.TryRead(context.Request.Headers, out var key))
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        var body = await StrictJson.ReadBodyAsync(context);
        if (body.Error is not null)
        {
            return body.Error;
        }

        var read = StrictJson.Deserialize<InstallRequest>(body.Bytes);
        if (read.Value is not { } request)
        {
            return read.Error!;
        }

        if (!TryValidate(request, out var platform))
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        await InstallLogHash.SetAsync(context, request.InstallId);

        var token = InstallTokens.Generate();
        var now = clock.GetUtcNow();
        var outcome = await installs.RegisterAsync(
            request.InstallId,
            platform,
            request.AppVersion,
            InstallTokens.Hash(token),
            SHA256.HashData(Encoding.ASCII.GetBytes(key)),
            SHA256.HashData(body.Bytes.Span),
            now,
            cancellationToken);

        return outcome switch
        {
            RegistrationOutcome.Created or RegistrationOutcome.Reissued => TypedResults.Json(
                new InstallResponse(new Sensitive<string>(token), TruncateToSecond(now)),
                ApiJsonContext.Default.InstallResponse,
                statusCode: StatusCodes.Status201Created),
            RegistrationOutcome.KeyReused => ApiProblems.Of(StatusCodes.Status409Conflict, ErrorCodes.IdempotencyKeyReused),
            _ => ApiProblems.Of(StatusCodes.Status409Conflict, ErrorCodes.InstallExists),
        };
    }

    private static async Task<IResult> DeleteAsync(
        HttpContext context,
        [FromServices] IInstallStore installs,
        [FromServices] TimeProvider clock,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        await installs.DeleteAsync(InstallTokenAuthentication.InstallIdOf(context.User), clock.GetUtcNow(), cancellationToken);
        return TypedResults.StatusCode(StatusCodes.Status202Accepted);
    }

    /// <summary>Field rules the JSON shape can't express (OpenAPI <c>InstallRequest</c>).</summary>
    internal static bool TryValidate(InstallRequest request, out Platform platform)
    {
        platform = default;
        // Printable ASCII first: .NET's \d also matches non-ASCII digits, and $ allows a trailing newline.
        if (request.AppVersion.Length > AppVersionMaxLength
            || !request.AppVersion.All(c => c is >= '!' and <= '~')
            || !AppVersion().IsMatch(request.AppVersion))
        {
            return false;
        }

        switch (request.Platform)
        {
            case "android":
                platform = Platform.Android;
                return true;
            case "ios":
                platform = Platform.Ios;
                return true;
            default:
                return false;
        }
    }

    private static DateTimeOffset TruncateToSecond(DateTimeOffset value)
    {
        var utc = value.ToUniversalTime();
        return new DateTimeOffset(utc.Ticks - (utc.Ticks % TimeSpan.TicksPerSecond), TimeSpan.Zero);
    }

    [GeneratedRegex(AppVersionPattern, RegexOptions.CultureInvariant)]
    private static partial Regex AppVersion();
}
