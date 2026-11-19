using System.Globalization;
using System.Text.Json.Nodes;
using Zaghlol.Ops.Tests.Support;

namespace Zaghlol.Ops.Tests;

/// <summary>
/// T-137: the CLI against the real API and PostgreSQL. Every Admin operation of the OpenAPI file is run through a command, signed in
/// with the authorization-code flow against the in-process IdP, and each audited operation leaves its audit row. The store order ID
/// typed at the prompt reaches the ownership check and appears in no audit row.
/// </summary>
public class CliIntegrationTests(CliApiFixture fixture) : IClassFixture<CliApiFixture>
{
    private const string Order = "GPA.3312-5208-4571-04923";

    [Fact]
    public async Task EveryAdminOperationIsReachableFromTheCliAndLeavesItsAuditRow()
    {
        var (operatorId, subject) = await fixture.NewOperatorAsync("catalog_editor", "flags_admin", "prices_admin", "support_viewer", "support_agent");
        fixture.Idp.Subject = subject;
        using var env = NewEnvironment();

        // Sign in once (authorization code + PKCE); every later command reuses the stored token.
        var tokenRequests = fixture.Idp.TokenRequests;
        await Ok(env, "login");
        Assert.Equal(tokenRequests + 1, fixture.Idp.TokenRequests);
        Assert.Equal(["authorization_code"], fixture.Idp.GrantTypes.Distinct());

        // Reports: adminDailyActive, adminListBankRequests.
        var daily = await Json(env, "metrics", "daily-active", "--days", "3");
        Assert.Equal(3, daily["days"]!.AsArray().Count);
        var banks = await Json(env, "bank-requests", "list");
        Assert.NotNull(banks["items"]);

        // Catalog draft: put category (adminPutCatalogDraftEntry), create merchant (adminCreateDraftMerchant), alias, keyword, list, delete.
        env.Files["category.json"] = "{\"nameAr\":\"x\",\"nameEn\":\"Dining\",\"icon\":\"fork\",\"color\":\"#112233\",\"bucket\":\"wants\",\"sort\":1}";
        await Ok(env, "catalog", "draft", "put", "categories", "dining", "--file", "category.json");
        var merchant = await Json(env, "catalog", "draft", "create-merchant", "--canonical", "Koshary Cli", "--name-ar", "x", "--category", "dining");
        var merchantId = merchant["id"]!.GetValue<int>().ToString(CultureInfo.InvariantCulture);
        env.Files["alias.json"] = "{\"match\":\"exact\"}";
        await Ok(env, "catalog", "draft", "put", "aliases", "--merchant", merchantId, "--alias", "koshary cli", "--file", "alias.json");
        env.Files["keyword.json"] = "{\"category\":\"dining\",\"weight\":50}";
        await Ok(env, "catalog", "draft", "put", "keywords", "--lang", "en", "--keyword", "koshary", "--file", "keyword.json");
        var listed = await Json(env, "catalog", "draft", "list", "merchants", "--limit", "1");
        Assert.NotEmpty(listed["items"]!.AsArray());
        var all = await Json(env, "catalog", "draft", "list", "aliases", "--all");
        Assert.NotEmpty(all["items"]!.AsArray());
        await Ok(env, "catalog", "draft", "delete", "keywords", "--lang", "en", "--keyword", "koshary");
        Assert.Equal(3, await fixture.AuditAsync("catalog_draft_put", operatorId));
        Assert.Equal(1, await fixture.AuditAsync("catalog_draft_create", operatorId));
        Assert.Equal(1, await fixture.AuditAsync("catalog_draft_delete", operatorId));

        // Import: dry run changes nothing, the real run applies in order (merchant create, alias put, alias delete).
        env.Files["import.json"] =
            "{\"entries\":[{\"entity\":\"merchants\",\"body\":{\"canonical\":\"Imported One\",\"nameAr\":\"y\",\"category\":\"dining\"}},"
            + "{\"entity\":\"aliases\",\"merchant\":" + merchantId + ",\"alias\":\"imported alias\",\"body\":{\"match\":\"prefix\"}},"
            + "{\"entity\":\"aliases\",\"merchant\":" + merchantId + ",\"alias\":\"imported alias\",\"delete\":true}]}";
        var before = await fixture.AuditAsync("catalog_draft_create", operatorId);
        await Ok(env, "catalog", "import", "import.json", "--dry-run");
        Assert.Equal(before, await fixture.AuditAsync("catalog_draft_create", operatorId));
        var applied = await Json(env, "catalog", "import", "import.json");
        Assert.Equal(3, applied["applied"]!.GetValue<int>());
        Assert.Equal(before + 1, await fixture.AuditAsync("catalog_draft_create", operatorId));

        // Publish (adminPublishCatalog).
        var published = await Json(env, "catalog", "publish", "--note", "CLI test");
        Assert.True(published["version"]!.GetValue<int>() >= 1);
        Assert.Equal(1, await fixture.AuditAsync("catalog_publish", operatorId));

        // Flags (adminGetFlag, adminPutFlag).
        await fixture.ExecuteAsync("INSERT INTO zaghlol.feature_flags (key, enabled, rules, version, updated_at, updated_by) VALUES ('smart_roi', false, '{}'::jsonb, 1, now(), gen_random_uuid()) ON CONFLICT (key) DO NOTHING");
        Assert.False((await Json(env, "flags", "get", "smart_roi"))["value"]!.GetValue<bool>());
        var flag = await Json(env, "flags", "set", "smart_roi", "--value", "true", "--platforms", "android", "--min-app-version", "1.4.0", "--rollout-percent", "10");
        Assert.True(flag["value"]!.GetValue<bool>());
        Assert.Equal(10, flag["rules"]!["rolloutPercent"]!.GetValue<int>());
        Assert.Equal(1, await fixture.AuditAsync("flag_update", operatorId));
        var cleared = await Json(env, "flags", "set", "smart_roi", "--value", "false", "--clear-rules");
        Assert.Null(cleared["rules"]!["rolloutPercent"]);

        // Price override (adminOverridePrice): the price stays a decimal string.
        var price = await Json(env, "prices", "override", "--symbol", "XAU21_G", "--currency", "EGP", "--price", "4217.50", "--reason", "Feed outage, dealer quote");
        Assert.Equal("4217.50", price["price"]!.GetValue<string>());
        Assert.Equal(1, await fixture.AuditAsync("price_override", operatorId));

        // Contributions (adminListContributions, adminPromoteContribution, adminRejectContribution).
        await SeedAggregateAsync("cli promoted shop");
        await SeedAggregateAsync("cli rejected shop");
        var queue = await Json(env, "contributions", "list");
        Assert.True(queue["items"]!.AsArray().Count >= 2);
        var promoted = await Json(env, "contributions", "promote", "--merchant-norm", "cli promoted shop", "--institution", "nbe");
        Assert.Equal("promoted", promoted["status"]!.GetValue<string>());
        var rejected = await Json(env, "contributions", "reject", "--merchant-norm", "cli rejected shop", "--institution", "nbe");
        Assert.Equal("rejected", rejected["status"]!.GetValue<string>());
        Assert.Equal(1, await fixture.AuditAsync("contribution_promote", operatorId));
        Assert.Equal(1, await fixture.AuditAsync("contribution_reject", operatorId));

        // Support lookup by install and by e-mail (adminLookupEntitlement), both audited.
        var (purchase, holder, claimant, email) = await fixture.SeedMovableAsync();
        var byInstall = await Json(env, "support", "lookup", "--install", holder.ToString());
        Assert.NotNull(byInstall["status"]);
        await Ok(env, "support", "lookup", "--email", email);
        Assert.Equal(2, await fixture.AuditAsync("support_lookup", operatorId));

        // Support writes with the no-echo prompt (adminMoveSeat, adminDetachPurchase).
        var ownershipBefore = fixture.Ownership.OrderIds.Count;
        env.Type(Order);
        var move = await Json(env, "support", "move", "--purchase", purchase.ToString(), "--to", claimant.ToString(), "--reason", "lost_or_broken_phone", "--ticket", "ZG-10422");
        Assert.True(move["moved"]!.GetValue<bool>());
        env.Type(Order);
        var correction = await Json(env, "support", "move", "--purchase", purchase.ToString(), "--to", holder.ToString(), "--reason", "correction", "--corrects", move["auditId"]!.GetValue<long>().ToString(CultureInfo.InvariantCulture), "--ticket", "ZG-10423");
        Assert.True(correction["moved"]!.GetValue<bool>());
        Assert.Equal(2, await fixture.AuditAsync("support_seat_move", operatorId));
        env.Type(Order);
        var detach = await Json(env, "support", "detach", "--purchase", purchase.ToString(), "--ticket", "ZG-10424", "--corrects", "1");
        Assert.False(detach["detached"]!.GetValue<bool>());
        Assert.Equal(1, await fixture.AuditAsync("support_detach", operatorId));

        // The agent role cannot unfreeze: 403 maps to exit code 3 and the prompt is still asked only after sign-in.
        env.Type(Order);
        Assert.Equal(3, await env.RunAsync("support", "unfreeze", "--purchase", purchase.ToString(), "--ticket", "ZG-10425"));
        Assert.Contains("403 FORBIDDEN", env.Error.ToString(), StringComparison.Ordinal);

        Assert.Equal(tokenRequests + 1, fixture.Idp.TokenRequests);

        // D-57 on the server side: the order ID reached the ownership check, and is in no audit row.
        var received = fixture.Ownership.OrderIds.Skip(ownershipBefore).ToList();
        Assert.True(received.Count == 3, "ownership checks seen: " + received.Count.ToString(CultureInfo.InvariantCulture));
        Assert.All(received, id => Assert.Equal(Order, id));
        Assert.Equal(0L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.audit_log WHERE details::text LIKE '%3312-5208%' OR target LIKE '%3312-5208%'"));
        Assert.DoesNotContain(Order, env.AllOutput, StringComparison.Ordinal);
        Assert.DoesNotContain("3312-5208", env.Output + env.Error.ToString() + env.PromptText, StringComparison.Ordinal);
    }

    [Fact]
    public async Task UnfreezeNeedsADifferentLeadAfter24HoursAndTheCliShowsTheServersRefusal()
    {
        var (_, agentSubject) = await fixture.NewOperatorAsync("support_agent");
        var (_, leadSubject) = await fixture.NewOperatorAsync("support_lead");
        var (purchase, holder, claimant, _) = await fixture.SeedMovableAsync();

        fixture.Idp.Subject = agentSubject;
        using var agent = NewEnvironment();
        agent.Type(Order);
        var move = await Json(agent, "support", "move", "--purchase", purchase.ToString(), "--to", claimant.ToString(), "--reason", "other", "--ticket", "ZG-20001");
        agent.Type(Order);
        await Ok(agent, "support", "move", "--purchase", purchase.ToString(), "--to", holder.ToString(), "--reason", "correction", "--corrects", move["auditId"]!.GetValue<long>().ToString(CultureInfo.InvariantCulture), "--ticket", "ZG-20002");

        // The freeze is running: an ordinary move is refused (409 ADMIN_CONFLICT, exit 1) and audited.
        agent.Type(Order);
        Assert.Equal(1, await agent.RunAsync("support", "move", "--purchase", purchase.ToString(), "--to", claimant.ToString(), "--reason", "other", "--ticket", "ZG-20003"));
        Assert.Contains("409 ADMIN_CONFLICT", agent.Error.ToString(), StringComparison.Ordinal);

        fixture.Idp.Subject = leadSubject;
        using var lead = NewEnvironment();
        lead.Type(Order);
        Assert.Equal(1, await lead.RunAsync("support", "unfreeze", "--purchase", purchase.ToString(), "--ticket", "ZG-20004"));
        Assert.Contains("409 ADMIN_CONFLICT", lead.Error.ToString(), StringComparison.Ordinal);

        await fixture.ExecuteAsync("UPDATE zaghlol.audit_log SET at = now() - interval '25 hours' WHERE target = @t", ("t", purchase.ToString()));
        lead.ClearOutput();
        lead.Type(Order);
        var unfrozen = await Json(lead, "support", "unfreeze", "--purchase", purchase.ToString(), "--ticket", "ZG-20005");
        Assert.True(unfrozen["unfrozen"]!.GetValue<bool>());
        Assert.True(await fixture.AuditAsync("support_unfreeze") >= 2);
        Assert.Equal(0L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.audit_log WHERE details::text LIKE '%3312-5208%'"));
    }

    [Fact]
    public async Task ARoleThatIsMissingIsExitCode3AndLeavesNoAuditRow()
    {
        var (_, subject) = await fixture.NewOperatorAsync("catalog_editor");
        fixture.Idp.Subject = subject;
        using var env = NewEnvironment();
        var before = await fixture.AuditAsync("flag_update");

        var code = await env.RunAsync("flags", "set", "smart_roi", "--value", "true");

        Assert.Equal(3, code);
        Assert.Contains("403 FORBIDDEN", env.Error.ToString(), StringComparison.Ordinal);
        Assert.Equal(before, await fixture.AuditAsync("flag_update"));
    }

    [Fact]
    public async Task ASignedInPersonWhoIsNotAnOperatorGetsExitCode3AndTheTokenIsForgotten()
    {
        fixture.Idp.Subject = "sub-not-an-operator-" + Guid.NewGuid().ToString("N");
        using var env = NewEnvironment();

        var code = await env.RunAsync("metrics", "daily-active");

        Assert.Equal(3, code);
        Assert.Contains("401", env.Error.ToString(), StringComparison.Ordinal);
        Assert.Contains("\"signedIn\": false", await StatusAsync(env), StringComparison.Ordinal);
    }

    [Fact]
    public async Task ImportStopsAtTheFirstFailureAndSaysHowManyWereApplied()
    {
        var (_, subject) = await fixture.NewOperatorAsync("catalog_editor");
        fixture.Idp.Subject = subject;
        using var env = NewEnvironment();
        env.Files["bad.json"] =
            "{\"entries\":[{\"entity\":\"categories\",\"key\":\"imp_ok_cat\",\"body\":{\"nameAr\":\"x\",\"nameEn\":\"Ok\",\"icon\":\"i\",\"color\":\"#112233\",\"bucket\":\"wants\",\"sort\":2}},"
            + "{\"entity\":\"merchants\",\"body\":{\"canonical\":\"Bad Cat Merchant\",\"nameAr\":\"y\",\"category\":\"no_such_category\"}},"
            + "{\"entity\":\"categories\",\"key\":\"imp_never\",\"body\":{\"nameAr\":\"x\",\"nameEn\":\"Never\",\"icon\":\"i\",\"color\":\"#112233\",\"bucket\":\"wants\",\"sort\":3}}]}";

        var code = await env.RunAsync("catalog", "import", "bad.json");

        Assert.Equal(1, code);
        Assert.Contains("stopped at entry 2; 1 applied before it", env.Error.ToString(), StringComparison.Ordinal);
        Assert.Equal(1L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'categories' AND entry_key = 'imp_ok_cat'"));
        Assert.Equal(0L, await fixture.ScalarAsync("SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'categories' AND entry_key = 'imp_never'"));
    }

    [Fact]
    public async Task AnImportFileWithAnUnknownMemberIsRefusedBeforeAnyCallIsMade()
    {
        var (_, subject) = await fixture.NewOperatorAsync("catalog_editor");
        fixture.Idp.Subject = subject;
        using var env = NewEnvironment();
        env.Files["bad.json"] = "{\"entries\":[{\"entity\":\"categories\",\"key\":\"x_cat\",\"body\":{},\"extra\":1}]}";

        var tokens = fixture.Idp.TokenRequests;

        Assert.Equal(2, await env.RunAsync("catalog", "import", "bad.json"));
        Assert.Equal(tokens, fixture.Idp.TokenRequests);
        Assert.Contains("Entry 1", env.Error.ToString(), StringComparison.Ordinal);
    }

    // The tests share one IdP (its keys are the API's trusted keys), so an environment must not dispose it.
    private TestEnvironment NewEnvironment() => new(fixture.ApiHandler, fixture.Idp, typedOrderId: null, interactive: true, ownsIdp: false);

    private static async Task Ok(TestEnvironment env, params string[] args)
    {
        env.ClearOutput();
        var code = await env.RunAsync(args);
        Assert.True(code == 0, $"{string.Join(' ', args.Take(3))} exited {code}: {env.Error}");
    }

    private static async Task<JsonObject> Json(TestEnvironment env, params string[] args)
    {
        env.ClearOutput();
        var code = await env.RunAsync(args);
        Assert.True(code == 0, $"{string.Join(' ', args.Take(3))} exited {code}: {env.Error}");
        return JsonNode.Parse(env.Output.ToString())!.AsObject();
    }

    private static async Task<string> StatusAsync(TestEnvironment env)
    {
        env.ClearOutput();
        await env.RunAsync("status");
        return env.Output.ToString();
    }

    private async Task SeedAggregateAsync(string norm) =>
        await fixture.ExecuteAsync(
            "INSERT INTO zaghlol.contribution_aggregates (merchant_norm, institution_code, distinct_installs, top_category_code, category_votes, status) VALUES (@n, 'nbe', 6, 'dining', '{\"dining\": 6}', 'ready_for_review')",
            ("n", norm));
}
