using System.Buffers.Text;
using System.Globalization;
using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using Zaghlol.Api.Signing;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Signing;

/// <summary>T-123: <see cref="ResponseSigningMiddleware"/> signs exactly the 200 bodies of marked endpoints.</summary>
[Collection(ApiHostGroup.Name)]
public partial class ResponseSigningTests(SigningHostFixture fixture) : IClassFixture<SigningHostFixture>
{
    [GeneratedRegex("^kid=(s[0-9]{4}[a-z]); alg=ES256; sig=([A-Za-z0-9_-]{86})\\z")]
    private static partial Regex HeaderPattern();

    [Fact]
    public async Task A200IsSignedOverTheExactBodyAndVerifiesWithTheExportedKey()
    {
        using var response = await GetAsync("/t/signed");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadAsByteArrayAsync();
        Assert.Equal(body.Length, response.Content.Headers.ContentLength);
        AssertSigned(response, body);
        using var json = JsonDocument.Parse(body);
        Assert.Equal("مرحبا zaghlol", json.RootElement.GetProperty("message").GetString());
    }

    [Fact]
    public async Task AnEmptyObjectBodyIsSigned()
    {
        using var response = await GetAsync("/t/signed-empty");

        var body = await response.Content.ReadAsByteArrayAsync();
        Assert.Equal("{}"u8.ToArray(), body);
        AssertSigned(response, body);
    }

    [Theory]
    [InlineData("/t/signed-body-stream")]
    [InlineData("/t/signed-body-writer")]
    public async Task BodyStreamAndBodyWriterWritesAreBothBufferedAndSigned(string path)
    {
        using var response = await GetAsync(path);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadAsByteArrayAsync();
        Assert.Equal(SigningHostFixture.PartA.Concat(SigningHostFixture.PartB).ToArray(), body);
        AssertSigned(response, body);
    }

    [Theory]
    [InlineData("/t/signed-404", HttpStatusCode.NotFound)]
    [InlineData("/t/signed-409", HttpStatusCode.Conflict)]
    [InlineData("/t/unsigned", HttpStatusCode.OK)]
    public async Task OnlyA200OfAMarkedEndpointIsSigned(string path, HttpStatusCode status)
    {
        using var response = await GetAsync(path);

        Assert.Equal(status, response.StatusCode);
        Assert.False(response.Headers.Contains(ResponseSigningMiddleware.HeaderName));
        Assert.NotEmpty(await response.Content.ReadAsByteArrayAsync());
    }

