using System.Security.Cryptography;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Serilog.Core;
using Zaghlol.Api.Auth;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests;

/// <summary>The real API with every Production setting a deployment needs, plus the KMS settings under test (T-200, T-205).</summary>
internal static class ProductionApiFactory
{
    private const string Unreachable = "Host=127.0.0.1;Port=1;Database=none;Username=none";

    /// <summary>The real Program with every Production setting a self-hosted deployment needs (public test values; also T-205).</summary>
    internal static WebApplicationFactory<Program> Create(
        string environment,
        Dictionary<string, string?> kms,
        CapturingSink logs,
        FakeOidcIssuer issuer,
        ECDsa appleKey)
    {
        var settings = new Dictionary<string, string?>(kms, StringComparer.Ordinal)
        {
            ["ConnectionStrings:App"] = Unreachable,
            ["ConnectionStrings:Admin"] = Unreachable,
            ["Purchases:Google:PackageName"] = "app.zaghlol",
            ["Purchases:Google:CredentialSource"] = "ApplicationDefault",
            ["Purchases:Google:Rtdn:Audience"] = "https://api.zaghlol.app/v1/notifications/google",
            ["Purchases:Google:Rtdn:PushServiceAccount"] = "push@zaghlol-test.iam.gserviceaccount.com",
            ["Purchases:Apple:BundleId"] = "app.zaghlol",
            ["Purchases:Apple:AllowSandbox"] = "true",
            ["Purchases:Apple:IssuerId"] = "57246542-96fe-1a63-e053-0824d011072a",
            ["Purchases:Apple:KeyId"] = "ABCDE12345",
            ["Purchases:Apple:PrivateKey"] = appleKey.ExportPkcs8PrivateKeyPem(),
            ["Accounts:Google:ClientIds:0"] = "123-abc.apps.googleusercontent.com",
            ["Accounts:Apple:ServicesId"] = "app.zaghlol.signin",
            ["Accounts:Apple:BundleId"] = "app.zaghlol",
            ["Accounts:Apple:TeamId"] = "ABCDE12345",
            ["Accounts:Apple:KeyId"] = "ABCDE12345",
            ["Accounts:Apple:PrivateKey"] = appleKey.ExportPkcs8PrivateKeyPem(),
            ["Attestation:AppAttest:TeamId"] = "ABCDE12345",
            ["OperatorAuth:Enabled"] = "true",
            ["OperatorAuth:Profile"] = "Entra",
            ["OperatorAuth:AllowedTenants:0"] = FakeOidcIssuer.TenantId,
            ["OperatorAuth:Issuer"] = FakeOidcIssuer.DefaultIssuer,
            ["OperatorAuth:Audiences:0"] = FakeOidcIssuer.CliAudience,
        };
        foreach (var (plan, kind, type) in new[] { ("monthly", "subscription", "auto_renewable"), ("yearly", "subscription", "auto_renewable"), ("lifetime", "onetime", "non_consumable") })
        {
            settings[$"Purchases:Google:Products:zaghlol_gold_{plan}:Kind"] = kind;
            settings[$"Purchases:Google:Products:zaghlol_gold_{plan}:Plan"] = plan;
            settings[$"Purchases:Apple:Products:zaghlol_gold_{plan}:Type"] = type;
            settings[$"Purchases:Apple:Products:zaghlol_gold_{plan}:Plan"] = plan;
        }

        return new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseEnvironment(environment);
            foreach (var (key, value) in settings)
            {
                builder.UseSetting(key, value);
            }

            builder.ConfigureServices(services =>
            {
                services.AddSingleton<ILogEventSink>(logs);
                services.AddHttpClient(OidcKeyCache.HttpClientName).ConfigurePrimaryHttpMessageHandler(() => issuer.CreateHandler());
            });
        });
    }
}
