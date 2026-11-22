using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using Npgsql;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Tests;

/// <summary>T-207 (AC1, AC2): TLS verification settings, the Production transport guard and pool sizes. No database needed.</summary>
public class DatabaseSettingsTests
{
    private const string Plain = "Host=h;Database=zaghlol;Username=u;Password=p";
    private const string Full = "Host=h;Database=zaghlol;Username=u;Password=p;SSL Mode=VerifyFull";

    [Theory]
    [InlineData("Disable")]
    [InlineData("Prefer")]
    [InlineData("Require")]
    public void ProductionRefusesUnverifiedTransport(string mode)
    {
        var errors = new DatabaseSettings().Validate([(DatabaseRole.App, $"{Plain};SSL Mode={mode}")], production: true);

        Assert.Single(errors);
        Assert.DoesNotContain("Password", errors[0], StringComparison.Ordinal);
    }

    [Fact]
    public void ProductionRefusesTheDefaultSslMode() =>
        Assert.NotEmpty(new DatabaseSettings().Validate([(DatabaseRole.Migrator, Plain)], production: true));

    [Theory]
    [InlineData("VerifyFull")]
    [InlineData("VerifyCA")]
    public void ProductionAcceptsVerifyingModes(string mode) =>
        Assert.Empty(new DatabaseSettings().Validate([(DatabaseRole.App, $"{Plain};SSL Mode={mode}")], production: true));

    [Fact]
    public void DevelopmentAndTheExplicitPrivateNetworkEscapeAreAllowed()
    {
        Assert.Empty(new DatabaseSettings().Validate([(DatabaseRole.App, Plain)], production: false));
        Assert.Empty(new DatabaseSettings { AllowInsecureTransport = true }.Validate([(DatabaseRole.App, Plain)], production: true));
    }

    [Theory]
    [InlineData("Production", true)]
    [InlineData("Staging", true)]
    [InlineData("Development", false)]
    [InlineData("Testing", false)]
    public void TheTlsGuardCoversProductionAndStagingOnly(string environment, bool required)
    {
        var host = new Microsoft.Extensions.Hosting.Internal.HostingEnvironment { EnvironmentName = environment };
        Assert.Equal(required, DatabaseSettings.RequiresVerifiedTls(host));
        Assert.False(DatabaseSettings.RequiresVerifiedTls(null));
    }

    [Fact]
    public void ACaCertificateNeedsAVerifyingMode()
    {
        var settings = new DatabaseSettings { CaCertificatePem = NewCertificatePem() };

        Assert.NotEmpty(settings.Validate([(DatabaseRole.App, $"{Plain};SSL Mode=Require")], production: false));
        Assert.Empty(settings.Validate([(DatabaseRole.App, Full)], production: true));
    }

    [Fact]
    public void PemAndPathAreExclusiveAndBadPemIsReportedWithoutItsText()
    {
        var both = new DatabaseSettings { CaCertificatePem = NewCertificatePem(), CaCertificatePath = "/x/ca.pem" };
        Assert.Single(both.Validate([(DatabaseRole.App, Full)], production: true));

        var bad = new DatabaseSettings { CaCertificatePem = "not a certificate" };
        var errors = bad.Validate([(DatabaseRole.App, Full)], production: true);
        Assert.Single(errors);
        Assert.DoesNotContain("not a certificate", errors[0], StringComparison.Ordinal);
    }

    [Fact]
    public void ThePemMayCarryLiteralBackslashN()
    {
        var oneLine = NewCertificatePem().Replace("\n", "\\n", StringComparison.Ordinal);

        Assert.Single(new DatabaseSettings { CaCertificatePem = oneLine }.LoadCaCertificates()!);
    }

