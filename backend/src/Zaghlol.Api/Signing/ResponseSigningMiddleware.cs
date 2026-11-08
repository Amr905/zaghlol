using Microsoft.AspNetCore.Http.Features;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Api.Signing;

/// <summary>Endpoint metadata: sign this endpoint's 200 responses (<see cref="ResponseSigningMiddleware"/>).</summary>
internal sealed class RequireResponseSignatureMetadata
{
    public static readonly RequireResponseSignatureMetadata Instance = new();

    private RequireResponseSignatureMetadata()
    {
    }
}

internal static class ResponseSigningEndpointExtensions
{
    /// <summary>
    /// Every 200 of this endpoint carries <c>Zaghlol-Signature</c> over the exact body bytes. Applied to the six anchoring
    /// operations and <c>GET /v1/catalog/{version}/full</c> by their owning tasks.
    /// </summary>
    public static TBuilder RequireResponseSignature<TBuilder>(this TBuilder builder)
        where TBuilder : IEndpointConventionBuilder =>
        builder.WithMetadata(RequireResponseSignatureMetadata.Instance);
}

/// <summary>
/// Buffers the body of endpoints marked <see cref="ResponseSigningEndpointExtensions.RequireResponseSignature{TBuilder}"/>
/// and, on status 200, signs the exact bytes with the active Sync key (T-123 design note). Runs after routing and before
/// the endpoints, inside any response compression, so it signs uncompressed bytes. Both <c>Body</c> and
/// <c>BodyWriter</c> writes land in the buffer and an early <c>StartAsync</c> or flush can't commit headers. Over
/// <see cref="MaxBufferedBytes"/> the request fails with 500; a downstream exception discards the buffer. Nothing
/// unsigned is ever streamed for a 200 of a signed endpoint.
/// </summary>
internal sealed class ResponseSigningMiddleware(RequestDelegate next, ISigner signer)
{
    public const string HeaderName = "Zaghlol-Signature";
    public const int MaxBufferedBytes = 1024 * 1024;

    public async Task InvokeAsync(HttpContext context)
    {
        if (context.GetEndpoint()?.Metadata.GetMetadata<RequireResponseSignatureMetadata>() is null)
        {
            await next(context);
            return;
        }

        var original = context.Features.GetRequiredFeature<IHttpResponseBodyFeature>();
        await using var buffer = new CappedBufferStream(MaxBufferedBytes);
        var buffered = new StreamResponseBodyFeature(buffer);
        context.Features.Set<IHttpResponseBodyFeature>(buffered);
        try
        {
            await next(context);

            // Flushes anything still in the BodyWriter pipe into the buffer.
            await buffered.CompleteAsync();
        }
        finally
        {
            context.Features.Set(original);
        }

        // A handler can never supply its own signature.
        context.Response.Headers.Remove(HeaderName);
        var body = buffer.Written;
        if (context.Response.StatusCode == StatusCodes.Status200OK)
        {
            var signature = await signer.SignAsync(SigningPurpose.Sync, body, context.RequestAborted);
            context.Response.Headers[HeaderName] = signature.HeaderValue;
        }

        else if (body.IsEmpty)
        {
            // A bodiless 4xx/5xx (NotFound(), Unauthorized()) stays untouched: no Content-Length, so the status-code
            // pages middleware outside can still write the RFC 9457 problem body.
            return;
        }

        context.Response.ContentLength = body.Length;
        if (body.Length > 0)
        {
            await original.Writer.WriteAsync(body, context.RequestAborted);
        }
    }
}

/// <summary>A signed endpoint wrote more than the 1 MiB signing buffer. Maps to <c>500 INTERNAL</c>.</summary>
public sealed class ResponseTooLargeToSignException : Exception
{
    public const string DefaultMessage = "The response is too large to sign.";

    public ResponseTooLargeToSignException()
        : base(DefaultMessage)
    {
    }

    public ResponseTooLargeToSignException(string message)
        : base(message)
    {
    }

    public ResponseTooLargeToSignException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>A memory buffer that throws <see cref="ResponseTooLargeToSignException"/> past its cap.</summary>
internal sealed class CappedBufferStream(int cap) : MemoryStream
{
    public ReadOnlyMemory<byte> Written => new(GetBuffer(), 0, (int)Length);

    public override void Write(byte[] buffer, int offset, int count)
    {
        Reserve(count);
        base.Write(buffer, offset, count);
    }

    public override void Write(ReadOnlySpan<byte> buffer)
    {
        Reserve(buffer.Length);
        base.Write(buffer);
    }

    public override void WriteByte(byte value)
    {
        Reserve(1);
        base.WriteByte(value);
    }

    public override Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
    {
        Reserve(count);
        return base.WriteAsync(buffer, offset, count, cancellationToken);
    }

    public override ValueTask WriteAsync(ReadOnlyMemory<byte> buffer, CancellationToken cancellationToken = default)
    {
        Reserve(buffer.Length);
        return base.WriteAsync(buffer, cancellationToken);
    }

    public override IAsyncResult BeginWrite(byte[] buffer, int offset, int count, AsyncCallback? callback, object? state)
    {
        Reserve(count);
        return base.BeginWrite(buffer, offset, count, callback, state);
    }

    private void Reserve(int count)
    {
        if (Position + count > cap)
        {
            KmsMetrics.ResponseTooLargeToSign();
            throw new ResponseTooLargeToSignException();
        }
    }
}
