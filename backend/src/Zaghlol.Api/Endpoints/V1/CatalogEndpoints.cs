using System.IO.Compression;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Mvc;
using Zaghlol.Api.Problems;
using Zaghlol.Api.Signing;
using Zaghlol.Application.Catalog;
using Zaghlol.Domain;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// <c>GET /v1/catalog/{version}/full</c> (backend-api §4.8): the immutable signed snapshot <c>{version, ops[]}</c> of one
/// published version. Anonymous (the catalog is public; a CDN caches it) and rate limited per client network. It serves the
/// stored snapshot, not a rebuild from the live tables, because a later publish changes the live rows. The stored bytes are
/// checked against the hash recorded at publish; the response signature comes from the signing middleware over the exact
/// bytes sent, with a buffer sized for a whole catalog (T-123 I-5).
/// </summary>
internal static class CatalogEndpoints
{
    public static IEndpointRouteBuilder MapCatalog(this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapGet("/v1/catalog/{version:int}/full", GetFullAsync)
            .WithName("getFullCatalog")
            .RequireResponseSignature(CatalogLimits.MaxSnapshotBytes);
        return endpoints;
    }

    private static async Task<IResult> GetFullAsync(
        HttpContext context,
        int version,
        [FromServices] ICatalogReader reader,
        [FromServices] ICatalogSnapshotStore store,
        CancellationToken cancellationToken)
    {
        var info = version < 1 ? null : await reader.FindVersionAsync(version, cancellationToken);
        if (info is null)
        {
            return ApiProblems.Of(StatusCodes.Status404NotFound, ErrorCodes.CatalogVersionUnknown);
        }

        var stored = await store.GetAsync(version, cancellationToken) ?? throw new CatalogSnapshotCorruptException();
        var json = await DecompressAsync(stored, cancellationToken);
        if (!CryptographicOperations.FixedTimeEquals(SHA256.HashData(json), info.Sha256.Span))
        {
            throw new CatalogSnapshotCorruptException();
        }

        // A published version never changes, so shared caches may keep it for good.
        context.Response.Headers.CacheControl = "public, max-age=31536000, immutable";
        return new JsonBytesResult(json);
    }

    private static async Task<byte[]> DecompressAsync(byte[] gzip, CancellationToken cancellationToken)
    {
        using var input = new MemoryStream(gzip);
        using var decompressor = new GZipStream(input, CompressionMode.Decompress);
        using var output = new MemoryStream();
        var chunk = new byte[16 * 1024];
        int read;
        while ((read = await decompressor.ReadAsync(chunk, cancellationToken)) > 0)
        {
            if (output.Length + read > CatalogLimits.MaxSnapshotBytes)
            {
                throw new CatalogSnapshotCorruptException();
            }

            await output.WriteAsync(chunk.AsMemory(0, read), cancellationToken);
        }

        return output.ToArray();
    }
}
