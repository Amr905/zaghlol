using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Api.RateLimiting;
using Zaghlol.Application.Support;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Observability;

namespace Zaghlol.Api.Endpoints.Admin;

/// <summary>
/// <c>POST /admin/v1/support/entitlement:lookup</c> (backend-api §5.2, T-136), role <c>support_viewer</c>. The key travels
/// only in the body: <c>{installId}</c> or <c>{email}</c>, exactly one. Any other member is <c>400 UNKNOWN_FIELD</c>; both,
/// neither, a duplicate, a non-string or a malformed key is <c>400 VALIDATION_FAILED</c>, and no problem body echoes it.
/// Every call is audited (<c>support_lookup</c>), counts <c>zaghlol.support.lookup</c> and draws on the per-operator lookup
/// bucket. An e-mail that matches no account answers <c>200</c> with no purchases after the same queries as a match. The
/// three support writes (<c>seat:move</c>, <c>purchase:detach</c>, <c>purchase:unfreeze</c>) are T-186's.
/// </summary>
internal static class SupportAdminEndpoints
{
    public static IEndpointRouteBuilder MapSupportAdmin(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        var group = endpoints.MapGroup("/admin/v1/support");
        group.MapPost("/entitlement:lookup", LookupAsync)
            .RequireOperatorRole(OperatorRoles.SupportViewer)
            .WithMetadata(SupportLookupRateLimitMetadata.Instance)
            .WithName("adminLookupEntitlement");
        return endpoints;
    }

    private static async Task<IResult> LookupAsync(
        HttpContext context,
        [FromServices] ISupportLookupStore store,
        [FromServices] ZaghlolMetrics metrics,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";
        var body = await StrictJson.ReadBodyAsync(context);
        if (body.Error is not null)
        {
            return body.Error;
        }

        var key = SupportLookupKey.Parse(body.Bytes);
        if (key.Error is { } code)
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, code);
        }

        var operatorId = OperatorAuthentication.OperatorIdOf(context.User);
        var view = key.Install is { } installId
            ? await store.LookupInstallAsync(operatorId, installId, cancellationToken)
            : await store.LookupEmailAsync(operatorId, key.Email!, cancellationToken);
        metrics.SupportLookup(OperatorRoles.SupportViewer);
        return TypedResults.Json(ToDto(view), ApiJsonContext.Default.SupportEntitlementDto);
    }

    private static SupportEntitlementDto ToDto(SupportEntitlementView view) => new(
        view.Status,
        [.. view.Purchases.Select(p => new SupportPurchaseDto(
            p.PurchaseId,
            p.Plan,
            p.State,
            p.Store,
            p.Seat,
            p.AccountLinked,
            p.LinkedBy,
            p.LastMovedAt,
            p.NextMoveAt,
            p.PendingClaimants,
            p.BuyingInstallSilent,
            p.IsBuyingInstall,
            p.DisputeFrozenUntil,
            p.RebindsLast30Days))],
        view.Plan,
        view.Exp,
        view.GraceUntil);
}

/// <summary>The parsed lookup body: an install ID, a normalised e-mail, or the error code to answer.</summary>
internal readonly record struct SupportLookupKey(InstallId? Install, string? Email, string? Error)
{
    public const string InstallIdMember = "installId";
    public const string EmailMember = "email";

    private const int MaxDepth = 4;

    // Never rendered with the e-mail (debuggers, accidental logging).
    public override string ToString() => nameof(SupportLookupKey);

    public static SupportLookupKey Parse(ReadOnlyMemory<byte> utf8)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(utf8, new JsonDocumentOptions { MaxDepth = MaxDepth });
        }
        catch (JsonException)
        {
            return Invalid;
        }

        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return Invalid;
            }

            var members = root.EnumerateObject().ToList();
            if (members.Exists(m => m.Name is not (InstallIdMember or EmailMember)))
            {
                return new SupportLookupKey(null, null, ErrorCodes.UnknownField);
            }

            if (members.Count != 1 || members[0].Value.ValueKind != JsonValueKind.String)
            {
                return Invalid;
            }

            var member = members[0];
            if (string.Equals(member.Name, InstallIdMember, StringComparison.Ordinal))
            {
                return InstallId.TryParse(member.Value.GetString(), out var installId)
                    ? new SupportLookupKey(installId, null, null)
                    : Invalid;
            }

            return SupportEmail.TryNormalize(member.Value.GetString(), out var email)
                ? new SupportLookupKey(null, email, null)
                : Invalid;
        }
    }

    private static SupportLookupKey Invalid => new(null, null, ErrorCodes.ValidationFailed);
}
