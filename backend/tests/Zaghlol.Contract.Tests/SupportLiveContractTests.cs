using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using Zaghlol.Api.Auth;
using Zaghlol.Testing;

namespace Zaghlol.Contract.Tests;

/// <summary>The real API over a migrated PostgreSQL 17 with a fake operator validator, for the support lookup contract tests.</summary>
public sealed class SupportContractFixture : IAsyncLifetime
{
    private readonly FakeKms kms = FakeKms.CreateDefault();
    private readonly ContractOperatorValidator operators = new();
    private WebApplicationFactory<Program>? factory;

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public HttpClient Client { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseSetting("ConnectionStrings:App", Database.Api);
            builder.UseSetting("ConnectionStrings:Admin", Database.Admin);
            builder.UseSetting("RateLimits:SupportLookup:TokenLimit", "1000");
            builder.UseSetting("RateLimits:SupportLookup:TokensPerPeriod", "1000");
            builder.UseSetting("RateLimits:SupportLookup:PeriodSeconds", "60");
            foreach (var (key, value) in kms.Settings())
            {
                builder.UseSetting(key, value);
            }

            builder.ConfigureServices(services =>
            {
                kms.Use(services);
                services.RemoveAll<IOperatorTokenValidator>();
                services.AddSingleton<IOperatorTokenValidator>(operators);
            });
        });
        Client = factory.CreateClient();
    }

    public async Task DisposeAsync()
    {
        Client?.Dispose();
        if (factory is not null)
        {
            await factory.DisposeAsync();
        }

        if (Database is not null)
        {
            await Database.DisposeAsync();
        }

        kms.Dispose();
    }

    internal async Task<string> OperatorTokenAsync(params string[] roles)
    {
        var id = Guid.NewGuid();
        await ZaghlolTestDatabase.ExecuteAsync(
            Database.Migrator,
            string.Create(
                CultureInfo.InvariantCulture,
                $"INSERT INTO zaghlol.operators (id, oidc_subject, display_name, roles) VALUES ('{id}', 'sub-{id}', 'Contract test', ARRAY['{string.Join("','", roles)}'])"));
        return operators.Issue(id, roles);
    }

    /// <summary>An install holding the seat of an account-linked, in-grace purchase with a running dispute freeze.</summary>
    internal async Task<(Guid Install, string Email)> SeedAsync()
    {
        var install = Guid.NewGuid();
        var account = Guid.NewGuid();
        var purchase = Guid.NewGuid();
        var email = "contract-" + Guid.NewGuid().ToString("N")[..8] + "@example.com";
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            """
            INSERT INTO zaghlol.installs (id, token_hash, platform, app_version) VALUES (@install, @hash, 'ios', '1.2.0');
            INSERT INTO zaghlol.accounts (id, provider, provider_subject, email) VALUES (@account, 'apple', @subject, @email);
            INSERT INTO zaghlol.purchases (id, store, product_id, plan, store_key, state, expires_at, environment, last_verified_at,
                                           install_id, account_id, account_linked_by, dispute_frozen_until)
              VALUES (@purchase, 'app_store', 'zaghlol_gold_yearly', 'yearly', @key, 'in_grace', now() + interval '3 days',
                      'production', now(), @install, @account, 'signin', now() + interval '20 days');
            INSERT INTO zaghlol.purchase_seats (purchase_id, install_id, proof, bound_at) VALUES (@purchase, @install, 'attested', now());
            """,
            connection);
        command.Parameters.AddWithValue("install", install);
        command.Parameters.AddWithValue("hash", System.Security.Cryptography.RandomNumberGenerator.GetBytes(32));
        command.Parameters.AddWithValue("account", account);
        command.Parameters.AddWithValue("subject", Guid.NewGuid().ToString("N"));
        command.Parameters.AddWithValue("email", email);
        command.Parameters.AddWithValue("purchase", purchase);
        command.Parameters.AddWithValue("key", "contract-" + Guid.NewGuid().ToString("N"));
        await command.ExecuteNonQueryAsync();
        return (install, email);
    }
}

