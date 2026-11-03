using System.Diagnostics;

namespace Zaghlol.Api.Problems;

internal static class ProblemDetailsCustomizer
{
    /// <summary>
    /// Adds the stable <c>code</c> and a correlation id to every RFC 9457 body, and makes sure
    /// nothing from the request is echoed back (backend-api.md section 1).
    /// </summary>
    public static void Customize(ProblemDetailsContext context)
    {
        var problem = context.ProblemDetails;
        var status = problem.Status ?? context.HttpContext.Response.StatusCode;

        problem.Status = status;
        problem.Instance = null;

        if (!problem.Extensions.ContainsKey("code"))
        {
            problem.Extensions["code"] = ProblemCodes.ForStatus(status);
        }

        problem.Extensions["correlationId"] = Activity.Current?.TraceId.ToString() ?? context.HttpContext.TraceIdentifier;
    }
}
