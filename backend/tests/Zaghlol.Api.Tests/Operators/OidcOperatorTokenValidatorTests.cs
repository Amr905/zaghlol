using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Zaghlol.Api.Auth;
using OperatorRoles = Zaghlol.Application.Operators.OperatorRoles;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Operators;

/// <summary>
/// T-136 AC1 and design note §2–§3, at the validator: every token defect is refused (<c>null</c>, so one 401 body), roles
/// come only from the <c>operators</c> row, the JWKS cache follows its timing rules, and the 30 s row cache bounds revocation.
/// </summary>
[Collection(ApiHostGroup.Name)]
public sealed class OidcOperatorTokenValidatorTests : IDisposable
{
    private const string Subject = "00u-operator-subject-1";

    private readonly ValidatorKit kit = new();
    private readonly Guid operatorId;

    public OidcOperatorTokenValidatorTests()
    {
        operatorId = kit.Directory.Add(Subject, OperatorRoles.FlagsAdmin, OperatorRoles.SupportViewer);
    }

    public void Dispose() => kit.Dispose();

    [Theory]
    [InlineData("RS256")]
    [InlineData("ES256")]
    public async Task AValidMfaTokenAuthenticatesWithTheRowsRoles(string algorithm)
    {
        var identity = await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject, Algorithm = algorithm }));

        Assert.NotNull(identity);
        Assert.Equal(operatorId, identity.OperatorId);
        Assert.Equal(new[] { OperatorRoles.FlagsAdmin, OperatorRoles.SupportViewer }, identity.Roles.Order(StringComparer.Ordinal));
    }

    [Fact]
    public async Task TheAdminAppAudienceIsAcceptedToo()
    {
        Assert.NotNull(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject, Audience = FakeOidcIssuer.AdminAudience })));
    }

    public static TheoryData<string> Defects => new()
    {
        "no_amr", "amr_without_mfa", "wrong_issuer", "wrong_audience", "no_audience", "alg_none", "hs256_with_public_key",
        "unknown_kid", "no_kid", "rs256_header_with_ec_kid", "forged_signature", "tampered_payload", "expired",
        "lifetime_over_one_hour", "issued_in_the_future", "not_yet_valid", "no_iat", "no_nbf", "no_exp", "string_exp",
        "foreign_key_with_jku", "unknown_subject", "jwe_shape", "garbage",
    };

    [Theory]
    [MemberData(nameof(Defects))]
    public async Task EveryDefectIsRefused(string defect)
    {
        var now = kit.Clock.Now;
        using var foreign = RSA.Create(2048);
        var spec = new OperatorTokenSpec { Subject = Subject };
        string token = defect switch
        {
            "no_amr" => kit.Mint(spec with { Amr = null }),
            "amr_without_mfa" => kit.Mint(spec with { Amr = ["pwd"] }),
            "wrong_issuer" => kit.Mint(spec with { Issuer = "https://login.zaghlol.test/other/v2.0" }),
            "wrong_audience" => kit.Mint(spec with { Audience = "some-other-app" }),
            "no_audience" => kit.Mint(spec with { Audience = null }),
            "alg_none" => kit.Mint(spec with { Algorithm = "none" }),
            "hs256_with_public_key" => kit.Mint(spec with { Algorithm = "HS256" }),
            "unknown_kid" => kit.Mint(spec with { Kid = "rsa-404" }),
            "no_kid" => kit.Mint(spec with { Kid = string.Empty }),
            "rs256_header_with_ec_kid" => kit.Mint(spec with { Kid = kit.Issuer.EcKid }),
            "forged_signature" => kit.Mint(spec with { ForeignKey = foreign }),
            "tampered_payload" => Tamper(kit.Mint(spec)),
            "expired" => kit.Mint(spec with { IssuedAt = now.AddSeconds(-3700), LifetimeSeconds = 3600 }),
            "lifetime_over_one_hour" => kit.Mint(spec with { LifetimeSeconds = 3601 }),
            "issued_in_the_future" => kit.Mint(spec with { IssuedAt = now.AddSeconds(120) }),
            "not_yet_valid" => kit.Mint(spec with { NotBefore = now.AddSeconds(120) }),
            "no_iat" => kit.Mint(spec with { OmitIssuedAt = true }),
            "no_nbf" => kit.Mint(spec with { OmitNotBefore = true }),
            "no_exp" => kit.Mint(spec with { OmitExpiry = true }),
            "string_exp" => kit.Mint(spec with { OmitExpiry = true, Extra = new Dictionary<string, JsonNode?> { ["exp"] = (now.ToUnixTimeSeconds() + 600).ToString(System.Globalization.CultureInfo.InvariantCulture) } }),
            "foreign_key_with_jku" => kit.Mint(spec with
            {
                ForeignKey = foreign,
                Kid = "attacker-1",
                ExtraHeader = new Dictionary<string, JsonNode?> { ["jku"] = "https://attacker.example/jwks", ["x5u"] = "https://attacker.example/cert" },
            }),
            "unknown_subject" => kit.Mint(spec with { Subject = "nobody" }),
            "jwe_shape" => kit.Mint(spec) + ".AAAA.BBBB",
            _ => "not-a-token",
        };

        Assert.Null(await kit.ValidateAsync(token));
    }

    [Theory]
    [InlineData(-59, true)]
    [InlineData(-60, false)]
    public async Task ExpiryHasSixtySecondsOfSkew(int expiredSecondsAgo, bool accepted)
    {
        var token = kit.Mint(new OperatorTokenSpec
        {
            Subject = Subject,
            IssuedAt = kit.Clock.Now.AddSeconds(expiredSecondsAgo - 3600),
            LifetimeSeconds = 3600,
        });

        Assert.Equal(accepted, await kit.ValidateAsync(token) is not null);
    }

    [Fact]
    public async Task ADisabledOperatorIsRefused()
    {
        kit.Directory.Add("disabled-subject", OperatorRoles.FlagsAdmin);
        kit.Directory.Disable("disabled-subject");

        Assert.Null(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = "disabled-subject" })));
    }

    [Fact]
    public async Task TokenRoleAndGroupClaimsNeverGrantARole()
    {
        kit.Directory.Add("plain-subject");
        var token = kit.Mint(new OperatorTokenSpec
        {
            Subject = "plain-subject",
            Extra = new Dictionary<string, JsonNode?>
            {
                ["roles"] = new JsonArray("flags_admin", "support_lead"),
                ["groups"] = new JsonArray("catalog_editor"),
            },
        });

        var identity = await kit.ValidateAsync(token);

        Assert.NotNull(identity);
        Assert.Empty(identity.Roles);
    }

    [Fact]
    public async Task UnknownRolesInTheRowAreDroppedAndCounted()
    {
        using var counters = new CounterRecorder();
        kit.Directory.Add("odd-subject", "superuser", OperatorRoles.CatalogEditor, "support");

        var identity = await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = "odd-subject" }));

        Assert.Equal(new[] { OperatorRoles.CatalogEditor }, identity!.Roles);
        Assert.Equal(2, counters.Total("zaghlol.diag.operator_unknown_role"));
    }

    [Fact]
    public async Task AdvisoryModeKeepsTheSupportRolesAndCountsTheUnprovenRequest()
    {
        using var counters = new CounterRecorder();
        kit.Directory.Add("agent-subject", OperatorRoles.SupportAgent, OperatorRoles.SupportLead);

        var identity = await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = "agent-subject" }));
        var proven = await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = "agent-subject", Acrs = [ValidatorKit.ContextId] }));

        Assert.Equal(new[] { OperatorRoles.SupportAgent, OperatorRoles.SupportLead }, identity!.Roles.Order(StringComparer.Ordinal));
        Assert.Equal(2, proven!.Roles.Count);
        Assert.Equal(1, counters.Total("zaghlol.diag.operator_phishing_resistant_unproven", OperatorRoles.SupportAgent));
        Assert.Equal(1, counters.Total("zaghlol.diag.operator_phishing_resistant_unproven", OperatorRoles.SupportLead));
    }

    [Fact]
    public async Task EnforcedModeDropsTheSupportRolesWithoutTheAuthenticationContext()
    {
        using var enforced = new ValidatorKit(o => o.PhishingResistantMode = PhishingResistantMode.Enforced);
        enforced.Directory.Add("agent-subject", OperatorRoles.SupportViewer, OperatorRoles.SupportAgent, OperatorRoles.SupportLead);

        var without = await enforced.ValidateAsync(enforced.Mint(new OperatorTokenSpec { Subject = "agent-subject", Acrs = ["c9"] }));
        var with = await enforced.ValidateAsync(enforced.Mint(new OperatorTokenSpec { Subject = "agent-subject", Acrs = ["c2", ValidatorKit.ContextId] }));

        Assert.Equal(new[] { OperatorRoles.SupportViewer }, without!.Roles);
        Assert.Equal(3, with!.Roles.Count);
    }

    [Fact]
    public async Task AcceptedAmrValuesAreConfigurable()
    {
        using var hardware = new ValidatorKit(o => o.AcceptedAmr.Add("hwk"));
        hardware.Directory.Add(Subject, OperatorRoles.FlagsAdmin);

        Assert.NotNull(await hardware.ValidateAsync(hardware.Mint(new OperatorTokenSpec { Subject = Subject, Amr = ["hwk"] })));
        Assert.Null(await hardware.ValidateAsync(hardware.Mint(new OperatorTokenSpec { Subject = Subject, Amr = ["mfa"] })));
    }

    [Fact]
    public async Task AnAlgorithmOutsideTheConfiguredSubsetIsRefused()
    {
        using var ecOnly = new ValidatorKit(o => o.Algorithms.Add("ES256"));
        ecOnly.Directory.Add(Subject, OperatorRoles.FlagsAdmin);

        Assert.NotNull(await ecOnly.ValidateAsync(ecOnly.Mint(new OperatorTokenSpec { Subject = Subject, Algorithm = "ES256" })));
        Assert.Null(await ecOnly.ValidateAsync(ecOnly.Mint(new OperatorTokenSpec { Subject = Subject, Algorithm = "RS256" })));
    }

    [Fact]
    public async Task ADiscoveredIssuerThatDiffersFromTheConfiguredOneLoadsNoKeys()
    {
        kit.Issuer.AnnouncedIssuer = "https://login.zaghlol.test/attacker/v2.0";

        Assert.Null(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject })));
        Assert.Equal(0, kit.Issuer.JwksRequests);
        Assert.Null(kit.Keys.FetchedAt);
    }

    [Fact]
    public async Task AfterRotationTheNewKidIsFetchedAtMostOncePerFiveMinutes()
    {
        Assert.NotNull(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject })));
        Assert.Equal(1, kit.Issuer.JwksRequests);

        kit.Issuer.Rotate();
        kit.Clock.Advance(TimeSpan.FromMinutes(1));

        // Inside the throttle window an unknown kid triggers no fetch.
        Assert.Null(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject })));
        Assert.Equal(1, kit.Issuer.JwksRequests);

        kit.Clock.Advance(TimeSpan.FromMinutes(4));
        Assert.NotNull(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject })));
        Assert.Equal(2, kit.Issuer.JwksRequests);

        // A flood of made-up kids right after costs no further fetch.
        for (var i = 0; i < 20; i++)
        {
            Assert.Null(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject, Kid = "flood-" + i })));
        }

        Assert.Equal(2, kit.Issuer.JwksRequests);
    }

    [Fact]
    public async Task KeysRefreshDailyAndTheLastGoodKeysServeUpToSevenDaysOfIdpOutage()
    {
        Assert.NotNull(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject })));
        kit.Clock.Advance(TimeSpan.FromHours(24));
        Assert.NotNull(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject })));
        Assert.Equal(2, kit.Issuer.JwksRequests);

        kit.Issuer.Failing = true;
        kit.Clock.Advance(TimeSpan.FromDays(6));
        Assert.NotNull(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject })));

        kit.Clock.Advance(TimeSpan.FromDays(1) + TimeSpan.FromMinutes(1));
        Assert.Null(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject })));

        kit.Issuer.Failing = false;
        kit.Clock.Advance(OidcKeyCache.RefreshThrottle);
        Assert.NotNull(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject })));
    }

    [Fact]
    public async Task ADisabledOperatorLosesAccessWithinThirtySeconds()
    {
        kit.Directory.Add("leaver", OperatorRoles.FlagsAdmin);
        Assert.NotNull(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = "leaver" })));
        var reads = kit.Directory.Reads;

        kit.Directory.Disable("leaver");
        kit.Clock.Advance(TimeSpan.FromSeconds(29));
        Assert.NotNull(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = "leaver" })));
        Assert.Equal(reads, kit.Directory.Reads);

        kit.Clock.Advance(TimeSpan.FromSeconds(2));
        Assert.Null(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = "leaver" })));
    }

    [Fact]
    public async Task AnUnknownSubjectIsCachedAsAMissToo()
    {
        var token = kit.Mint(new OperatorTokenSpec { Subject = "ghost" });
        Assert.Null(await kit.ValidateAsync(token));
        var reads = kit.Directory.Reads;

        Assert.Null(await kit.ValidateAsync(token));
        Assert.Equal(reads, kit.Directory.Reads);
    }

    private static string Tamper(string token)
    {
        var parts = token.Split('.');
        var payload = JsonNode.Parse(System.Buffers.Text.Base64Url.DecodeFromChars(parts[1]))!.AsObject();
        payload["sub"] = "someone-else";
        parts[1] = System.Buffers.Text.Base64Url.EncodeToString(System.Text.Encoding.UTF8.GetBytes(payload.ToJsonString()));
        return string.Join('.', parts);
    }
}
