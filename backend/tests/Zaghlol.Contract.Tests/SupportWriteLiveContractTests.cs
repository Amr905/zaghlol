using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json.Nodes;
using Zaghlol.Application.Purchases;
using Zaghlol.Testing;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// FU-011 for the three support writes (T-186): every status the live API answers is declared by the operation and every body
/// validates against its schema, requests included. Also the role checks (<c>support_viewer</c> 403 on all three, <c>support_agent</c>
/// 403 on unfreeze, <c>support_lead</c> alone 403 on move and detach). The order lookups are a fake.
/// </summary>
public class SupportWriteLiveContractTests(SupportContractFixture fixture) : IClassFixture<SupportContractFixture>
{
    private const string Move = "/admin/v1/support/seat:move";
    private const string Detach = "/admin/v1/support/purchase:detach";
    private const string Unfreeze = "/admin/v1/support/purchase:unfreeze";
    private const string Json = "application/json";
    private const string Problem = "application/problem+json";
    private const string Order = "GPA.3312-5208-4571-04923";

    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private static SpecOperation Operation(string id) => Spec.Operations().Single(o => o.Id == id);

    [Fact]
    public async Task MoveCorrectionUnfreezeAndDetachAnswerTheirDeclaredSchemas()
    {
        var agent = await fixture.OperatorTokenAsync("support_agent");
        var lead = await fixture.OperatorTokenAsync("support_lead");
        var (purchase, holder, claimant) = await fixture.SeedMovableAsync();
        fixture.Ownership.Next = OwnershipOutcome.Pass;

        // seat:move to the claimant.
        var moveBody = MoveBody(purchase, claimant, "lost_or_broken_phone");
        using var moved = await SendAsync(Move, agent, moveBody);
        var movedBody = await AssertDeclared("adminMoveSeat", moved, HttpStatusCode.OK, Json, moveBody);
        Assert.True(movedBody!["moved"]!.GetValue<bool>());
        Assert.False(movedBody["attached"]!.GetValue<bool>());
        Assert.NotNull(movedBody["nextMoveAt"]);
        var auditId = movedBody["auditId"]!.GetValue<long>();

        // A correction (the move back) starts the dispute freeze.
        var correctionBody = MoveBody(purchase, holder, "correction", auditId);
        using var correction = await SendAsync(Move, agent, correctionBody);
        await AssertDeclared("adminMoveSeat", correction, HttpStatusCode.OK, Json, correctionBody);

        // An ordinary move during the freeze is 409 ADMIN_CONFLICT.
        using var frozen = await SendAsync(Move, agent, MoveBody(purchase, claimant, "other"));
        Assert.Equal("ADMIN_CONFLICT", (await AssertDeclared("adminMoveSeat", frozen, HttpStatusCode.Conflict, Problem))!["code"]!.GetValue<string>());

        // The correcting operator can't unfreeze; another lead can.
        var sameOperatorLead = await fixture.OperatorTokenAsync("support_lead");
        var unfreezeBody = UnfreezeBody(purchase);
        using var early = await SendAsync(Unfreeze, lead, unfreezeBody);
        Assert.Equal("ADMIN_CONFLICT", (await AssertDeclared("adminUnfreezePurchase", early, HttpStatusCode.Conflict, Problem))!["code"]!.GetValue<string>());
        await ZaghlolTestDatabase.ExecuteAsync(fixture.Database.Migrator, $"UPDATE zaghlol.audit_log SET at = now() - interval '25 hours' WHERE target = '{purchase}'");
        using var unfrozen = await SendAsync(Unfreeze, lead, unfreezeBody);
        var unfrozenBody = await AssertDeclared("adminUnfreezePurchase", unfrozen, HttpStatusCode.OK, Json, unfreezeBody);
        Assert.True(unfrozenBody!["unfrozen"]!.GetValue<bool>());
        using var again = await SendAsync(Unfreeze, sameOperatorLead, unfreezeBody);
        Assert.False((await AssertDeclared("adminUnfreezePurchase", again, HttpStatusCode.OK, Json, unfreezeBody))!["unfrozen"]!.GetValue<bool>());

        // purchase:detach on an unlinked purchase is an audited noop.
        var detachBody = DetachBody(purchase, 1);
        using var detached = await SendAsync(Detach, agent, detachBody);
        Assert.False((await AssertDeclared("adminDetachPurchase", detached, HttpStatusCode.OK, Json, detachBody))!["detached"]!.GetValue<bool>());
    }

