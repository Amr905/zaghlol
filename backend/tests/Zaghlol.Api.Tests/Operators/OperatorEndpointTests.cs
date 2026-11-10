using System.Globalization;
using System.Net;
using System.Reflection;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Application.Catalog;
using Zaghlol.Application.Flags;
using Zaghlol.Application.Support;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;
using OperatorRoles = Zaghlol.Application.Operators.OperatorRoles;

namespace Zaghlol.Api.Tests.Operators;

/// <summary>
/// T-136 acceptance through the real API, the real OIDC validator (fake issuer) and PostgreSQL: refused tokens are 401
/// (AC1), every admin write leaves exactly one audit row naming the operator and a failed audit insert fails the write
/// (AC2), <c>support_viewer</c> can't call any write (AC5), the e-mail lookup audits only the HMAC pseudonym and the
/// account and the e-mail reaches no log or span (AC6), the install lookup's seat fields and that no other install's ID
/// is returned (AC7), the lookup body rules, the per-operator lookup bucket, and that <c>/v1</c> can't reach admin code
/// (FU-021).
/// </summary>
[Collection(ApiHostGroup.Name)]
public class OperatorEndpointTests(OperatorHostFixture fixture) : IClassFixture<OperatorHostFixture>
{
    private const string Lookup = "/admin/v1/support/entitlement:lookup";
    private const string LookupKey = "POST " + Lookup;
    private const string PutDraft = "PUT /admin/v1/catalog/draft/{entity}/{id}";
    private const string CreateDraft = "POST /admin/v1/catalog/draft/{entity}";
    private const string DeleteDraft = "DELETE /admin/v1/catalog/draft/{entity}/{id}";
    private const string Publish = "POST /admin/v1/catalog/publish";
    private const string PutFlag = "PUT /admin/v1/flags/{key}";
    private const string PutPriceOverride = "PUT /admin/v1/prices/override";

    private static readonly string[] AllOperatorRoles =
        [OperatorRoles.CatalogEditor, OperatorRoles.FlagsAdmin, OperatorRoles.PricesAdmin, OperatorRoles.SupportViewer];

    /// <summary>Every admin operation that changes state or is audited, with a valid call. A new one fails the test below.</summary>
    private static readonly string[] AuditedOperations = [PutDraft, CreateDraft, DeleteDraft, Publish, PutFlag, PutPriceOverride, LookupKey];