    [Fact]
    public void TheCaCanComeFromAFileAndABundleHoldsEveryCertificate()
    {
        var path = Path.Combine(Path.GetTempPath(), $"zaghlol-ca-{Guid.NewGuid():N}.pem");
        try
        {
            File.WriteAllText(path, NewCertificatePem() + NewCertificatePem());

            Assert.Equal(2, new DatabaseSettings { CaCertificatePath = path }.LoadCaCertificates()!.Count);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void PoolDefaultsFitTheFreePlanBudget()
    {
        // API (App 5 + Admin 1 + readiness probe 1) + Worker 3 = 10 runtime connections; migrator 2 only during a deploy.
        var runtime = DatabaseSettings.DefaultMaxPoolSize(DatabaseRole.App) + DatabaseSettings.DefaultMaxPoolSize(DatabaseRole.Admin)
            + DatabaseSettings.DefaultMaxPoolSize(DatabaseRole.Worker) + 1;
        Assert.True(runtime <= 10);
        Assert.InRange(DatabaseSettings.DefaultMaxPoolSize(DatabaseRole.Migrator), 1, 2);

        using var source = ZaghlolDbContextOptions.CreateDataSource(Full, DatabaseRole.App, new DatabaseSettings());
        Assert.Equal(5, new NpgsqlConnectionStringBuilder(source.ConnectionString).MaxPoolSize);
    }

    [Fact]
    public void ThePoolSizeComesFromSettingThenConnectionStringThenDefault()
    {
        var settings = DatabaseSettings.From(new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?> { ["Database:MaxPoolSize:Worker"] = "2" }).Build());

        using var fromSetting = ZaghlolDbContextOptions.CreateDataSource($"{Full};Maximum Pool Size=9", DatabaseRole.Worker, settings);
        using var fromString = ZaghlolDbContextOptions.CreateDataSource($"{Full};Maximum Pool Size=7", DatabaseRole.App, settings);

        Assert.Equal(2, new NpgsqlConnectionStringBuilder(fromSetting.ConnectionString).MaxPoolSize);
        Assert.Equal(7, new NpgsqlConnectionStringBuilder(fromString.ConnectionString).MaxPoolSize);
    }

    [Fact]
    public void AZeroPoolSizeIsRejected() =>
        Assert.NotEmpty(new DatabaseSettings { MaxPoolSize = { ["App"] = 0 } }.Validate([(DatabaseRole.App, Full)], production: false));

    [Fact]
    public void TheHostRefusesToStartInProductionWithoutVerifiedTls()
    {
        var provider = BuildProvider("Production", $"{Plain};SSL Mode=Require");

        Assert.Throws<OptionsValidationException>(() => provider.GetRequiredService<IOptions<DatabaseConnectionOptions>>().Value);
    }

    [Fact]
    public void TheHostStartsInProductionWithVerifyFullAndAConfiguredCa()
    {
        var provider = BuildProvider("Production", Full, ("Database:CaCertificatePem", NewCertificatePem()));

        var options = provider.GetRequiredService<IOptions<DatabaseConnectionOptions>>().Value;
        Assert.True(options.IsProduction);
        using var source = provider.GetRequiredKeyedService<NpgsqlDataSource>(DatabaseRole.App);
        Assert.Equal(SslMode.VerifyFull, new NpgsqlConnectionStringBuilder(source.ConnectionString).SslMode);
    }

    private static ServiceProvider BuildProvider(string environment, string connectionString, params (string Key, string Value)[] extra)
    {
        var values = new Dictionary<string, string?> { ["ConnectionStrings:App"] = connectionString };
        foreach (var (key, value) in extra)
        {
            values[key] = value;
        }

        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(new ConfigurationBuilder().AddInMemoryCollection(values).Build());
        services.AddSingleton<IHostEnvironment>(new FakeEnvironment(environment));
        services.AddLogging();
        services.AddZaghlolDatabase(DatabaseRole.App);
        return services.BuildServiceProvider();
    }

    private static string NewCertificatePem()
    {
        using var key = RSA.Create(2048);
        var request = new CertificateRequest("CN=test-ca", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        using var certificate = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddDays(30));
        return certificate.ExportCertificatePem() + "\n";
    }

    private sealed class FakeEnvironment(string name) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = name;

        public string ApplicationName { get; set; } = "test";

        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;

        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = null!;
    }
}
