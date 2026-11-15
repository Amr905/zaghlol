using System.Net;
using System.Text;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Api.Endpoints.V1;
using Zaghlol.Api.Tests.Installs;
using Zaghlol.Infrastructure.Accounts;
using ProblemAssert = Zaghlol.Api.Tests.Installs.Problems;

namespace Zaghlol.Api.Tests.Accounts;

/// <summary>The callback needs no database: only <c>Accounts:AndroidPackage</c> and the pipeline.</summary>
public sealed class AppleCallbackHostFixture : InstallsHostFixture
{
    public const string Package = "app.zaghlol.test";

    protected override bool WithDatabase => false;

    protected override IReadOnlyDictionary<string, string?> Settings
    {
        get
        {
            var settings = new Dictionary<string, string?>(base.Settings) { ["Accounts:AndroidPackage"] = Package };
            return settings;
        }
    }

    protected override void ConfigureServices(IServiceCollection services) => services.AddZaghlolAccounts();

    protected override void MapEndpoints(WebApplication application) => application.MapAccounts();
}

/// <summary>
/// <c>POST /v1/apple/android-callback</c> (CR-05, FU-008, T-135): the bounce builds its <c>intent://</c> <c>Location</c> from constants and
/// pattern-checked, percent-encoded values; an injected <c>#</c>, <c>;</c>, <c>%23</c>, CR/LF or <c>&amp;</c> in any forwarded field is a
/// <c>400</c> (or, were a field ever loosened, still exactly one <c>#Intent;…;end</c> tail). <c>user</c> and unlisted fields are dropped
/// unread; neither the form nor the <c>Location</c> reaches the logs.
/// </summary>
[Collection(ApiHostGroup.Name)]
public class AppleCallbackTests(AppleCallbackHostFixture f) : IClassFixture<AppleCallbackHostFixture>
{
    private const string State = "AbCdEf0123456789_-AbCdEf";
    private const string Code = "c1a0b2d3.e4f5-g6h7";
    private const string IdToken = "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln";
    private const string Tail = "#Intent;package=" + AppleCallbackHostFixture.Package + ";scheme=signinwithapple;end";

    private static readonly string[] Injections =
    [
        "a#b", "a;b", "a%23b", "a\rb", "a\nb", "a\r\nLocation: evil", "a&b=1", "a#Intent;package=evil;end", "#", ";end", "%0d%0a", "a b", "a\u0000b",
    ];

    private async Task<HttpResponseMessage> PostAsync(IEnumerable<KeyValuePair<string, string>> form, string? mediaType = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/apple/android-callback");
        request.Content = mediaType is null
            ? new FormUrlEncodedContent(form)
            : new StringContent(string.Join('&', form.Select(p => p.Key + "=" + Uri.EscapeDataString(p.Value))), Encoding.UTF8, mediaType);
        return await f.Client.SendAsync(request);
    }

    private static Dictionary<string, string> Success() => new() { ["code"] = Code, ["id_token"] = IdToken, ["state"] = State };

    /// <summary>The header as the server wrote it (the typed <c>Location</c> would be normalized by the client's URI parser).</summary>
    private static string LocationOf(HttpResponseMessage response) => string.Concat(response.Headers.NonValidated["Location"]);

    [Fact]
    public async Task ASuccessfulForm_Answers303WithExactlyTheIntentLocationAndNothingElse()
    {
        var form = Success();
        form["user"] = "{\"name\":{\"firstName\":\"X\"},\"email\":\"person@example.test\"}";
        form["extra"] = "ignored";

        using var response = await PostAsync(form);

        Assert.Equal(HttpStatusCode.SeeOther, response.StatusCode);
        Assert.Equal($"intent://callback?code={Code}&id_token={IdToken}&state={State}{Tail}", LocationOf(response));
        Assert.Equal("no-store", response.Headers.CacheControl?.ToString());
    }

    [Fact]
    public async Task ACancelledAuthorization_ForwardsOnlyErrorAndState()
    {
        using var response = await PostAsync(new Dictionary<string, string> { ["error"] = "user_cancelled_authorize", ["state"] = State });

        Assert.Equal(HttpStatusCode.SeeOther, response.StatusCode);
        Assert.Equal($"intent://callback?error=user_cancelled_authorize&state={State}{Tail}", LocationOf(response));
    }

    public static TheoryData<string> Fields => new() { "state", "code", "id_token", "error" };