    [Fact]
    public async Task AValidMfaTokenWithTheRoleIsServed()
    {
        var (_, subject) = await fixture.NewOperatorAsync(OperatorRoles.FlagsAdmin);

        using var response = await fixture.SendAsync(HttpMethod.Get, "/admin/v1/flags/zakah", fixture.Token(subject));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Theory]
    [InlineData("no_mfa")]
    [InlineData("wrong_audience")]
    [InlineData("alg_none")]
    [InlineData("hs256")]
    [InlineData("expired")]
    [InlineData("over_one_hour")]
    [InlineData("disabled")]
    [InlineData("unknown_subject")]
    public async Task ARefusedTokenIs401WithTheSingleBody(string defect)
    {
        var (id, subject) = await fixture.NewOperatorAsync(OperatorRoles.FlagsAdmin);
        var now = DateTimeOffset.UtcNow;
        var spec = new OperatorTokenSpec { Subject = subject };
        if (defect == "disabled")
        {
            await fixture.ExecuteAsync("UPDATE zaghlol.operators SET disabled_at = now() WHERE id = @id", ("id", id));
        }

        var token = fixture.Issuer.Mint(
            defect switch
            {
                "no_mfa" => spec with { Amr = ["pwd"] },
                "wrong_audience" => spec with { Audience = "another-client" },
                "alg_none" => spec with { Algorithm = "none" },
                "hs256" => spec with { Algorithm = "HS256" },
                "expired" => spec with { IssuedAt = now.AddHours(-2) },
                "over_one_hour" => spec with { LifetimeSeconds = 7200 },
                "unknown_subject" => spec with { Subject = "sub-nobody" },
                _ => spec,
            },
            now);

        using var response = await fixture.SendAsync(HttpMethod.Get, "/admin/v1/flags/zakah", token);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        var body = JsonNode.Parse(await response.Content.ReadAsStringAsync())!;
        Assert.Equal("UNAUTHORIZED", body["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task EveryAdminWriteLeavesExactlyOneAuditRowNamingTheOperator()
    {
        var operations = fixture.Endpoints("/admin/v1/").Where(e => e.Method != "GET").Select(e => e.Key).ToHashSet(StringComparer.Ordinal);
        Assert.Equal(AuditedOperations.Order(StringComparer.Ordinal), operations.Order(StringComparer.Ordinal));

        foreach (var operation in operations)
        {
            var (id, subject) = await fixture.NewOperatorAsync(AllOperatorRoles);
            var (before, response) = await PerformAsync(operation, id, subject);
            using (response)
            {
                Assert.True(response.IsSuccessStatusCode, $"{operation}: {(int)response.StatusCode} {await response.Content.ReadAsStringAsync()}");
            }

            Assert.True(before + 1 == await fixture.AuditCountAsync(id), operation);
        }
    }

    [Fact]
    public async Task AFailedAuditInsertFailsTheWrite()
    {
        var (id, subject) = await fixture.NewOperatorAsync(OperatorRoles.FlagsAdmin);
        var versionBefore = await fixture.ScalarAsync("SELECT version FROM zaghlol.feature_flags WHERE key = 'smart_roi'");

        await fixture.ExecuteAsync("REVOKE INSERT ON zaghlol.audit_log FROM ops_rw");
        HttpStatusCode status;
        try
        {
            using var response = await fixture.SendAsync(HttpMethod.Put, "/admin/v1/flags/smart_roi", fixture.Token(subject), "{\"value\":true}");
            status = response.StatusCode;
        }
        finally
        {
            await fixture.ExecuteAsync("GRANT INSERT ON zaghlol.audit_log TO ops_rw");
        }

        Assert.True((int)status >= 500, $"expected a 5xx, got {(int)status}");
        Assert.Equal(versionBefore, await fixture.ScalarAsync("SELECT version FROM zaghlol.feature_flags WHERE key = 'smart_roi'"));
        Assert.Equal(0L, await fixture.AuditCountAsync(id));
    }

    [Fact]
    public async Task SupportViewerIsForbiddenOnEveryWriteOperation()
    {
        var (id, subject) = await fixture.NewOperatorAsync(OperatorRoles.SupportViewer);
        var writes = fixture.Endpoints("/admin/v1/").Where(e => e.Method != "GET" && e.Key != LookupKey).ToList();
        Assert.NotEmpty(writes);

        foreach (var write in writes)
        {
            Assert.DoesNotContain(OperatorRoles.SupportViewer, write.Roles);
            var path = write.Route.Replace("{entity}", "categories", StringComparison.Ordinal)
                .Replace("{id}", "t136_forbidden", StringComparison.Ordinal)
                .Replace("{key}", FlagKeys.Zakah, StringComparison.Ordinal);
            using var response = await fixture.SendAsync(new HttpMethod(write.Method), path, fixture.Token(subject), "{}");
            Assert.True(response.StatusCode == HttpStatusCode.Forbidden, $"{write.Key}: {(int)response.StatusCode}");
        }

        Assert.Equal(0L, await fixture.AuditCountAsync(id));
    }

    [Fact]
    public async Task TheLookupNeedsSupportViewerItself()
    {
        foreach (var role in new[] { OperatorRoles.SupportAgent, OperatorRoles.SupportLead, OperatorRoles.CatalogEditor })
        {
            var (_, subject) = await fixture.NewOperatorAsync(role);
            using var response = await fixture.SendAsync(HttpMethod.Post, Lookup, fixture.Token(subject), InstallBody(Guid.NewGuid()));
            Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        }
    }

    [Fact]
    public async Task AnEmailLookupAuditsThePseudonymAndTheAccountNeverTheEmail()
    {
        var marker = "t136mark" + Guid.NewGuid().ToString("N")[..10];
        var stored = $"Op.{marker}@Example.COM";
        var account = Guid.CreateVersion7();
        var purchase = Guid.NewGuid();
        await fixture.ExecuteAsync(
            "INSERT INTO zaghlol.accounts (id, provider, provider_subject, email) VALUES (@id, 'google', @subject, @email)",
            ("id", account),
            ("subject", Guid.NewGuid().ToString("N")),
            ("email", stored));
        await InsertPurchaseAsync(purchase, buyer: null, account: account);

        var (id, subject) = await fixture.NewOperatorAsync(OperatorRoles.SupportViewer);
        using var response = await fixture.SendAsync(HttpMethod.Post, Lookup, fixture.Token(subject), "{\"email\":\"  op." + marker + "@example.com \"}");

        var text = await response.Content.ReadAsStringAsync();
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = JsonNode.Parse(text)!;
        var listed = Assert.Single(body["purchases"]!.AsArray());
        Assert.Equal(purchase.ToString(), listed!["purchaseId"]!.GetValue<string>());
        Assert.Null(listed["isBuyingInstall"]);
        Assert.Equal("vacant", listed["seat"]!.GetValue<string>());
        Assert.True(listed["accountLinked"]!.GetValue<bool>());
        Assert.DoesNotContain(marker, text, StringComparison.OrdinalIgnoreCase);

        var normalized = "op." + marker + "@example.com";
        var mac = await fixture.Services.GetRequiredService<IKeyedHasher>()
            .HmacSha256Async(KeyedHashKey.Audit, Encoding.UTF8.GetBytes(normalized), CancellationToken.None);
        var target = (string)(await fixture.ScalarAsync(
            "SELECT target FROM zaghlol.audit_log WHERE operator_id = @id AND action = 'support_lookup'", ("id", id)))!;
        Assert.Equal("email:" + Convert.ToHexStringLower(mac), target);
        Assert.Matches("^email:[0-9a-f]{64}$", target);
        Assert.Equal(account.ToString(), await fixture.ScalarAsync(
            "SELECT details ->> 'account_id' FROM zaghlol.audit_log WHERE operator_id = @id", ("id", id)));

        // Nowhere in the audit table, the logs or the exported spans.
        Assert.Equal(0L, await fixture.ScalarAsync(
            "SELECT count(*) FROM zaghlol.audit_log a WHERE a::text ILIKE '%' || @marker || '%'", ("marker", marker)));
        await Task.Delay(500);
        Assert.NotEmpty(fixture.Logs.Entries);
        Assert.DoesNotContain(fixture.Logs.Entries, e => e.Contains(marker, StringComparison.OrdinalIgnoreCase));
        Assert.NotEmpty(fixture.Spans.Snapshot());
        Assert.DoesNotContain(fixture.Spans.Snapshot(), s => Describe(s).Contains(marker, StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task AnEmailWithNoAccountIsAnEmptyAuditedAnswer()
    {
        var (id, subject) = await fixture.NewOperatorAsync(OperatorRoles.SupportViewer);

        using var response = await fixture.SendAsync(HttpMethod.Post, Lookup, fixture.Token(subject), "{\"email\":\"nobody-t136@example.com\"}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = JsonNode.Parse(await response.Content.ReadAsStringAsync())!;
        Assert.Equal("none", body["status"]!.GetValue<string>());
        Assert.Empty(body["purchases"]!.AsArray());
        Assert.Equal(1L, await fixture.AuditCountAsync(id));
        Assert.Null(await fixture.ScalarAsync("SELECT details ->> 'account_id' FROM zaghlol.audit_log WHERE operator_id = @id", ("id", id)));
    }

    [Fact]
    public async Task AnInstallLookupShowsTheSeatAndNeverAnotherInstallsId()
    {
        var buyer = Guid.NewGuid();
        var holder = Guid.NewGuid();
        var claimant = Guid.NewGuid();
        var purchase = Guid.NewGuid();
        var now = DateTimeOffset.UtcNow;
        await InsertInstallAsync(buyer, lastSeen: now.AddDays(-40));
        await InsertInstallAsync(holder, lastSeen: now);
        await InsertInstallAsync(claimant, lastSeen: now);
        await InsertPurchaseAsync(purchase, buyer: buyer, account: null, disputeFrozenUntil: now.AddDays(10));
        var nextMove = new DateTimeOffset(now.AddDays(29).Year, now.AddDays(29).Month, now.AddDays(29).Day, 3, 0, 0, TimeSpan.Zero);
        await fixture.ExecuteAsync(
            "INSERT INTO zaghlol.purchase_seats (purchase_id, install_id, proof, bound_at, last_moved_at, next_move_at, recent_rebinds) "
            + "VALUES (@p, @i, 'basic', @now, @moved, @next, ARRAY[@r1, @r2]::timestamptz[])",
            ("p", purchase),
            ("i", holder),
            ("now", now),
            ("moved", now.AddDays(-1)),
            ("next", nextMove),
            ("r1", now.AddDays(-2)),
            ("r2", now.AddDays(-45)));
        await fixture.ExecuteAsync(
            "INSERT INTO zaghlol.seat_claimants (purchase_id, install_id, claimed_at, channel) VALUES (@p, @i, @at, 'restore')",
            ("p", purchase),
            ("i", claimant),
            ("at", now.AddDays(-1)));

        var (_, subject) = await fixture.NewOperatorAsync(OperatorRoles.SupportViewer);
        var asBuyer = await LookupAsync(subject, buyer, holder, claimant);
        var asHolder = await LookupAsync(subject, holder, buyer, claimant);
        var asClaimant = await LookupAsync(subject, claimant, buyer, holder);

        Assert.Equal("moved", asBuyer["status"]!.GetValue<string>());
        var bought = asBuyer["purchases"]![0]!;
        Assert.Equal("none", bought["seat"]!.GetValue<string>());
        Assert.True(bought["isBuyingInstall"]!.GetValue<bool>());
        Assert.True(bought["buyingInstallSilent"]!.GetValue<bool>());
        Assert.Equal(1, bought["pendingClaimants"]!.GetValue<int>());
        Assert.Equal(1, bought["rebindsLast30Days"]!.GetValue<int>());
        Assert.False(bought["accountLinked"]!.GetValue<bool>());
        Assert.Null(bought["linkedBy"]);
        Assert.NotNull(bought["disputeFrozenUntil"]);
        Assert.NotNull(bought["nextMoveAt"]);

        Assert.Equal("active", asHolder["status"]!.GetValue<string>());
        Assert.Equal("holder", asHolder["purchases"]![0]!["seat"]!.GetValue<string>());
        Assert.False(asHolder["purchases"]![0]!["isBuyingInstall"]!.GetValue<bool>());
        Assert.Equal("monthly", asHolder["plan"]!.GetValue<string>());

        Assert.Equal("claimant", asClaimant["purchases"]![0]!["seat"]!.GetValue<string>());

        // The fourth lookup by the same operator hits the per-operator lookup bucket; another operator is unaffected.
        using var limited = await fixture.SendAsync(HttpMethod.Post, Lookup, fixture.Token(subject), InstallBody(buyer));
        Assert.Equal(HttpStatusCode.TooManyRequests, limited.StatusCode);
        var (_, other) = await fixture.NewOperatorAsync(OperatorRoles.SupportViewer);
        using var fresh = await fixture.SendAsync(HttpMethod.Post, Lookup, fixture.Token(other), InstallBody(buyer));
        Assert.Equal(HttpStatusCode.OK, fresh.StatusCode);
    }

    [Theory]
    [InlineData("{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"note\":\"x\"}", "UNKNOWN_FIELD")]
    [InlineData("{\"accountId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\"}", "UNKNOWN_FIELD")]
    [InlineData("{\"installId\":\"0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77\",\"email\":\"a@b.example\"}", "VALIDATION_FAILED")]
    [InlineData("{}", "VALIDATION_FAILED")]
    [InlineData("{\"installId\":\"not-an-install\"}", "VALIDATION_FAILED")]
    [InlineData("{\"installId\":null}", "VALIDATION_FAILED")]
    [InlineData("{\"email\":\"no-at-sign\"}", "VALIDATION_FAILED")]
    [InlineData("{\"email\":\"a@b@c.example\"}", "VALIDATION_FAILED")]
    [InlineData("{\"email\":\"a@b.example\",\"email\":\"c@d.example\"}", "VALIDATION_FAILED")]
    [InlineData("[]", "VALIDATION_FAILED")]
    public async Task TheLookupBodyHoldsExactlyOneKnownKey(string body, string code)
    {
        var (id, subject) = await fixture.NewOperatorAsync(OperatorRoles.SupportViewer);

        using var response = await fixture.SendAsync(HttpMethod.Post, Lookup, fixture.Token(subject), body);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var text = await response.Content.ReadAsStringAsync();
        Assert.Equal(code, JsonNode.Parse(text)!["code"]!.GetValue<string>());
        Assert.DoesNotContain("example", text, StringComparison.Ordinal);
        Assert.Equal(0L, await fixture.AuditCountAsync(id));
    }

    [Fact]
    public async Task V1EndpointsNeverTakeAdminServicesAndEveryAdminEndpointNeedsAnOperatorRole()
    {
        // FU-021: /v1 handlers can't obtain the Admin login. Their stores come from IAppDbContextFactory (App only), and no
        // /v1 handler takes an admin port. Every /admin/v1 endpoint requires exactly one operator role.
        Type[] adminPorts = [typeof(ICatalogAdminStore), typeof(FlagAdminService), typeof(IFlagAdminStore), typeof(ISupportLookupStore)];
        var source = fixture.Services.GetRequiredService<EndpointDataSource>();
        var v1 = source.Endpoints.OfType<RouteEndpoint>().Where(e => OperatorHostFixture.Template(e.RoutePattern).StartsWith("/v1/", StringComparison.Ordinal)).ToList();
        Assert.NotEmpty(v1);
        foreach (var endpoint in v1)
        {
            var handler = endpoint.Metadata.GetMetadata<MethodInfo>();
            Assert.NotNull(handler);
            Assert.DoesNotContain(handler.GetParameters(), p => adminPorts.Contains(p.ParameterType));
            Assert.DoesNotContain(endpoint.Metadata.OfType<Microsoft.AspNetCore.Authorization.IAuthorizeData>(), a => a.Policy?.StartsWith(Auth.OperatorAuthentication.PolicyPrefix, StringComparison.Ordinal) == true);
        }

        var admin = fixture.Endpoints("/admin/v1/");
        Assert.NotEmpty(admin);
        Assert.All(admin, e => Assert.True(e.Roles.Count == 1 && OperatorRoles.IsKnown(e.Roles[0]), e.Key));
    }

    private static string InstallBody(Guid installId) => "{\"installId\":\"" + installId.ToString("D") + "\"}";

    private static string NewCode() => "t136_" + Guid.NewGuid().ToString("N")[..10];

    private static string CategoryBody =>
        "{\"nameAr\":\"اختبار\",\"nameEn\":\"Test\",\"icon\":\"tag\",\"color\":\"#0F7A55\",\"bucket\":\"wants\",\"sort\":1}";

    private static string MerchantBody(string category) =>
        "{\"canonical\":\"T136 Merchant " + Guid.NewGuid().ToString("N")[..10] + "\",\"nameAr\":\"مطعم\",\"category\":\"" + category + "\"}";

    private static string Describe(System.Diagnostics.Activity activity)
    {
        var text = new StringBuilder(activity.DisplayName).Append('|').Append(activity.StatusDescription).Append('|');
        foreach (var (key, value) in activity.TagObjects)
        {
            text.Append(key).Append('=').Append(Convert.ToString(value, CultureInfo.InvariantCulture)).Append(';');
        }

        foreach (var activityEvent in activity.Events)
        {
            text.Append(activityEvent.Name).Append(';');
            foreach (var (key, value) in activityEvent.Tags)
            {
                text.Append(key).Append('=').Append(Convert.ToString(value, CultureInfo.InvariantCulture)).Append(';');
            }
        }

        return text.ToString();
    }

    private async Task<JsonNode> LookupAsync(string subject, Guid installId, params Guid[] others)
    {
        using var response = await fixture.SendAsync(HttpMethod.Post, Lookup, fixture.Token(subject), InstallBody(installId));
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(response.StatusCode == HttpStatusCode.OK, text);
        foreach (var other in others)
        {
            Assert.DoesNotContain(other.ToString("D"), text, StringComparison.OrdinalIgnoreCase);
        }

        return JsonNode.Parse(text)!;
    }

    private Task InsertInstallAsync(Guid id, DateTimeOffset lastSeen) =>
        fixture.ExecuteAsync(
            "INSERT INTO zaghlol.installs (id, token_hash, platform, app_version, first_seen_at, last_seen_at) "
            + "VALUES (@id, @hash, 'android', '1.0.0', @seen, @seen)",
            ("id", id),
            ("hash", System.Security.Cryptography.RandomNumberGenerator.GetBytes(32)),
            ("seen", lastSeen));

    private Task InsertPurchaseAsync(Guid id, Guid? buyer, Guid? account, DateTimeOffset? disputeFrozenUntil = null) =>
        fixture.ExecuteAsync(
            "INSERT INTO zaghlol.purchases (id, store, product_id, plan, store_key, state, environment, last_verified_at, install_id, "
            + "account_id, account_linked_by, dispute_frozen_until) VALUES (@id, 'google_play', 'zaghlol_gold_monthly', 'monthly', @key, "
            + "'active', 'production', now(), @buyer, @account, @linked, @frozen)",
            ("id", id),
            ("key", "t136-store-key-" + Guid.NewGuid().ToString("N")),
            ("buyer", (object?)buyer ?? DBNull.Value),
            ("account", (object?)account ?? DBNull.Value),
            ("linked", account is null ? DBNull.Value : (object)"signin"),
            ("frozen", (object?)disputeFrozenUntil ?? DBNull.Value));

    private async Task<(long Before, HttpResponseMessage Response)> PerformAsync(string operation, Guid operatorId, string subject)
    {
        string Token() => fixture.Token(subject);
        switch (operation)
        {
            case PutDraft:
                return (await fixture.AuditCountAsync(operatorId), await fixture.SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/categories/" + NewCode(), Token(), CategoryBody));
            case CreateDraft:
                {
                    var code = NewCode();
                    (await fixture.SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/categories/" + code, Token(), CategoryBody)).Dispose();
                    return (await fixture.AuditCountAsync(operatorId), await fixture.SendAsync(HttpMethod.Post, "/admin/v1/catalog/draft/merchants", Token(), MerchantBody(code)));
                }

            case DeleteDraft:
                {
                    var code = NewCode();
                    (await fixture.SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/categories/" + code, Token(), CategoryBody)).Dispose();
                    return (await fixture.AuditCountAsync(operatorId), await fixture.SendAsync(HttpMethod.Delete, "/admin/v1/catalog/draft/categories/" + code, Token()));
                }

            case Publish:
                (await fixture.SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/categories/" + NewCode(), Token(), CategoryBody)).Dispose();
                return (await fixture.AuditCountAsync(operatorId), await fixture.SendAsync(HttpMethod.Post, "/admin/v1/catalog/publish", Token(), "{}"));
            case PutFlag:
                return (await fixture.AuditCountAsync(operatorId), await fixture.SendAsync(HttpMethod.Put, "/admin/v1/flags/zakah", Token(), "{\"value\":true}"));
            case PutPriceOverride:
                return (await fixture.AuditCountAsync(operatorId), await fixture.SendAsync(HttpMethod.Put, "/admin/v1/prices/override", Token(), "{\"symbol\":\"XAU21_G\",\"currency\":\"EGP\",\"price\":\"4217.50\",\"reason\":\"Audit coverage test\"}"));
            case LookupKey:
                return (await fixture.AuditCountAsync(operatorId), await fixture.SendAsync(HttpMethod.Post, Lookup, Token(), InstallBody(Guid.NewGuid())));
            default:
                throw new InvalidOperationException("No audited call for " + operation + ": add one here.");
        }
    }
}
