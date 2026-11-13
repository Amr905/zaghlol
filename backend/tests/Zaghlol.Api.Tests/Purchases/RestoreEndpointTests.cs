using System.Net;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Api.Tests.Installs;
using Zaghlol.Application.Purchases.Attestation;
using Zaghlol.Application.Purchases.Restore;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Entitlements;
using Zaghlol.Infrastructure.Purchases;
using Zaghlol.Infrastructure.Seats;
using Zaghlol.Testing;
using ProblemAssert = Zaghlol.Api.Tests.Installs.Problems;

namespace Zaghlol.Api.Tests.Purchases;

/// <summary>The purchases host with the real seat, seat-key, entitlement and restore services and the T-181 attestation fakes.</summary>
public sealed class RestoreHostFixture : PurchasesHostFixture
{
    public FakePlayIntegrityVerifier Integrity { get; } = new();

    public FakeAppAttestVerifier AppAttest { get; } = new();

    protected override void ConfigureServices(IServiceCollection services)
    {
        base.ConfigureServices(services);
        services.AddZaghlolSeatKeys();
        services.AddZaghlolSeats();
        services.AddZaghlolEntitlements();
        services.RemoveAll<IPlayIntegrityVerifier>();
        services.AddSingleton<IPlayIntegrityVerifier>(Integrity);
        services.RemoveAll<IAppAttestVerifier>();
        services.AddSingleton<IAppAttestVerifier>(AppAttest);
        services.AddZaghlolRestore();
    }
}

/// <summary>T-185 through the real pipeline: strict parse and install binding (R3-8, R2-1), the signed 200 and the per-install limit.</summary>
[Collection(ApiHostGroup.Name)]
public class RestoreEndpointTests(RestoreHostFixture fixture) : IClassFixture<RestoreHostFixture>
{
    private const string AndroidTemplate =
        "{\"platform\":\"android\",\"purchases\":[{\"productId\":\"zaghlol_gold_lifetime\",\"purchaseToken\":\"synthetic-play-token/0001\"}],"
        + "\"attestation\":{\"type\":\"play_integrity\",\"token\":\"0123456789abcdef.0123456789abcdef\"}}";

    [Fact]
    public async Task R38EveryInvalidVectorThroughTheRealPipelineIs400ValidationFailedAndNeverReachesAttestation()
    {
        var vectors = JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "vectors", "restore-binding-v1.json")))!["invalid"]!.AsArray();
        Assert.NotEmpty(vectors);
        var before = fixture.Integrity.Calls + fixture.AppAttest.Assertions;

        foreach (var vector in vectors)
        {
            var (_, token) = await fixture.NewInstallAsync();

            using var response = await Post(token, vector!["raw"]!.GetValue<string>());

            await ProblemAssert.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        }

        Assert.Equal(before, fixture.Integrity.Calls + fixture.AppAttest.Assertions);
    }

    [Fact]
    public async Task R21AProofMadeForOneInstallReplayedWithAnotherInstallsTokenAndTheSameBodyIs422()
    {
        var (installA, tokenA) = await fixture.NewInstallAsync();
        var (_, tokenB) = await fixture.NewInstallAsync();
        var hashForA = RestoreRequestParser.Parse(Encoding.UTF8.GetBytes(AndroidTemplate), InstallId.Parse(installA)).Request!.BodyHash;
        fixture.Integrity.ExpectedBodyHash = hashForA;
        try
        {
            using var asA = await Post(tokenA, AndroidTemplate);
            using var asB = await Post(tokenB, AndroidTemplate);

            Assert.Equal(HttpStatusCode.OK, asA.StatusCode);
            await ProblemAssert.AssertAsync(asB, HttpStatusCode.UnprocessableEntity, "DEVICE_ATTESTATION_FAILED");
        }
        finally
        {
            fixture.Integrity.ExpectedBodyHash = null;
        }
    }

    [Fact]
    public async Task ADuplicateNestedMemberNeverReachesBindingEvenWhenTheFirstValueIsValid()
    {
        var (_, token) = await fixture.NewInstallAsync();
        var body = AndroidTemplate.Replace("\"purchaseToken\":\"synthetic-play-token/0001\"", "\"purchaseToken\":\"a\",\"purchaseToken\":\"b\"", StringComparison.Ordinal);
        var calls = fixture.Integrity.Calls;

        using var response = await Post(token, body);

        await ProblemAssert.AssertAsync(response, HttpStatusCode.BadRequest, "VALIDATION_FAILED");
        Assert.Equal(calls, fixture.Integrity.Calls);
    }

    [Fact]
    public async Task TheSixthRestoreInAnHourFromOneInstallIs429WithRetryAfter()
    {
        var (_, token) = await fixture.NewInstallAsync();
        for (var i = 0; i < 5; i++)
        {
            using var accepted = await Post(token, "{}");
            Assert.Equal(HttpStatusCode.BadRequest, accepted.StatusCode);
        }

        using var sixth = await Post(token, "{}");

        await ProblemAssert.AssertAsync(sixth, HttpStatusCode.TooManyRequests, "RATE_LIMITED");
        Assert.NotNull(sixth.Headers.RetryAfter);
        var (_, other) = await fixture.NewInstallAsync();
        using var otherInstall = await Post(other, "{}");
        Assert.Equal(HttpStatusCode.BadRequest, otherInstall.StatusCode);
    }

    private async Task<HttpResponseMessage> Post(string token, string body)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/purchases/restore");
        request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        request.Content = new StringContent(body, Encoding.UTF8, "application/json");
        return await fixture.Client.SendAsync(request);
    }
}