    [Theory]
    [InlineData("/t/signed-404-bodiless", HttpStatusCode.NotFound, "NOT_FOUND")]
    [InlineData("/t/signed-401-bodiless", HttpStatusCode.Unauthorized, "UNAUTHORIZED")]
    [InlineData("/t/signed-union-not-found", HttpStatusCode.NotFound, "NOT_FOUND")]
    public async Task ABodilessErrorOfASignedEndpointStillGetsTheProblemBody(string path, HttpStatusCode status, string code)
    {
        using var response = await GetAsync(path);

        Assert.Equal(status, response.StatusCode);
        Assert.False(response.Headers.Contains(ResponseSigningMiddleware.HeaderName));
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(code, json.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task AHandlerCannotSupplyItsOwnSignature()
    {
        using var response = await GetAsync("/t/signed-spoof");

        var body = await response.Content.ReadAsByteArrayAsync();
        AssertSigned(response, body);
        Assert.DoesNotContain("forged", Header(response), StringComparison.Ordinal);
    }

    [Fact]
    public async Task AnExceptionDiscardsTheBufferAndGivesAnUnsignedProblem()
    {
        using var response = await GetAsync("/t/signed-throws");

        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        Assert.False(response.Headers.Contains(ResponseSigningMiddleware.HeaderName));
        var body = await response.Content.ReadAsStringAsync();
        Assert.DoesNotContain("partial", body, StringComparison.Ordinal);
        using var json = JsonDocument.Parse(body);
        Assert.Equal("INTERNAL", json.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task ABodyOfExactlyTheCapIsSignedAndOneByteMoreIsA500()
    {
        using (var atCap = await GetAsync(string.Create(CultureInfo.InvariantCulture, $"/t/signed-size/{ResponseSigningMiddleware.MaxBufferedBytes}")))
        {
            Assert.Equal(HttpStatusCode.OK, atCap.StatusCode);
            var body = await atCap.Content.ReadAsByteArrayAsync();
            Assert.Equal(ResponseSigningMiddleware.MaxBufferedBytes, body.Length);
            AssertSigned(atCap, body);
        }

        using var over = await GetAsync(string.Create(CultureInfo.InvariantCulture, $"/t/signed-size/{ResponseSigningMiddleware.MaxBufferedBytes + 1}"));
        Assert.Equal(HttpStatusCode.InternalServerError, over.StatusCode);
        Assert.False(over.Headers.Contains(ResponseSigningMiddleware.HeaderName));
        using var json = JsonDocument.Parse(await over.Content.ReadAsStringAsync());
        Assert.Equal("INTERNAL", json.RootElement.GetProperty("code").GetString());
    }

    [Theory]
    [InlineData(FakeKmsFault.Throw)]
    [InlineData(FakeKmsFault.Hang)]
    public async Task AKmsOutageIs503WithRetryAfterAndNoBody(FakeKmsFault fault)
    {
        fixture.Kms.Fault = fault;
        try
        {
            using var response = await GetAsync("/t/signed");

            Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
            Assert.Equal(TimeSpan.FromSeconds(5), response.Headers.RetryAfter?.Delta);
            Assert.False(response.Headers.Contains(ResponseSigningMiddleware.HeaderName));
            var body = await response.Content.ReadAsStringAsync();
            Assert.DoesNotContain("zaghlol", body, StringComparison.Ordinal);
            using var json = JsonDocument.Parse(body);
            Assert.Equal("UPSTREAM_UNAVAILABLE", json.RootElement.GetProperty("code").GetString());
            Assert.Equal(5, json.RootElement.GetProperty("retryAfterSeconds").GetInt32());
        }
        finally
        {
            fixture.Kms.Fault = FakeKmsFault.None;
        }
    }

    private async Task<HttpResponseMessage> GetAsync(string path) => await fixture.Client.GetAsync(new Uri(path, UriKind.Relative));

    private static string Header(HttpResponseMessage response) =>
        response.Headers.TryGetValues(ResponseSigningMiddleware.HeaderName, out var values) ? string.Join(",", values) : string.Empty;

    private void AssertSigned(HttpResponseMessage response, byte[] body)
    {
        var match = HeaderPattern().Match(Header(response));
        Assert.True(match.Success, Header(response));
        var key = fixture.Signer.PublishedKeys(SigningPurpose.Sync).Single(k => k.Kid == match.Groups[1].Value);
        Assert.True(SignatureCheck.Verifies(key.PublicJwk, body, Base64Url.DecodeFromChars(match.Groups[2].Value)));

        var flipped = body.ToArray();
        if (flipped.Length > 0)
        {
            flipped[^1] ^= 0x01;
            Assert.False(SignatureCheck.Verifies(key.PublicJwk, flipped, Base64Url.DecodeFromChars(match.Groups[2].Value)));
        }
    }
}

internal static class SignatureCheck
{
    public static bool Verifies(EcPublicJwk jwk, byte[] data, byte[] signature)
    {
        using var key = System.Security.Cryptography.ECDsa.Create(new System.Security.Cryptography.ECParameters
        {
            Curve = System.Security.Cryptography.ECCurve.NamedCurves.nistP256,
            Q = new System.Security.Cryptography.ECPoint { X = Base64Url.DecodeFromChars(jwk.X), Y = Base64Url.DecodeFromChars(jwk.Y) },
        });
        return key.VerifyData(data, signature, System.Security.Cryptography.HashAlgorithmName.SHA256, System.Security.Cryptography.DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
    }
}
