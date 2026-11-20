using System.Net;
using System.Net.Http.Headers;
using System.Text;
using Zaghlol.Api.Idempotency;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Installs;

/// <summary>
/// BUG-004: <c>Zaghlol-App</c> is <c>required: true</c> on every <c>/v1</c> app operation of the OpenAPI file, so a missing,
/// repeated or malformed value is <c>400 VALIDATION_FAILED</c> (QA cases API-014 and API-015 for <c>POST /v1/installs</c>).
/// Authentication still comes first: an unauthenticated call is <c>401</c> whatever the header says.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class AppHeaderTests(InstallsHostFixture fixture) : IClassFixture<InstallsHostFixture>
{
    [Fact]
    public async Task API014_RegistrationWithoutTheAppHeaderIs400AndStoresNothing()
    {
        var installId = InstallsHostFixture.NewInstallId();
        var body = InstallsHostFixture.InstallBody(installId);

        using var missing = await RegisterAsync(body, InstallsHostFixture.NewKey(), app: null);
        await Problems.AssertAsync(missing, HttpStatusCode.BadRequest, "VALIDATION_FAILED");

        // Nothing was stored: the same install registers once the header is right.
        using var created = await RegisterAsync(body, InstallsHostFixture.NewKey(), app: "android/1.0.0 (42)");
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
    }

    [Theory]
    [InlineData("android 1.0")]
    [InlineData("android/1.0.0")]
    [InlineData("android/1.0 (42)")]
    [InlineData("windows/1.0.0 (42)")]
    [InlineData("android/1.0.0 ()")]
    [InlineData("android/1.0.0  (42)")]
    [InlineData("android/١.0.0 (42)")]
    [InlineData("")]
    public async Task API015_RegistrationWithAMalformedAppHeaderIs400(string app)
    {
        using var response = await RegisterAsync(InstallsHostFixture.InstallBody(InstallsHostFixture.NewInstallId()), InstallsHostFixture.NewKey(), app);

        await Problems.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
    }

    [Fact]
    public async Task ARepeatedAppHeaderIs400()
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/installs");
        request.Options.Set(AppHeaderHandler.Omit, true);
        request.Headers.TryAddWithoutValidation("Zaghlol-App", ["android/1.0.0 (1)", "android/1.0.0 (2)"]);
        request.Headers.Add(IdempotencyKeys.HeaderName, InstallsHostFixture.NewKey());
        request.Content = new StringContent(InstallsHostFixture.InstallBody(InstallsHostFixture.NewInstallId()), Encoding.UTF8, "application/json");

        using var response = await fixture.Client.SendAsync(request);

        await Problems.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
    }

    [Fact]
    public async Task AnInstallScopedCallWithoutTheAppHeaderIs400AndDoesNothing()
    {
        var (_, token) = await fixture.NewInstallAsync();

        using var missing = await SendAsync(HttpMethod.Delete, "/v1/installs/me", token, app: null);
        using var malformed = await SendAsync(HttpMethod.Delete, "/v1/installs/me", token, app: "android 1.0");
        using var stillValid = await SendAsync(HttpMethod.Get, "/v1/t/whoami", token, app: "android/1.0.0 (1)");

        await Problems.AssertAsync(missing, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        await Problems.AssertAsync(malformed, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        Assert.Equal(HttpStatusCode.OK, stillValid.StatusCode); // the delete never ran
    }

    [Fact]
    public async Task AuthenticationComesBeforeTheAppHeaderCheck()
    {
        using var response = await SendAsync(HttpMethod.Get, "/v1/t/whoami", token: null, app: null);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    private async Task<HttpResponseMessage> RegisterAsync(string body, string key, string? app)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/installs");
        Apply(request, app);
        request.Headers.Add(IdempotencyKeys.HeaderName, key);
        request.Content = new StringContent(body, Encoding.UTF8, "application/json");
        return await fixture.Client.SendAsync(request);
    }

    private async Task<HttpResponseMessage> SendAsync(HttpMethod method, string path, string? token, string? app)
    {
        using var request = new HttpRequestMessage(method, path);
        Apply(request, app);
        if (token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        }

        return await fixture.Client.SendAsync(request);
    }

    private static void Apply(HttpRequestMessage request, string? app)
    {
        request.Options.Set(AppHeaderHandler.Omit, true);
        if (app is not null)
        {
            request.Headers.TryAddWithoutValidation("Zaghlol-App", app);
        }
    }
}
