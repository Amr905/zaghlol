using System.Security.Cryptography;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Zaghlol.Infrastructure.Accounts;

namespace Zaghlol.Infrastructure.Tests.Accounts;

/// <summary>Accounts:* (T-135): Production refuses to start without the client IDs and the Sign in with Apple key; Development doesn't need them.</summary>
public class AccountsOptionsTests
{
    private sealed class Env(string name) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = name;

        public string ApplicationName { get; set; } = "t";

        public string ContentRootPath { get; set; } = "/";

        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = null!;
    }

    private static string NewPem()
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        return key.ExportPkcs8PrivateKeyPem();
    }

    private static Dictionary<string, string?> Complete() => new()
    {
        ["Accounts:Google:ClientIds:0"] = "1234567890-web.apps.googleusercontent.com",
        ["Accounts:Google:ClientIds:1"] = "1234567890-android.apps.googleusercontent.com",
        ["Accounts:Apple:ServicesId"] = "app.zaghlol.signin",
        ["Accounts:Apple:BundleId"] = "app.zaghlol",
        ["Accounts:Apple:TeamId"] = "ABCDE12345",
        ["Accounts:Apple:KeyId"] = "FGHIJ67890",
        ["Accounts:Apple:PrivateKey"] = NewPem(),
        ["Accounts:AndroidPackage"] = "app.zaghlol",
    };

    private static AccountsOptions Read(Dictionary<string, string?> settings, string environment = "Production") =>
        AccountsOptions.Read(new ConfigurationBuilder().AddInMemoryCollection(settings).Build(), new Env(environment));

    [Fact]
    public void AProductionConfigurationReadsEveryValue()
    {
        var options = Read(Complete());

        Assert.Equal(2, options.GoogleClientIds.Count);
        Assert.Equal(["app.zaghlol.signin", "app.zaghlol"], options.AppleAudiences);
        Assert.True(options.HasAppleKey);
        Assert.Equal("app.zaghlol", options.AndroidPackage);
        Assert.Equal(new Uri("https://appleid.apple.com"), options.AppleBaseUrl);
        Assert.DoesNotContain("PRIVATE", options.ApplePrivateKey!.Value.ToString(), StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("Accounts:Google:ClientIds:0")]
    [InlineData("Accounts:Apple:ServicesId")]
    [InlineData("Accounts:Apple:BundleId")]
    [InlineData("Accounts:Apple:TeamId")]
    [InlineData("Accounts:Apple:KeyId")]
    [InlineData("Accounts:Apple:PrivateKey")]
    [InlineData("Accounts:AndroidPackage")]
    public void ProductionRefusesToStartWithoutEachRequiredSetting(string missing)
    {
        var settings = Complete();
        settings.Remove(missing);
        if (missing == "Accounts:Google:ClientIds:0")
        {
            settings.Remove("Accounts:Google:ClientIds:1");
        }

        var error = Assert.Throws<AccountsConfigurationException>(() => Read(settings));

        Assert.StartsWith("Accounts", error.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("Development")]
    [InlineData("Testing")]
    public void DevelopmentAndTestingNeedNothing(string environment)
    {
        var options = Read([], environment);

        Assert.Empty(options.GoogleClientIds);
        Assert.False(options.HasAppleKey);
    }

    [Fact]
    public void ABadKeyOrIdentifierStopsTheHostAndNeverEchoesTheValue()
    {
        var notAKey = Complete();
        notAKey["Accounts:Apple:PrivateKey"] = "super-secret-not-a-pem";
        var badTeam = Complete();
        badTeam["Accounts:Apple:TeamId"] = "short";
        var partial = Complete();
        partial.Remove("Accounts:Apple:KeyId");

        foreach (var settings in new[] { notAKey, badTeam, partial })
        {
            var error = Assert.ThrowsAny<Exception>(() => Read(settings, "Development"));
            Assert.DoesNotContain("super-secret", error.Message, StringComparison.Ordinal);
            Assert.DoesNotContain("short", error.Message, StringComparison.Ordinal);
        }
    }

    [Fact]
    public void ABaseUrlOverrideIsOnlyForDevelopmentAndTesting()
    {
        var settings = Complete();
        settings["Accounts:Apple:BaseUrl"] = "http://127.0.0.1:9999";

        Assert.Throws<AccountsConfigurationException>(() => Read(settings));
        Assert.Equal(new Uri("http://127.0.0.1:9999"), Read(settings, "Testing").AppleBaseUrl);
    }

    [Fact]
    public void TheAndroidPackageFallsBackToThePlayPackage()
    {
        var settings = Complete();
        settings.Remove("Accounts:AndroidPackage");
        settings["Purchases:Google:PackageName"] = "app.zaghlol.play";

        Assert.Equal("app.zaghlol.play", Read(settings).AndroidPackage);
    }
}
