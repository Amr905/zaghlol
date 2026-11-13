using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Zaghlol.Infrastructure.Attestation;

namespace Zaghlol.Infrastructure.Tests.Attestation;

/// <summary>T-181 fail-closed configuration: test roots, the development AAGUID and foreign URLs never reach Production.</summary>
public sealed class AttestationOptionsTests
{
    [Fact]
    public void ProductionReadsTheTeamIdAndUsesThePinnedRoot()
    {
        var options = AttestationOptionsReader.ReadAppAttest(Config(("Attestation:AppAttest:TeamId", "ABCDE12345")), new Env("Production"), "app.zaghlol");
        Assert.Equal("ABCDE12345.app.zaghlol", options.AppId);
        Assert.False(options.AllowDevelopment);
        Assert.Equal(AppAttestRootCertificate.Der, options.TrustAnchor());
    }

    [Theory]
    [InlineData("Production", "Attestation:AppAttest:TeamId", "")]
    [InlineData("Staging", "Attestation:AppAttest:TeamId", "short")]
    [InlineData("Production", "Attestation:AppAttest:AllowDevelopmentEnvironment", "true")]
    [InlineData("Staging", "Attestation:AppAttest:TestRootCertificate", "AAAA")]
    [InlineData("Production", "Attestation:AppAttest:AllowDevelopmentEnvironment", "yes")]
    public void UnsafeAppAttestSettingsStopStartup(string environment, string key, string value)
    {
        var settings = new Dictionary<string, string?>(StringComparer.Ordinal) { ["Attestation:AppAttest:TeamId"] = "ABCDE12345" };
        settings[key] = value;
        Assert.Throws<AttestationConfigurationException>(() =>
            AttestationOptionsReader.ReadAppAttest(Config([.. settings.Select(s => (s.Key, s.Value))]), new Env(environment), "app.zaghlol"));
    }

    [Fact]
    public void StagingMayAllowTheDevelopmentAaguid()
    {
        var options = AttestationOptionsReader.ReadAppAttest(
            Config(("Attestation:AppAttest:TeamId", "ABCDE12345"), ("Attestation:AppAttest:AllowDevelopmentEnvironment", "true")), new Env("Staging"), "app.zaghlol");
        Assert.True(options.AllowDevelopment);
    }

    [Fact]
    public void PlayIntegrityRefusesAnotherUrlOrNoPackageOutsideTesting()
    {
        Assert.Throws<AttestationConfigurationException>(() =>
            AttestationOptionsReader.ReadPlayIntegrity(Config(("Attestation:PlayIntegrity:BaseUrl", "http://127.0.0.1:9/")), new Env("Production"), "app.zaghlol"));
        Assert.Throws<AttestationConfigurationException>(() => AttestationOptionsReader.ReadPlayIntegrity(Config(), new Env("Production"), string.Empty));
        Assert.Equal(new Uri(PlayIntegrityOptions.ProductionBaseUrl), AttestationOptionsReader.ReadPlayIntegrity(Config(), new Env("Production"), "app.zaghlol").BaseUrl);
        Assert.Equal(new Uri("http://127.0.0.1:9/"), AttestationOptionsReader.ReadPlayIntegrity(Config(("Attestation:PlayIntegrity:BaseUrl", "http://127.0.0.1:9")), new Env("Testing"), "app.zaghlol").BaseUrl);
    }

    private static IConfiguration Config(params (string Key, string? Value)[] settings) =>
        new ConfigurationBuilder().AddInMemoryCollection(settings.Select(s => new KeyValuePair<string, string?>(s.Key, s.Value))).Build();

    private sealed class Env(string name) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = name;

        public string ApplicationName { get; set; } = "t";

        public string ContentRootPath { get; set; } = "/";

        public IFileProvider ContentRootFileProvider { get; set; } = null!;
    }
}
