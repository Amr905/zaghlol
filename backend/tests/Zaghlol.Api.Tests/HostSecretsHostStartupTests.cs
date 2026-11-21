using System.Security.Cryptography;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests;

/// <summary>
/// T-205 acceptance 1, 2 and 5 at host level: the real API <c>Program</c> starts in Staging and Production with
/// <c>Kms:Provider = HostSecrets</c> (database unreachable on purpose), and neither its logs nor <c>GET /v1/health</c> carry key
/// material; without <c>Kms:AcceptSharedHostCustody</c> it refuses to start in Production with the constant message.
/// Any OS: the provider needs no POSIX file checks.
/// </summary>
[Collection(ApiHostGroup.Name)]
public sealed class HostSecretsHostStartupTests : IDisposable
{
    private readonly HostSecretsKeySet keys = new();
    private readonly FakeOidcIssuer issuer = new();
    private readonly ECDsa appleKey = ECDsa.Create(ECCurve.NamedCurves.nistP256);
    private readonly CapturingSink logs = new();

    public void Dispose() => appleKey.Dispose();

    [Theory]
    [InlineData("Staging")]
    [InlineData("Production")]
    public async Task TheApiStartsWithHostSecretsAndShowsNoKeyMaterial(string environment)
    {
        using var factory = ProductionApiFactory.Create(environment, keys.Settings(), logs, issuer, appleKey);

        using var client = factory.CreateClient();
        using var response = await client.GetAsync(new Uri("/v1/health", UriKind.Relative));
        var body = await response.Content.ReadAsStringAsync();

        Assert.Equal("HostSecretsKms", factory.Services.GetRequiredService<ISigningKeyProvider>().GetType().Name);
        var signer = factory.Services.GetRequiredService<ISigner>();
        var signature = await signer.SignAsync(SigningPurpose.Sync, "{}"u8.ToArray(), CancellationToken.None);
        var point = signer.PublishedKeys(SigningPurpose.Sync).Single().PublicJwk.ToX963();
        using var verifier = ECDsa.Create(new ECParameters
        {
            Curve = ECCurve.NamedCurves.nistP256,
            Q = new ECPoint { X = point[1..33], Y = point[33..] },
        });
        Assert.True(verifier.VerifyData("{}"u8, signature.Signature.Span, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation));
        Assert.Contains(logs.Entries, e => e.StartsWith("KMS key ring verified", StringComparison.Ordinal));
        AssertNoKeyMaterial(body + "\n" + response.Headers + "\n" + string.Join('\n', logs.Entries));
    }

    [Fact]
    public void TheApiRefusesHostSecretsInProductionWithoutTheCustodyFlag()
    {
        var settings = keys.Settings();
        settings.Remove("Kms:AcceptSharedHostCustody");

        var error = ApiStartRefusal.Expect(() => ProductionApiFactory.Create("Production", settings, logs, issuer, appleKey));

        var refusal = Assert.Single(HostStartupTests.Chain(error).OfType<KmsConfigurationException>());
        Assert.StartsWith("Outside Development and Testing, Kms:Provider = HostSecrets needs Kms:AcceptSharedHostCustody = true", refusal.Message, StringComparison.Ordinal);
        AssertNoKeyMaterial(error + "\n" + string.Join('\n', logs.Entries));
    }

    private void AssertNoKeyMaterial(string haystack)
    {
        foreach (var sentinel in keys.Sentinels)
        {
            Assert.DoesNotContain(sentinel, haystack, StringComparison.OrdinalIgnoreCase);
        }
    }
}