    [Fact]
    public async Task EveryErrorStatusIsDeclaredAndConforms()
    {
        var agent = await fixture.OperatorTokenAsync("support_agent");
        var lead = await fixture.OperatorTokenAsync("support_lead");
        var (purchase, _, claimant) = await fixture.SeedMovableAsync();
        var (linked, _, _) = await fixture.SeedMovableAsync(signInLinked: true);
        var missing = Guid.NewGuid();

        using var unknown = await SendAsync(Move, agent, "{\"purchaseId\":\"" + purchase + "\",\"extra\":1}");
        using var invalid = await SendAsync(Move, agent, "{\"purchaseId\":\"nope\"}");
        using var correctionWithoutRow = await SendAsync(Move, agent, "{\"purchaseId\":\"" + purchase + "\",\"toInstallId\":\"" + claimant + "\",\"reasonCode\":\"correction\",\"ticketRef\":\"ZG-1\",\"ownershipCheck\":\"" + Order + "\"}");
        using var notFound = await SendAsync(Move, agent, MoveBody(missing, claimant, "other"));
        using var stranger = await SendAsync(Move, agent, MoveBody(purchase, Guid.NewGuid(), "other"));
        using var signInLink = await SendAsync(Detach, agent, DetachBody(linked, 1));
        using var anonymous = await SendAsync(Move, null, MoveBody(purchase, claimant, "other"));
        using var wrongType = await SendAsync(Move, agent, MoveBody(purchase, claimant, "other"), "text/plain");
        using var unfreezeUnknown = await SendAsync(Unfreeze, lead, "{\"purchaseId\":\"" + purchase + "\",\"extra\":1}");
        using var detachInvalid = await SendAsync(Detach, agent, "{\"purchaseId\":\"" + purchase + "\"}");

        Assert.Equal("UNKNOWN_FIELD", (await AssertDeclared("adminMoveSeat", unknown, HttpStatusCode.BadRequest, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("VALIDATION_FAILED", (await AssertDeclared("adminMoveSeat", invalid, HttpStatusCode.BadRequest, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("VALIDATION_FAILED", (await AssertDeclared("adminMoveSeat", correctionWithoutRow, HttpStatusCode.BadRequest, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("NOT_FOUND", (await AssertDeclared("adminMoveSeat", notFound, HttpStatusCode.NotFound, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("ADMIN_CONFLICT", (await AssertDeclared("adminMoveSeat", stranger, HttpStatusCode.Conflict, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("ADMIN_CONFLICT", (await AssertDeclared("adminDetachPurchase", signInLink, HttpStatusCode.Conflict, Problem))!["code"]!.GetValue<string>());
        Assert.Equal("UNAUTHORIZED", (await AssertDeclared("adminMoveSeat", anonymous, HttpStatusCode.Unauthorized, Problem))!["code"]!.GetValue<string>());
        await AssertDeclared("adminMoveSeat", wrongType, HttpStatusCode.UnsupportedMediaType, Problem);
        await AssertDeclared("adminUnfreezePurchase", unfreezeUnknown, HttpStatusCode.BadRequest, Problem);
        await AssertDeclared("adminDetachPurchase", detachInvalid, HttpStatusCode.BadRequest, Problem);
    }

    [Theory]
    [InlineData(OwnershipOutcome.Fail, HttpStatusCode.UnprocessableEntity, "OWNERSHIP_CHECK_FAILED")]
    [InlineData(OwnershipOutcome.Unavailable, HttpStatusCode.ServiceUnavailable, "UPSTREAM_UNAVAILABLE")]
    public async Task AFailedOwnershipCheckIs422Or503OnAllThreeOperations(OwnershipOutcome outcome, HttpStatusCode status, string code)
    {
        var agent = await fixture.OperatorTokenAsync("support_agent");
        var lead = await fixture.OperatorTokenAsync("support_lead");
        var (purchase, holder, claimant) = await fixture.SeedMovableAsync();
        var (frozen, _, _) = await fixture.SeedMovableAsync();
        await ZaghlolTestDatabase.ExecuteAsync(fixture.Database.Migrator, $"UPDATE zaghlol.purchases SET dispute_frozen_until = now() + interval '5 days' WHERE id = '{frozen}'");
        await SeedFreezeRowAsync(frozen, holder);
        fixture.Ownership.Next = outcome;
        try
        {
            using var move = await SendAsync(Move, agent, MoveBody(purchase, claimant, "other"));
            using var detach = await SendAsync(Detach, agent, DetachBody(purchase, 1));
            using var unfreeze = await SendAsync(Unfreeze, lead, UnfreezeBody(frozen));

            Assert.Equal(code, (await AssertDeclared("adminMoveSeat", move, status, Problem))!["code"]!.GetValue<string>());
            Assert.Equal(code, (await AssertDeclared("adminDetachPurchase", detach, status, Problem))!["code"]!.GetValue<string>());
            Assert.Equal(code, (await AssertDeclared("adminUnfreezePurchase", unfreeze, status, Problem))!["code"]!.GetValue<string>());
        }
        finally
        {
            fixture.Ownership.Next = OwnershipOutcome.Pass;
        }
    }

    [Fact]
    public async Task RoleChecks()
    {
        var viewer = await fixture.OperatorTokenAsync("support_viewer");
        var agent = await fixture.OperatorTokenAsync("support_agent");
        var lead = await fixture.OperatorTokenAsync("support_lead");
        var (purchase, _, claimant) = await fixture.SeedMovableAsync();
        var calls = fixture.Ownership.Calls;

        foreach (var (path, body) in new[] { (Move, MoveBody(purchase, claimant, "other")), (Detach, DetachBody(purchase, 1)), (Unfreeze, UnfreezeBody(purchase)) })
        {
            using var asViewer = await SendAsync(path, viewer, body);
            Assert.Equal(HttpStatusCode.Forbidden, asViewer.StatusCode);
        }

        using var agentUnfreeze = await SendAsync(Unfreeze, agent, UnfreezeBody(purchase));
        using var leadMove = await SendAsync(Move, lead, MoveBody(purchase, claimant, "other"));
        using var leadDetach = await SendAsync(Detach, lead, DetachBody(purchase, 1));

        Assert.Equal(HttpStatusCode.Forbidden, agentUnfreeze.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, leadMove.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, leadDetach.StatusCode);
        Assert.Equal(calls, fixture.Ownership.Calls);
        await AssertDeclared("adminMoveSeat", leadMove, HttpStatusCode.Forbidden, Problem);
    }

    private async Task SeedFreezeRowAsync(Guid purchase, Guid holder)
    {
        // A correction row naming a different operator, so that the lead may unfreeze.
        var other = Guid.NewGuid();
        await ZaghlolTestDatabase.ExecuteAsync(
            fixture.Database.Migrator,
            string.Create(
                CultureInfo.InvariantCulture,
                $$"""
                INSERT INTO zaghlol.operators (id, oidc_subject, display_name, roles) VALUES ('{{other}}', 'sub-{{other}}', 'Freezer', ARRAY['support_agent']);
                INSERT INTO zaghlol.audit_log (operator_id, action, target, details, at)
                VALUES ('{{other}}', 'support_seat_move', '{{purchase}}',
                        '{"to_install":"{{holder}}","reason_code":"correction","ticket_ref":"ZG-9","corrects_audit_id":1,"ownership_check":"order_id","ownership_outcome":"pass","outcome":"moved"}', now() - interval '25 hours');
                """));
    }

    private static string MoveBody(Guid purchase, Guid to, string reason, long? corrects = null) =>
        "{\"purchaseId\":\"" + purchase + "\",\"toInstallId\":\"" + to + "\",\"reasonCode\":\"" + reason + "\",\"ticketRef\":\"ZG-10422\",\"ownershipCheck\":\"" + Order + "\""
        + (corrects is { } id ? ",\"correctsAuditId\":" + id.ToString(CultureInfo.InvariantCulture) : string.Empty) + "}";

    private static string DetachBody(Guid purchase, long corrects) =>
        "{\"purchaseId\":\"" + purchase + "\",\"reasonCode\":\"correction\",\"ticketRef\":\"ZG-10431\",\"ownershipCheck\":\"" + Order + "\",\"correctsAuditId\":" + corrects.ToString(CultureInfo.InvariantCulture) + "}";

    private static string UnfreezeBody(Guid purchase) =>
        "{\"purchaseId\":\"" + purchase + "\",\"ticketRef\":\"ZG-10457\",\"ownershipCheck\":\"" + Order + "\"}";

    private static async Task<JsonNode?> AssertDeclared(string operationId, HttpResponseMessage response, HttpStatusCode status, string mediaType, string? requestBody = null)
    {
        var operation = Operation(operationId);
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(status == response.StatusCode, $"expected {(int)status}, got {(int)response.StatusCode}: {text}");
        var code = ((int)status).ToString(CultureInfo.InvariantCulture);

        Assert.True(operation.Body["responses"]!.AsObject().ContainsKey(code), $"{operation.Label} does not declare {code}");
        if (requestBody is not null)
        {
            Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(operation)!, JsonNode.Parse(requestBody)));
        }

        Assert.Equal(mediaType, response.Content.Headers.ContentType?.MediaType);
        var schema = Spec.ResponseSchema(operation, code, mediaType);
        Assert.NotNull(schema);
        var body = JsonNode.Parse(text);
        Assert.Null(Spec.Validate(schema, body));
        Assert.DoesNotContain(Order, text, StringComparison.Ordinal);
        return body;
    }

    private async Task<HttpResponseMessage> SendAsync(string path, string? token, string body, string mediaType = Json)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, path);
        if (token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        }

        request.Content = new StringContent(body, Encoding.UTF8);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue(mediaType);
        return await fixture.Client.SendAsync(request);
    }
}
