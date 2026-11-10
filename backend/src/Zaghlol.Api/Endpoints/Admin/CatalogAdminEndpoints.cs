using System.Globalization;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Json;
using Zaghlol.Api.Problems;
using Zaghlol.Application.Catalog;
using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints.Admin;

/// <summary>
/// The catalog admin operations of backend-api §5.1 and §5.2, all behind the <c>catalog_editor</c> policy and never cached.
/// Keys are validated before anything else (<c>400 VALIDATION_FAILED</c>), then the body under the strict DTO policy. No route
/// uses the idempotency filter (FU-052 S-2): <c>PUT</c> and <c>DELETE</c> are idempotent by key, and a repeated
/// <c>POST</c> create or publish is refused or harmless (publish with nothing changed is <c>409</c>).
/// </summary>
internal static class CatalogAdminEndpoints
{
    public const int DefaultPageSize = 100;
    public const int MaxPageSize = 500;

    public static IEndpointRouteBuilder MapCatalogAdmin(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        var group = endpoints.MapGroup("/admin/v1/catalog").RequireOperatorRole(OperatorRoles.CatalogEditor);
        group.MapGet("/draft/{entity}", ListAsync).WithName("adminListCatalogDraft");
        group.MapPost("/draft/{entity}", CreateMerchantAsync).WithName("adminCreateDraftMerchant");
        group.MapPut("/draft/{entity}/{id}", PutAsync).WithName("adminPutCatalogDraftEntry");
        group.MapDelete("/draft/{entity}/{id}", DeleteAsync).WithName("adminDeleteCatalogDraftEntry");
        group.MapPost("/publish", PublishAsync).WithName("adminPublishCatalog");
        return endpoints;
    }

    private static async Task<IResult> ListAsync(
        HttpContext context,
        string entity,
        [FromServices] ICatalogAdminStore store,
        CancellationToken cancellationToken)
    {
        NoStore(context);
        if (!CatalogEntities.TryParse(entity, out var kind)
            || !TryQueryInt(context, "cursor", 0, 0, int.MaxValue, out var cursor)
            || !TryQueryInt(context, "limit", DefaultPageSize, 1, MaxPageSize, out var limit))
        {
            return Invalid();
        }

        var page = await store.ListAsync(kind, cursor, limit, cancellationToken);
        return new JsonBytesResult(CatalogJson.Page(page.Items, page.NextCursor));
    }

    private static async Task<IResult> CreateMerchantAsync(
        HttpContext context,
        string entity,
        [FromServices] ICatalogAdminStore store,
        CancellationToken cancellationToken)
    {
        NoStore(context);
        if (!string.Equals(entity, CatalogEntities.Name(CatalogEntity.Merchants), StringComparison.Ordinal))
        {
            return Invalid();
        }

        var body = await ReadFieldsAsync(context, CatalogEntity.Merchants);
        if (body.Fields is not { } fields)
        {
            return body.Error!;
        }

        var change = await store.CreateMerchantAsync(OperatorAuthentication.OperatorIdOf(context.User), fields, cancellationToken);
        return Respond(change, StatusCodes.Status201Created);
    }

    private static async Task<IResult> PutAsync(
        HttpContext context,
        string entity,
        string id,
        [FromServices] ICatalogAdminStore store,
        CancellationToken cancellationToken)
    {
        NoStore(context);
        if (!CatalogEntities.TryParse(entity, out var kind) || !CatalogKeys.TryParse(kind, id, out var key))
        {
            return Invalid();
        }

        var body = await ReadFieldsAsync(context, kind);
        if (body.Fields is not { } fields)
        {
            return body.Error!;
        }

        var change = await store.PutAsync(OperatorAuthentication.OperatorIdOf(context.User), key, fields, cancellationToken);
        return Respond(change, StatusCodes.Status200OK);
    }

    private static async Task<IResult> DeleteAsync(
        HttpContext context,
        string entity,
        string id,
        [FromServices] ICatalogAdminStore store,
        CancellationToken cancellationToken)
    {
        NoStore(context);
        if (!CatalogEntities.TryParse(entity, out var kind) || !CatalogKeys.TryParse(kind, id, out var key))
        {
            return Invalid();
        }

        var change = await store.DeleteAsync(OperatorAuthentication.OperatorIdOf(context.User), key, cancellationToken);
        return change.Status == DraftStatus.Ok ? TypedResults.NoContent() : Respond(change, StatusCodes.Status204NoContent);
    }

