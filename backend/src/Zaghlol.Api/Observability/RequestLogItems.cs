namespace Zaghlol.Api.Observability;

/// <summary>
/// <c>HttpContext.Items</c> keys that carry log fields to <see cref="RequestLogMiddleware"/>, which runs outside the
/// handlers. They hold values already safe to log: a pseudonym and a stable problem code.
/// </summary>
public static class RequestLogItems
{
    /// <summary>Set by the install auth handler (T-124): <c>ILogPseudonymizer.InstallHashAsync(installId)</c>.</summary>
    public const string InstallHash = "zaghlol.log.installHash";

    /// <summary>Set by the problem-details customizer: the <c>code</c> of the error body.</summary>
    public const string ProblemCode = "zaghlol.log.code";
}
