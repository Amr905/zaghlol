using System.Text;
using System.Text.RegularExpressions;
using Zaghlol.Api.Problems;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Accounts;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// <c>POST /v1/apple/android-callback</c> (CR-05, FU-008; backend-api §4.6): Sign in with Apple's <c>form_post</c> for the Android web
/// flow. A stateless bounce: every forwarded field must match its pattern (else <c>400</c>), <c>user</c> and every unlisted field is
/// dropped unread, nothing is stored, and the answer is <c>303</c> to <c>intent://callback?…#Intent;package=…;scheme=signinwithapple;end</c>
/// built from constants and percent-encoded values, never by concatenating raw input. The form and the <c>Location</c> are never logged.
/// </summary>
internal static partial class AppleCallbackEndpoint
{
    /// <summary>The form body cap: an ID token (8 KB), a code (2 KB), <c>state</c>, <c>error</c> and Apple's <c>user</c> (4 KB) fit.</summary>
    public const int MaxBodyBytes = 32 * 1024;

    private const int MaxIdTokenLength = 8192;
    private const string IntentScheme = "signinwithapple";

    public static IEndpointRouteBuilder MapAppleCallback(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapPost("/v1/apple/android-callback", HandleAsync).WithName("appleAndroidCallback");
        return endpoints;
    }

    private static async Task<IResult> HandleAsync(HttpContext context, AccountsOptions options)
    {
        context.Response.Headers.CacheControl = "no-store";
        context.Response.Headers["Referrer-Policy"] = "no-referrer";

        var request = context.Request;
        if (!request.HasFormContentType || !request.ContentType!.StartsWith("application/x-www-form-urlencoded", StringComparison.OrdinalIgnoreCase))
        {
            return ApiProblems.Of(StatusCodes.Status415UnsupportedMediaType, ErrorCodes.UnsupportedMediaType);
        }

        if (request.ContentLength > MaxBodyBytes)
        {
            return ApiProblems.Of(StatusCodes.Status413PayloadTooLarge, ErrorCodes.PayloadTooLarge);
        }

        // A chunked body has no Content-Length: cap what the form reader may buffer.
        if (context.Features.Get<Microsoft.AspNetCore.Http.Features.IHttpMaxRequestBodySizeFeature>() is { IsReadOnly: false } limit)
        {
            limit.MaxRequestBodySize = MaxBodyBytes;
        }

        IFormCollection form;
        try
        {
            form = await request.ReadFormAsync(context.RequestAborted);
        }
        catch (BadHttpRequestException ex) when (ex.StatusCode == StatusCodes.Status413PayloadTooLarge)
        {
            return ApiProblems.Of(StatusCodes.Status413PayloadTooLarge, ErrorCodes.PayloadTooLarge);
        }
        catch (Exception ex) when (ex is InvalidDataException or BadHttpRequestException or IOException)
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        // Only the four listed fields are read, each at most once. `user` (name, e-mail) is never touched.
        if (!AtMostOne(form, "state", out var state) || state is null || !State().IsMatch(state)
            || !AtMostOne(form, "code", out var code) || !AtMostOne(form, "id_token", out var idToken) || !AtMostOne(form, "error", out var error))
        {
            return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
        }

        var query = new List<(string Name, string Value)>();
        if (error is not null)
        {
            if (code is not null || idToken is not null || !ErrorCode().IsMatch(error))
            {
                return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
            }

            query.Add(("error", error));
        }
        else
        {
            if (code is null || idToken is null || !Code().IsMatch(code) || idToken.Length > MaxIdTokenLength || !CompactJws().IsMatch(idToken))
            {
                return ApiProblems.Of(StatusCodes.Status400BadRequest, ErrorCodes.ValidationFailed);
            }

            query.Add(("code", code));
            query.Add(("id_token", idToken));
        }

        query.Add(("state", state));
        return new SeeOther(Location(options.AndroidPackage, query));
    }

    /// <summary>
    /// <c>intent://callback?name=value&amp;…#Intent;package=…;scheme=signinwithapple;end</c>: scheme, host, package and scheme word are
    /// constants (the package is validated at startup), each value is percent-encoded, and the single <c>#</c> is ours.
    /// </summary>
    internal static string Location(string package, IReadOnlyList<(string Name, string Value)> query)
    {
        var builder = new StringBuilder("intent://callback?");
        for (var i = 0; i < query.Count; i++)
        {
            if (i > 0)
            {
                builder.Append('&');
            }

            builder.Append(query[i].Name).Append('=').Append(Uri.EscapeDataString(query[i].Value));
        }

        return builder.Append("#Intent;package=").Append(package).Append(";scheme=").Append(IntentScheme).Append(";end").ToString();
    }

    /// <summary>False when the field repeats; <paramref name="value"/> is null when it is absent.</summary>
    private static bool AtMostOne(IFormCollection form, string name, out string? value)
    {
        value = null;
        if (!form.TryGetValue(name, out var values))
        {
            return true;
        }

        if (values.Count != 1)
        {
            return false;
        }

        value = values[0];
        return value is not null;
    }

    /// <summary>A <c>303 See Other</c> with a non-HTTP <c>Location</c> (the framework's redirect helpers insist on a URI).</summary>
    private sealed class SeeOther(string location) : IResult
    {
        public Task ExecuteAsync(HttpContext httpContext)
        {
            httpContext.Response.StatusCode = StatusCodes.Status303SeeOther;
            httpContext.Response.Headers.Location = location;
            return Task.CompletedTask;
        }
    }

    [GeneratedRegex(@"^[A-Za-z0-9_-]{16,128}\z", RegexOptions.CultureInvariant)]
    private static partial Regex State();

    [GeneratedRegex(@"^[A-Za-z0-9._-]{1,2048}\z", RegexOptions.CultureInvariant)]
    private static partial Regex Code();

    [GeneratedRegex(@"^[a-z_]{1,64}\z", RegexOptions.CultureInvariant)]
    private static partial Regex ErrorCode();

    [GeneratedRegex(@"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*\z", RegexOptions.CultureInvariant)]
    private static partial Regex CompactJws();
}
