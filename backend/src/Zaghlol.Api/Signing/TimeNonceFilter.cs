using Microsoft.Extensions.Primitives;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Api.Signing;

/// <summary>The request's <c>Zaghlol-Time-Nonce</c>, set by <see cref="TimeNonceFilter"/>; <c>null</c> when absent.</summary>
internal interface ITimeNonceFeature
{
    string? Value { get; }
}

/// <summary>
/// A 200 body of an anchoring operation. Implementations serialize <see cref="TimeNonce"/> with
/// <c>[JsonIgnore(Condition = JsonIgnoreCondition.Never)]</c>, so <c>null</c> is written explicitly.
/// </summary>
internal interface IAnchoredResponse
{
    string? TimeNonce { get; }
}

internal sealed class TimeNonceFeature(string? value) : ITimeNonceFeature
{
    public string? Value { get; } = value;

    // Never render the value (debuggers, accidental logging of the feature collection).
    public override string ToString() => nameof(TimeNonceFeature);
}

/// <summary>
/// R4-2 (backend-api §1): validates <c>Zaghlol-Time-Nonce</c> for the six anchoring operations and exposes it to the
/// handler only through <see cref="ITimeNonceFeature"/>. Never stored, logged, traced or put in problem bodies.
/// Registered first among endpoint filters (<see cref="TimeNonceEndpointExtensions.WithTimeNonce"/>), ahead of
/// idempotency, so a malformed nonce is always 400 and never a replay. After the handler, a typed 200 result (or one with
/// no status code, such as <c>TypedResults.Json</c>, which writes 200) whose
/// <see cref="IAnchoredResponse.TimeNonce"/> differs from the request fails closed (500). Raw replay results are exempt.
/// </summary>
internal sealed class TimeNonceFilter : IEndpointFilter
{
    public const string HeaderName = "Zaghlol-Time-Nonce";

    public static readonly TimeNonceFilter Instance = new();

    private TimeNonceFilter()
    {
    }

    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context, EndpointFilterDelegate next)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(next);

        var http = context.HttpContext;
        if (!TryRead(http.Request.Headers[HeaderName], out var nonce))
        {
            return TypedResults.Problem(
                statusCode: StatusCodes.Status400BadRequest,
                extensions: new Dictionary<string, object?> { ["code"] = ErrorCodes.ValidationFailed });
        }

        http.Features.Set<ITimeNonceFeature>(new TimeNonceFeature(nonce));
        var result = await next(context);
        if (Anchored(result) is { } anchored && !string.Equals(anchored.TimeNonce, nonce, StringComparison.Ordinal))
        {
            KmsMetrics.TimeNonceEchoMismatch();
            throw new TimeNonceMismatchException();
        }

        return result;
    }

    /// <summary>Absent: <c>null</c>. Otherwise exactly one value matching <c>^[A-Za-z0-9_-]{21}[AQgw]$</c> (16 bytes, canonical).</summary>
    internal static bool TryRead(StringValues values, out string? nonce)
    {
        nonce = null;
        if (values.Count == 0)
        {
            return true;
        }

        if (values.Count != 1 || !IsCanonical(values[0]))
        {
            return false;
        }

        nonce = values[0];
        return true;
    }

    internal static bool IsCanonical(string? value)
    {
        if (value is null || value.Length != 22)
        {
            return false;
        }

        for (var i = 0; i < 21; i++)
        {
            if (!IsBase64UrlChar(value[i]))
            {
                return false;
            }
        }

        return value[21] is 'A' or 'Q' or 'g' or 'w';
    }

    private static bool IsBase64UrlChar(char c) => c is (>= 'A' and <= 'Z') or (>= 'a' and <= 'z') or (>= '0' and <= '9') or '-' or '_';

    private static IAnchoredResponse? Anchored(object? result)
    {
        while (result is INestedHttpResult nested)
        {
            result = nested.Result;
        }

        return result switch
        {
            IValueHttpResult { Value: IAnchoredResponse value } and IStatusCodeHttpResult { StatusCode: null or StatusCodes.Status200OK } => value,
            IAnchoredResponse direct => direct,
            _ => null,
        };
    }
}

internal static class TimeNonceEndpointExtensions
{
    /// <summary>Adds <see cref="TimeNonceFilter"/>. Call it before any other endpoint filter.</summary>
    public static RouteHandlerBuilder WithTimeNonce(this RouteHandlerBuilder builder) =>
        builder.AddEndpointFilter(TimeNonceFilter.Instance);

    /// <summary>The validated <c>Zaghlol-Time-Nonce</c> of this request; <c>null</c> when it had none.</summary>
    public static string? TimeNonce(this HttpContext context) => context.Features.Get<ITimeNonceFeature>()?.Value;
}

/// <summary>A handler's anchored 200 body didn't echo the request's time nonce. Maps to <c>500 INTERNAL</c>.</summary>
public sealed class TimeNonceMismatchException : Exception
{
    public const string DefaultMessage = "The anchored response does not echo the request's time nonce.";

    public TimeNonceMismatchException()
        : base(DefaultMessage)
    {
    }

    public TimeNonceMismatchException(string message)
        : base(message)
    {
    }

    public TimeNonceMismatchException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
