using Zaghlol.Api.Problems;
using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// The OpenAPI <c>ZaghlolApp</c> parameter is <c>required: true</c> on every <c>/v1</c> app operation (BUG-004): a missing,
/// repeated or malformed <c>Zaghlol-App</c> header is <c>400 VALIDATION_FAILED</c> for the whole call, in the one form
/// <see cref="SyncEndpoints.TryReadAppVersion"/> accepts. It runs after authentication, so a missing or bad token is still
/// <c>401</c>; the header value is never echoed.
/// </summary>
internal sealed class AppHeaderFilter : IEndpointFilter
{
    public static AppHeaderFilter Instance { get; } = new();

    public ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context, EndpointFilterDelegate next)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(next);

        return SyncEndpoints.TryReadAppVersion(context.HttpContext.Request.Headers[SyncEndpoints.AppHeader], out _)
            ? next(context)
            : ValueTask.FromResult<object?>(ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed));
    }
}

internal static class AppHeaderEndpointExtensions
{
    /// <summary>Requires a valid <c>Zaghlol-App</c> header on every endpoint of the group or on the endpoint.</summary>
    public static TBuilder RequireAppHeader<TBuilder>(this TBuilder builder)
        where TBuilder : IEndpointConventionBuilder =>
        builder.AddEndpointFilter(AppHeaderFilter.Instance);
}
