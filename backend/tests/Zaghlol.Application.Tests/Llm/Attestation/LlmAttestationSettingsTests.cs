using Zaghlol.Application.Config;
using Zaghlol.Application.Flags;
using Zaghlol.Application.Llm.Attestation;

namespace Zaghlol.Application.Tests.Llm.Attestation;

/// <summary>T-336 AC4 (negative proof 1): the mode guard. Fake only in Development/Testing, ReportOnly only in Staging, Production always Enforce.</summary>
public sealed class LlmAttestationSettingsTests
{
    private static readonly string Key = Convert.ToBase64String(new byte[32]);

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    [InlineData("production")]
    [InlineData("Prod")]
    public void FakeIsRefusedOutsideDevelopmentAndTesting(string environment) =>
        Assert.Throws<LlmAttestationConfigurationException>(() => LlmAttestationSettings.Resolve("Fake", null, environment));

    [Theory]
    [InlineData("Production")]
    [InlineData("Development")]
    [InlineData("Testing")]
    [InlineData("Prod")]
    public void ReportOnlyIsRefusedOutsideStaging(string environment) =>
        Assert.Throws<LlmAttestationConfigurationException>(() => LlmAttestationSettings.Resolve("ReportOnly", null, environment));

    [Theory]
    [InlineData("Production")]
    [InlineData("Staging")]
    public void ADevProofKeyIsRefusedOutsideDevelopmentAndTesting(string environment) =>
        Assert.Throws<LlmAttestationConfigurationException>(() => LlmAttestationSettings.Resolve("Enforce", Key, environment));

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("Enforce")]
    public void ProductionAlwaysEnforcesWithoutADevKey(string? mode)
    {
        var settings = LlmAttestationSettings.Resolve(mode, null, "Production");
        Assert.Equal(LlmAttestationMode.Enforce, settings.Mode);
        Assert.False(settings.HasDevProofKey);
    }

    [Theory]
    [InlineData("Off")]
    [InlineData("None")]
    [InlineData("fake")]
    [InlineData("Disabled")]
    public void AnUnknownModeStopsStartupEverywhere(string mode)
    {
        foreach (var environment in new[] { "Production", "Staging", "Development", "Testing" })
        {
            Assert.Throws<LlmAttestationConfigurationException>(() => LlmAttestationSettings.Resolve(mode, Key, environment));
        }
    }

    [Fact]
    public void TheAllowedStagesResolve()
    {
        Assert.Equal(LlmAttestationMode.Fake, LlmAttestationSettings.Resolve("Fake", Key, "Development").Mode);
        Assert.Equal(LlmAttestationMode.Fake, LlmAttestationSettings.Resolve("Fake", Key, "Testing").Mode);
        Assert.Equal(LlmAttestationMode.ReportOnly, LlmAttestationSettings.Resolve("ReportOnly", null, "Staging").Mode);
        Assert.Equal(LlmAttestationMode.Enforce, LlmAttestationSettings.Resolve(null, null, "Staging").Mode);
        Assert.Equal(LlmAttestationMode.Enforce, LlmAttestationSettings.Resolve(null, null, "Testing").Mode);
        Assert.False(LlmAttestationSettings.Resolve("Enforce", Key, "Testing").HasDevProofKey);
    }

    [Fact]
    public void FakeNeedsAStrongBase64Key()
    {
        Assert.Throws<LlmAttestationConfigurationException>(() => LlmAttestationSettings.Resolve("Fake", null, "Testing"));
        Assert.Throws<LlmAttestationConfigurationException>(() => LlmAttestationSettings.Resolve("Fake", "not base64!", "Testing"));
        Assert.Throws<LlmAttestationConfigurationException>(() => LlmAttestationSettings.Resolve("Fake", Convert.ToBase64String(new byte[31]), "Testing"));
    }

    [Fact]
    public void ErrorsAndToStringNeverEchoTheKey()
    {
        // Built at run time: a literal here trips the repository secret scan.
        var secret = Convert.ToBase64String(System.Text.Encoding.ASCII.GetBytes(string.Concat(Enumerable.Repeat("marker-", 5))));
        var error = Assert.Throws<LlmAttestationConfigurationException>(() => LlmAttestationSettings.Resolve("Enforce", secret, "Production"));
        Assert.DoesNotContain(secret, error.Message, StringComparison.Ordinal);
        Assert.DoesNotContain(secret, LlmAttestationSettings.Resolve("Fake", secret, "Testing").ToString(), StringComparison.Ordinal);
    }

    /// <summary>No remote config key or flag exists that could carry the mode: both closed sets hold nothing about attestation.</summary>
    [Fact]
    public void NoRemoteConfigKeyOrFlagNamesAttestation()
    {
        Assert.DoesNotContain(RemoteConfigKeys.All, d => d.Key.Contains("attest", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(FlagKeys.Known, k => k.Contains("attest", StringComparison.OrdinalIgnoreCase));
    }
}
