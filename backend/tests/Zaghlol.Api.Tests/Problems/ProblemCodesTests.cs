using Zaghlol.Api.Problems;
using Zaghlol.Domain;

namespace Zaghlol.Api.Tests.Problems;

/// <summary>FU-004 #7: the status to stable-code table (the contract's Problem.code values) is pinned.</summary>
[Collection(ApiHostGroup.Name)]
public class ProblemCodesTests
{
    [Theory]
    [InlineData(400, ErrorCodes.ValidationFailed)]
    [InlineData(401, ErrorCodes.Unauthorized)]
    [InlineData(403, ErrorCodes.Forbidden)]
    [InlineData(404, ErrorCodes.NotFound)]
    [InlineData(405, ErrorCodes.MethodNotAllowed)]
    [InlineData(413, ErrorCodes.PayloadTooLarge)]
    [InlineData(415, ErrorCodes.UnsupportedMediaType)]
    [InlineData(429, ErrorCodes.RateLimited)]
    [InlineData(502, ErrorCodes.UpstreamUnavailable)]
    [InlineData(503, ErrorCodes.UpstreamUnavailable)]
    [InlineData(500, ErrorCodes.Internal)]
    [InlineData(504, ErrorCodes.Internal)]
    // Statuses with no code of their own (408, 409, 410, 422, ...) are the caller's mistake in the request's shape.
    [InlineData(408, ErrorCodes.ValidationFailed)]
    [InlineData(410, ErrorCodes.ValidationFailed)]
    [InlineData(422, ErrorCodes.ValidationFailed)]
    public void EachStatusMapsToItsStableCode(int status, string code) => Assert.Equal(code, ProblemCodes.ForStatus(status));
}
