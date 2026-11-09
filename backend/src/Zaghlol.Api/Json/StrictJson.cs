using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;
using Microsoft.Net.Http.Headers;
using Zaghlol.Api.Problems;
using Zaghlol.Domain;

namespace Zaghlol.Api.Json;

/// <summary>The request body bytes, read once per request and shared by the idempotency filter and the handler.</summary>
internal sealed class RequestBodyFeature(ReadOnlyMemory<byte> bytes)
{
    public ReadOnlyMemory<byte> Bytes { get; } = bytes;

    // Never render the body (debuggers, accidental logging of the feature collection).
    public override string ToString() => nameof(RequestBodyFeature);
}

/// <summary>The body bytes, or the problem to answer instead (413, 415).</summary>
internal readonly record struct BodyRead(ReadOnlyMemory<byte> Bytes, IResult? Error);

/// <summary>A deserialized body, or the problem to answer instead (400 <c>UNKNOWN_FIELD</c> or <c>VALIDATION_FAILED</c>).</summary>
internal readonly record struct StrictRead<T>(T? Value, IResult? Error)
    where T : class;

/// <summary>
/// The strict DTO policy for every Zaghlol-defined body (backend-api §1, BR-SYNC-03): <c>application/json</c> only
/// (<c>415</c>), at most 64 KB (<c>413</c>), source-generated metadata, unmapped members disallowed, case-sensitive names,
/// no duplicate names, <c>required</c> and non-nullable members enforced, numbers never read from strings. When the
/// deserializer rejects a body, a probe walks the parsed JSON against the type metadata: an unmapped name anywhere
/// (nested objects and arrays included) is <c>400 UNKNOWN_FIELD</c>, anything else <c>400 VALIDATION_FAILED</c>. Problem
/// bodies never echo a field name or value. The open third-party bodies (T-133/134/135) use a separate path.
/// </summary>
internal static class StrictJson
{
    public const int MaxBodyBytes = 64 * 1024;

    private const int MaxDepth = 32;

    public static JsonSerializerOptions Options { get; } = CreateOptions();

    /// <summary>Reads the body once (cached in <see cref="RequestBodyFeature"/>).</summary>
    public static async ValueTask<BodyRead> ReadBodyAsync(HttpContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        if (context.Features.Get<RequestBodyFeature>() is { } cached)
        {
            return new BodyRead(cached.Bytes, null);
        }

        var request = context.Request;
        if (!IsJson(request.ContentType))
        {
            return new BodyRead(default, ApiProblems.Of(StatusCodes.Status415UnsupportedMediaType, ErrorCodes.UnsupportedMediaType));
        }

        if (request.ContentLength > MaxBodyBytes)
        {
            return new BodyRead(default, ApiProblems.Of(StatusCodes.Status413PayloadTooLarge, ErrorCodes.PayloadTooLarge));
        }

        using var buffer = new MemoryStream();
        var chunk = new byte[8192];
        int read;
        while ((read = await request.Body.ReadAsync(chunk, context.RequestAborted)) > 0)
        {
            if (buffer.Length + read > MaxBodyBytes)
            {
                return new BodyRead(default, ApiProblems.Of(StatusCodes.Status413PayloadTooLarge, ErrorCodes.PayloadTooLarge));
            }

            await buffer.WriteAsync(chunk.AsMemory(0, read), context.RequestAborted);
        }

        var bytes = new ReadOnlyMemory<byte>(buffer.ToArray());
        context.Features.Set(new RequestBodyFeature(bytes));
        return new BodyRead(bytes, null);
    }

    /// <summary>Deserializes <paramref name="utf8"/> as <typeparamref name="T"/> under the strict policy.</summary>
    public static StrictRead<T> Deserialize<T>(ReadOnlyMemory<byte> utf8)
        where T : class
    {
        var info = (JsonTypeInfo<T>)Options.GetTypeInfo(typeof(T));
        try
        {
            var value = JsonSerializer.Deserialize(utf8.Span, info);
            return value is null ? Invalid<T>() : new StrictRead<T>(value, null);
        }
        catch (JsonException)
        {
            return HasUnknownMember(utf8, info)
                ? new StrictRead<T>(null, ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.UnknownField))
                : Invalid<T>();
        }
    }

    /// <summary>Reads and deserializes the body: 415, 413 or 400 as <see cref="StrictRead{T}.Error"/>.</summary>
    public static async ValueTask<StrictRead<T>> ReadAsync<T>(HttpContext context)
        where T : class
    {
        var body = await ReadBodyAsync(context);
        return body.Error is not null ? new StrictRead<T>(null, body.Error) : Deserialize<T>(body.Bytes);
    }

    /// <summary>True when any object in <paramref name="utf8"/> has a member its metadata doesn't declare.</summary>
    internal static bool HasUnknownMember(ReadOnlyMemory<byte> utf8, JsonTypeInfo info)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(utf8, new JsonDocumentOptions { MaxDepth = MaxDepth });
        }
        catch (JsonException)
        {
            return false;
        }

        using (document)
        {
            return Walk(document.RootElement, info, 0);
        }
    }

    private static bool Walk(JsonElement element, JsonTypeInfo info, int depth)
    {
        if (depth > MaxDepth)
        {
            return false;
        }

        if (info.Kind == JsonTypeInfoKind.Object && element.ValueKind == JsonValueKind.Object)
        {
            foreach (var member in element.EnumerateObject())
            {
                var property = info.Properties.FirstOrDefault(p => string.Equals(p.Name, member.Name, StringComparison.Ordinal));
                if (property is null || Walk(member.Value, info.Options.GetTypeInfo(property.PropertyType), depth + 1))
                {
                    return true;
                }
            }
        }
        else if (info.Kind == JsonTypeInfoKind.Enumerable && element.ValueKind == JsonValueKind.Array && info.ElementType is { } elementType)
        {
            var elementInfo = info.Options.GetTypeInfo(elementType);
            foreach (var item in element.EnumerateArray())
            {
                if (Walk(item, elementInfo, depth + 1))
                {
                    return true;
                }
            }
        }

        return false;
    }

    private static StrictRead<T> Invalid<T>()
        where T : class =>
        new(null, ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed));

    private static bool IsJson(string? contentType)
    {
        if (!MediaTypeHeaderValue.TryParse(contentType, out var parsed)
            || !parsed.MediaType.Equals("application/json", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        return !parsed.Charset.HasValue || parsed.Charset.Equals("utf-8", StringComparison.OrdinalIgnoreCase);
    }

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions(ApiJsonContext.Default.Options)
        {
            UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
            PropertyNameCaseInsensitive = false,
            AllowDuplicateProperties = false,
            RespectNullableAnnotations = true,
            RespectRequiredConstructorParameters = true,
            NumberHandling = JsonNumberHandling.Strict,
            AllowTrailingCommas = false,
            ReadCommentHandling = JsonCommentHandling.Disallow,
            MaxDepth = MaxDepth,
        };
        options.MakeReadOnly();
        return options;
    }
}
