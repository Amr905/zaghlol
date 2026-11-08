using System.Buffers.Text;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Primitives;
using Zaghlol.Api.Signing;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Api.Tests.Signing;

/// <summary>T-123 / R4-2: <see cref="TimeNonceFilter"/> on a test endpoint, and the never-logged rule.</summary>
[Collection(ApiHostGroup.Name)]
public class TimeNonceTests(SigningHostFixture fixture) : IClassFixture<SigningHostFixture>
{
    private const string Valid = "kq3V9w0bQ2FwdGFpblphZw";

    public static TheoryData<string> Malformed => new()
    {
        "kq3V9w0bQ2FwdGFpblphZ",       // 21 chars
        "kq3V9w0bQ2FwdGFpblphZwA",     // 23 chars
        "kq3V9w0bQ2FwdGFpblphZw==",    // padding
        "kq3V9w0bQ2FwdGFpblph+w",      // '+'
        "kq3V9w0bQ2FwdGFpblph/w",      // '/'
        "kq3V9w0bQ2FwdGFpblphZx",      // non-canonical last char (stray low bits)
        "kq3V9w0bQ2FwdGFpblph w",      // space
    };

    private static readonly string[] TwoValues = [Valid, "AAAAAAAAAAAAAAAAAAAAAA"];

    [Theory]
    [MemberData(nameof(Malformed))]
    public async Task AMalformedNonceIs400ValidationFailedWithoutEchoingIt(string nonce)
    {
        using var response = await SendAsync("/t/anchored", nonce);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.False(response.Headers.Contains(ResponseSigningMiddleware.HeaderName));
        var body = await response.Content.ReadAsStringAsync();
        using var json = JsonDocument.Parse(body);
        Assert.Equal("VALIDATION_FAILED", json.RootElement.GetProperty("code").GetString());
        Assert.False(json.RootElement.TryGetProperty("detail", out _));
        Assert.DoesNotContain(nonce, body, StringComparison.Ordinal);
    }

    [Fact]
    public void HeaderValuesAreAcceptedOnlyWhenAbsentOrExactlyOneCanonicalValue()
    {
        Assert.True(TimeNonceFilter.TryRead(StringValues.Empty, out var absent));
        Assert.Null(absent);
        Assert.True(TimeNonceFilter.TryRead(new StringValues(Valid), out var one));
        Assert.Equal(Valid, one);
        Assert.False(TimeNonceFilter.TryRead(new StringValues(string.Empty), out _));
        Assert.False(TimeNonceFilter.TryRead(new StringValues(TwoValues), out _));
        Assert.False(TimeNonceFilter.TryRead(new StringValues(Valid + ", " + Valid), out _));
    }