/// <summary>
/// FU-011 for <c>adminLookupEntitlement</c> (T-136): every status the live API answers is declared by the operation, and
/// every body validates against its schema (<c>SupportEntitlement</c> or <c>Problem</c>), including
/// <c>400 UNKNOWN_FIELD</c>.
/// </summary>
public class SupportLiveContractTests(SupportContractFixture fixture) : IClassFixture<SupportContractFixture>
{
    private const string Path = "/admin/v1/support/entitlement:lookup";
    private const string Json = "application/json";
    private const string Problem = "application/problem+json";

    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private static SpecOperation Lookup => Spec.Operations().Single(o => o.Id == "adminLookupEntitlement");

    [Fact]
    public async Task InstallAndEmailLookupsConformToSupportEntitlement()
    {
        var token = await fixture.OperatorTokenAsync("support_viewer");
        var (install, email) = await fixture.SeedAsync();
        var byInstall = "{\"installId\":\"" + install.ToString("D") + "\"}";
        var byEmail = "{\"email\":\"" + email + "\"}";
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(Lookup)!, JsonNode.Parse(byInstall)));
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(Lookup)!, JsonNode.Parse(byEmail)));

        using var installResponse = await SendAsync(token, byInstall);
        using var emailResponse = await SendAsync(token, byEmail);

        var installBody = await AssertDeclared(installResponse, HttpStatusCode.OK, Json);
        var emailBody = await AssertDeclared(emailResponse, HttpStatusCode.OK, Json);
        Assert.Equal("grace", installBody!["status"]!.GetValue<string>());
        Assert.Equal("holder", installBody["purchases"]![0]!["seat"]!.GetValue<string>());
        Assert.NotNull(installBody["graceUntil"]);
        Assert.Equal("held", emailBody!["purchases"]![0]!["seat"]!.GetValue<string>());
        Assert.Null(emailBody["purchases"]![0]!["isBuyingInstall"]);
        Assert.True(installResponse.Headers.CacheControl?.NoStore);
    }

    [Fact]
    public async Task ErrorsAreDeclaredProblems()
    {
        var viewer = await fixture.OperatorTokenAsync("support_viewer");
        var editor = await fixture.OperatorTokenAsync("catalog_editor");

        using var unknown = await SendAsync(viewer, "{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"extra\":1}");
        using var both = await SendAsync(viewer, "{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"email\":\"a@b.example\"}");
        using var anonymous = await SendAsync(null, "{\"email\":\"a@b.example\"}");
        using var forbidden = await SendAsync(editor, "{\"email\":\"a@b.example\"}");
        using var wrongType = await SendAsync(viewer, "{\"email\":\"a@b.example\"}", "text/plain");

        Assert.Equal("UNKNOWN_FIELD", (await AssertDeclared(unknown, HttpStatusCode.BadRequest, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("VALIDATION_FAILED", (await AssertDeclared(both, HttpStatusCode.BadRequest, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("UNAUTHORIZED", (await AssertDeclared(anonymous, HttpStatusCode.Unauthorized, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("FORBIDDEN", (await AssertDeclared(forbidden, HttpStatusCode.Forbidden, Problem))!["code"]!.GetValue<string>());
        await AssertDeclared(wrongType, HttpStatusCode.UnsupportedMediaType, Problem);
    }

    private static async Task<JsonNode?> AssertDeclared(HttpResponseMessage response, HttpStatusCode status, string mediaType)
    {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(status == response.StatusCode, $"expected {(int)status}, got {(int)response.StatusCode}: {text}");
        var code = ((int)status).ToString(CultureInfo.InvariantCulture);

        Assert.True(Lookup.Body["responses"]!.AsObject().ContainsKey(code), $"{Lookup.Label} does not declare {code}");
        Assert.Equal(mediaType, response.Content.Headers.ContentType?.MediaType);
        var schema = Spec.ResponseSchema(Lookup, code, mediaType);
        Assert.NotNull(schema);
        var body = JsonNode.Parse(text);
        Assert.Null(Spec.Validate(schema, body));
        return body;
    }

    private async Task<HttpResponseMessage> SendAsync(string? token, string body, string mediaType = Json)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, Path);
        if (token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        }

        request.Content = new StringContent(body, Encoding.UTF8);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue(mediaType);
        return await fixture.Client.SendAsync(request);
    }
}