    [Theory]
    [MemberData(nameof(Fields))]
    public async Task EveryInjectionInEveryForwardedFieldIs400OrKeepsExactlyOneIntentTail(string field)
    {
        foreach (var injection in Injections)
        {
            var form = field == "error"
                ? new Dictionary<string, string> { ["error"] = "user_cancelled_authorize", ["state"] = State }
                : Success();
            form[field] = field == "id_token" ? "aaa." + injection + ".ccc" : field == "state" ? injection + State : injection;

            using var response = await PostAsync(form);

            if (response.StatusCode == HttpStatusCode.BadRequest)
            {
                await ProblemAssert.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
                Assert.False(response.Headers.Contains("Location"));
                continue;
            }

            Assert.Equal(HttpStatusCode.SeeOther, response.StatusCode);
            var location = LocationOf(response);
            Assert.Single(location, '#');
            Assert.EndsWith(Tail, location, StringComparison.Ordinal);
            Assert.Equal(1, CountOf(location, ";scheme=signinwithapple;end"));
            Assert.DoesNotContain('\r', location);
            Assert.DoesNotContain('\n', location);
        }
    }

    [Fact]
    public async Task InjectionInTheDroppedUserFieldNeverReachesTheLocation()
    {
        var form = Success();
        form["user"] = "x#Intent;package=evil;end&code=evil";

        using var response = await PostAsync(form);

        Assert.Equal(HttpStatusCode.SeeOther, response.StatusCode);
        var location = LocationOf(response);
        Assert.DoesNotContain("evil", location, StringComparison.Ordinal);
        Assert.Single(location, '#');
    }

    [Theory]
    [InlineData("missing-state")]
    [InlineData("code-without-id-token")]
    [InlineData("error-with-code")]
    [InlineData("no-code-no-error")]
    [InlineData("short-state")]
    [InlineData("long-state")]
    public async Task MalformedFormsAre400(string kind)
    {
        var form = kind switch
        {
            "missing-state" => new Dictionary<string, string> { ["code"] = Code, ["id_token"] = IdToken },
            "code-without-id-token" => new Dictionary<string, string> { ["code"] = Code, ["state"] = State },
            "error-with-code" => new Dictionary<string, string> { ["error"] = "user_cancelled_authorize", ["code"] = Code, ["state"] = State },
            "no-code-no-error" => new Dictionary<string, string> { ["state"] = State },
            "short-state" => new Dictionary<string, string> { ["code"] = Code, ["id_token"] = IdToken, ["state"] = "tooshort" },
            _ => new Dictionary<string, string> { ["code"] = Code, ["id_token"] = IdToken, ["state"] = new string('a', 129) },
        };

        using var response = await PostAsync(form);

        await ProblemAssert.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
    }

    [Fact]
    public async Task ARepeatedForwardedFieldIs400_AJsonBodyIs415_AndABodyOverTheCapIs413()
    {
        using var repeated = new HttpRequestMessage(HttpMethod.Post, "/v1/apple/android-callback")
        {
            Content = new StringContent($"state={State}&state={State}&code={Code}&id_token={IdToken}", Encoding.UTF8, "application/x-www-form-urlencoded"),
        };
        using var repeatedResponse = await f.Client.SendAsync(repeated);
        await ProblemAssert.AssertAsync(repeatedResponse, HttpStatusCode.BadRequest, "VALIDATION_FAILED");

        using var json = new HttpRequestMessage(HttpMethod.Post, "/v1/apple/android-callback") { Content = new StringContent("{}", Encoding.UTF8, "application/json") };
        using var jsonResponse = await f.Client.SendAsync(json);
        await ProblemAssert.AssertAsync(jsonResponse, HttpStatusCode.UnsupportedMediaType, "UNSUPPORTED_MEDIA_TYPE");

        var big = Success();
        big["user"] = new string('x', AppleCallbackEndpoint.MaxBodyBytes + 1);
        using var bigResponse = await PostAsync(big);
        await ProblemAssert.AssertAsync(bigResponse, HttpStatusCode.RequestEntityTooLarge, "PAYLOAD_TOO_LARGE");
    }

    [Fact]
    public async Task NeitherTheFormNorTheLocationIsLogged()
    {
        var code = "sentinelcode" + Guid.NewGuid().ToString("N");
        var form = Success();
        form["code"] = code;
        form["user"] = "sentinel-user-" + Guid.NewGuid().ToString("N");

        using var ok = await PostAsync(form);
        form["state"] = "bad";
        using var bad = await PostAsync(form);

        Assert.Equal(HttpStatusCode.SeeOther, ok.StatusCode);
        var logs = string.Join('\n', f.LogSink.Entries);
        Assert.DoesNotContain(code, logs, StringComparison.Ordinal);
        Assert.DoesNotContain("sentinel-user-", logs, StringComparison.Ordinal);
        Assert.DoesNotContain(IdToken, logs, StringComparison.Ordinal);
        Assert.DoesNotContain("intent://", logs, StringComparison.Ordinal);
    }

    private static int CountOf(string text, string needle)
    {
        var count = 0;
        for (var i = text.IndexOf(needle, StringComparison.Ordinal); i >= 0; i = text.IndexOf(needle, i + needle.Length, StringComparison.Ordinal))
        {
            count++;
        }

        return count;
    }
}