    [Fact]
    public async Task TwoNonceHeadersAre400()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri("/t/anchored", UriKind.Relative));
        request.Headers.TryAddWithoutValidation(TimeNonceFilter.HeaderName, TwoValues);

        using var response = await fixture.Client.SendAsync(request);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Theory]
    [InlineData("/t/anchored")]
    [InlineData("/t/anchored-union")]
    public async Task AValidNonceIsEchoedByteForByteInsideTheSignedBody(string path)
    {
        var nonce = Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(16));
        Assert.True(TimeNonceFilter.IsCanonical(nonce));

        using var response = await SendAsync(path, nonce);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadAsByteArrayAsync();
        Assert.Contains("\"timeNonce\":\"" + nonce + "\"", Encoding.UTF8.GetString(body), StringComparison.Ordinal);
        AssertSignedBy(response, body);
    }

    [Fact]
    public async Task AnAbsentNonceGivesAnExplicitNull()
    {
        using var response = await SendAsync("/t/anchored", nonce: null);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadAsByteArrayAsync();
        using var json = JsonDocument.Parse(body);
        Assert.Equal(JsonValueKind.Null, json.RootElement.GetProperty("timeNonce").ValueKind);
        AssertSignedBy(response, body);
    }

    [Theory]
    [InlineData(null)]
    [InlineData(Valid)]
    public async Task AnAnchoredBodyThatDoesNotEchoTheNonceFailsClosed(string? nonce)
    {
        using var response = await SendAsync("/t/anchored-wrong", nonce);

        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
        Assert.False(response.Headers.Contains(ResponseSigningMiddleware.HeaderName));
    }

    [Fact]
    public async Task TheNonceAppearsInNoLogSpanOrExceptionOutput()
    {
        // A sentinel that can't occur by chance, sent to an echoing endpoint, a throwing endpoint and as a malformed value.
        var sentinel = "ZgHlNonceSentinel" + Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(3)) + "w";
        Assert.True(TimeNonceFilter.IsCanonical(sentinel), sentinel);
        var malformed = sentinel + "=";

        using (var echoed = await SendAsync("/t/anchored", sentinel))
        {
            Assert.Equal(HttpStatusCode.OK, echoed.StatusCode);
        }

        using (var failed = await SendAsync("/t/anchored-throws", sentinel))
        {
            Assert.Equal(HttpStatusCode.InternalServerError, failed.StatusCode);
            Assert.DoesNotContain(sentinel, await failed.Content.ReadAsStringAsync(), StringComparison.Ordinal);
        }

        using (var rejected = await SendAsync("/t/anchored", malformed))
        {
            Assert.Equal(HttpStatusCode.BadRequest, rejected.StatusCode);
        }

        // The request-completion event and the request span are written after the response: wait for the last one.
        var deadline = DateTime.UtcNow.AddSeconds(5);
        while (DateTime.UtcNow < deadline
               && (fixture.LogSink.Entries.Count(e => e.Contains("/t/anchored", StringComparison.Ordinal)) < 3
                   || !fixture.LogSink.Entries.Any(e => e.Contains(SigningHostFixture.HandlerFailure, StringComparison.Ordinal))))
        {
            await Task.Delay(50);
        }

        Assert.Contains(fixture.LogSink.Entries, e => e.Contains(SigningHostFixture.HandlerFailure, StringComparison.Ordinal));
        Assert.NotEmpty(fixture.Spans);
        Assert.DoesNotContain(fixture.LogSink.Entries, e => e.Contains(sentinel, StringComparison.Ordinal));
        Assert.DoesNotContain(fixture.Spans, s => s.Contains(sentinel, StringComparison.Ordinal));
    }

    [Theory]
    [InlineData("kq3V9w0bQ2FwdGFpblphZw", true)]
    [InlineData("AAAAAAAAAAAAAAAAAAAAAA", true)]
    [InlineData("____________________-Q", true)]
    [InlineData("kq3V9w0bQ2FwdGFpblphZB", false)]
    [InlineData("kq3V9w0bQ2FwdGFpblphZw\n", false)]
    [InlineData(null, false)]
    public void CanonicalFormIsTheOpenApiPattern(string? value, bool canonical) =>
        Assert.Equal(canonical, TimeNonceFilter.IsCanonical(value));

    private async Task<HttpResponseMessage> SendAsync(string path, string? nonce)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(path, UriKind.Relative));
        if (nonce is not null)
        {
            request.Headers.TryAddWithoutValidation(TimeNonceFilter.HeaderName, nonce);
        }

        return await fixture.Client.SendAsync(request);
    }

    private void AssertSignedBy(HttpResponseMessage response, byte[] body)
    {
        var header = string.Join(",", response.Headers.GetValues(ResponseSigningMiddleware.HeaderName));
        var parts = header.Split("; ");
        Assert.Equal(3, parts.Length);
        var kid = parts[0]["kid=".Length..];
        var key = fixture.Signer.PublishedKeys(SigningPurpose.Sync).Single(k => k.Kid == kid);
        Assert.True(SignatureCheck.Verifies(key.PublicJwk, body, Base64Url.DecodeFromChars(parts[2].AsSpan("sig=".Length))));
    }
}