    private static async Task<IResult> PublishAsync(
        HttpContext context,
        [FromServices] ICatalogAdminStore store,
        CancellationToken cancellationToken)
    {
        NoStore(context);
        var read = await StrictJson.ReadAsync<CatalogPublishRequest>(context);
        if (read.Value is not { } request)
        {
            return read.Error!;
        }

        if (!CatalogValidation.IsValidNote(request.Note))
        {
            return Invalid();
        }

        var result = await store.PublishAsync(OperatorAuthentication.OperatorIdOf(context.User), request.Note, cancellationToken);
        if (result.NothingToPublish)
        {
            return ApiProblems.Of(StatusCodes.Status409Conflict, ErrorCodes.AdminConflict);
        }

        return TypedResults.Json(
            new CatalogPublishResponse(result.Version, result.PublishedAt, result.SnapshotUrl!.AbsoluteUri),
            ApiJsonContext.Default.CatalogPublishResponse);
    }

    private static IResult Respond(DraftChange change, int successStatus) => change.Status switch
    {
        DraftStatus.NotFound => ApiProblems.Of(StatusCodes.Status404NotFound, ErrorCodes.NotFound),
        DraftStatus.Conflict => ApiProblems.Of(StatusCodes.Status409Conflict, ErrorCodes.AdminConflict),
        _ => new JsonBytesResult(CatalogJson.OfOp(change.Op!), successStatus),
    };

    private static ProblemHttpResult Invalid() => ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);

    private static void NoStore(HttpContext context) => context.Response.Headers.CacheControl = "no-store";

    /// <summary>A single optional query parameter holding only ASCII digits within the range, else invalid.</summary>
    private static bool TryQueryInt(HttpContext context, string name, int fallback, int min, int max, out int value)
    {
        value = fallback;
        if (!context.Request.Query.TryGetValue(name, out var values))
        {
            return true;
        }

        return values.Count == 1
            && int.TryParse(values[0], NumberStyles.None, CultureInfo.InvariantCulture, out value)
            && value >= min
            && value <= max;
    }

    /// <summary>Reads and validates the body that belongs to <paramref name="entity"/> and maps it to the stored fields.</summary>
    private static async Task<(CatalogFields? Fields, IResult? Error)> ReadFieldsAsync(HttpContext context, CatalogEntity entity)
    {
        var (fields, error) = entity switch
        {
            CatalogEntity.Categories => await ReadCategoryAsync(context),
            CatalogEntity.Merchants => await ReadMerchantAsync(context),
            CatalogEntity.Aliases => await ReadAliasAsync(context),
            _ => await ReadKeywordAsync(context),
        };
        if (fields is null)
        {
            return (null, error);
        }

        return CatalogValidation.IsValid(entity, fields) ? (fields, null) : (null, Invalid());
    }

    private static async Task<(CatalogFields? Fields, IResult? Error)> ReadCategoryAsync(HttpContext context)
    {
        var read = await StrictJson.ReadAsync<CategoryDraftRequest>(context);
        return read.Value is not { } body
            ? (null, read.Error)
            : (new CatalogFields
            {
                NameAr = body.NameAr,
                NameEn = body.NameEn,
                Icon = body.Icon,
                Color = body.Color,
                Bucket = body.Bucket,
                Sort = body.Sort,
            }, null);
    }

    private static async Task<(CatalogFields? Fields, IResult? Error)> ReadMerchantAsync(HttpContext context)
    {
        var read = await StrictJson.ReadAsync<MerchantDraftRequest>(context);
        return read.Value is not { } body
            ? (null, read.Error)
            : (new CatalogFields { Canonical = body.Canonical, NameAr = body.NameAr, Category = body.Category }, null);
    }

    private static async Task<(CatalogFields? Fields, IResult? Error)> ReadAliasAsync(HttpContext context)
    {
        var read = await StrictJson.ReadAsync<AliasDraftRequest>(context);
        return read.Value is not { } body ? (null, read.Error) : (new CatalogFields { Match = body.Match }, null);
    }

    private static async Task<(CatalogFields? Fields, IResult? Error)> ReadKeywordAsync(HttpContext context)
    {
        var read = await StrictJson.ReadAsync<KeywordDraftRequest>(context);
        return read.Value is not { } body
            ? (null, read.Error)
            : (new CatalogFields { Category = body.Category, Weight = body.Weight }, null);
    }
}
