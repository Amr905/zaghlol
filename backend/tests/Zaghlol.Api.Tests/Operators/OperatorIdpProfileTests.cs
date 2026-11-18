using Zaghlol.Api.Auth;
using Zaghlol.Testing;
using OperatorRoles = Zaghlol.Application.Operators.OperatorRoles;

namespace Zaghlol.Api.Tests.Operators;

/// <summary>
/// T-136 IdP profiles (Entra tenant, Google hosted domain, role mapping), at the validator. Negative proofs: wrong tenant or
/// domain, wrong audience, expired or forged token; plus the Google no-<c>amr</c>/<c>nbf</c> rule and the role-map narrowing.
/// </summary>
[Collection(ApiHostGroup.Name)]
public sealed class OperatorIdpProfileTests
{
    private const string Subject = "operator-1";
    private const string GoogleIssuer = "https://accounts.google.com";
    private const string Domain = "zaghlol.example";
    private const string AppRole = "Zaghlol.Flags";
    private const string OtherTenant = "99999999-9999-9999-9999-999999999999";

    private static ValidatorKit Google(Action<OperatorAuthOptions>? more = null)
    {
        var kit = new ValidatorKit(
            o =>
            {
                o.Profile = OperatorAuthProfile.Google;
                o.Issuer = GoogleIssuer;
                o.PhishingResistantMode = PhishingResistantMode.Advisory;
                o.RequiredAcrs = null;
                o.AllowedTenants.Clear();
                o.AllowedDomains.Add(Domain);
                more?.Invoke(o);
            },
            new FakeOidcIssuer(GoogleIssuer, "https://www.googleapis.com/oauth2/v3/certs"));
        kit.Directory.Add(Subject, OperatorRoles.FlagsAdmin, OperatorRoles.SupportViewer);
        return kit;
    }

    private static ValidatorKit Entra(Action<OperatorAuthOptions>? more = null)
    {
        var kit = new ValidatorKit(more);
        kit.Directory.Add(Subject, OperatorRoles.FlagsAdmin, OperatorRoles.SupportViewer);
        return kit;
    }

    [Fact]
    public async Task EntraAcceptsTheAllowedTenant()
    {
        using var kit = Entra();
        Assert.NotNull(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject })));
    }

    [Theory]
    [InlineData(OtherTenant)]
    [InlineData("")]
    public async Task EntraRefusesAWrongOrMissingTenant(string tenant)
    {
        using var kit = Entra();
        Assert.Null(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject, Tenant = tenant })));
    }

    [Fact]
    public async Task GoogleAcceptsTheHostedDomainWithoutAmrOrNbf()
    {
        using var kit = Google();
        var token = kit.Mint(new OperatorTokenSpec { Subject = Subject, HostedDomain = Domain, Amr = null, OmitNotBefore = true });
        var identity = await kit.ValidateAsync(token);
        Assert.NotNull(identity);
        Assert.Equal(2, identity.Roles.Count);
    }

    [Fact]
    public async Task GoogleAcceptsTheSchemelessIssuerAlias()
    {
        using var kit = Google();
        var token = kit.Mint(new OperatorTokenSpec { Subject = Subject, HostedDomain = Domain, Amr = null, Issuer = "accounts.google.com" });
        Assert.NotNull(await kit.ValidateAsync(token));
    }

    [Theory]
    [InlineData("other.example")]
    [InlineData(null)]
    public async Task GoogleRefusesAWrongOrMissingHostedDomain(string? domain)
    {
        using var kit = Google();
        Assert.Null(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject, HostedDomain = domain, Amr = null })));
    }

    [Fact]
    public async Task GoogleStillRefusesWrongAudienceExpiredAndForgedTokens()
    {
        using var kit = Google();
        var spec = new OperatorTokenSpec { Subject = Subject, HostedDomain = Domain, Amr = null };
        Assert.Null(await kit.ValidateAsync(kit.Mint(spec with { Audience = "someone-elses-client" })));
        Assert.Null(await kit.ValidateAsync(kit.Mint(spec with { IssuedAt = kit.Clock.Now.AddHours(-3) })));
        using var foreign = System.Security.Cryptography.RSA.Create(2048);
        Assert.Null(await kit.ValidateAsync(kit.Mint(spec with { ForeignKey = foreign })));
    }

    [Fact]
    public async Task EntraRefusesWrongAudienceExpiredAndForgedTokens()
    {
        using var kit = Entra();
        var spec = new OperatorTokenSpec { Subject = Subject };
        Assert.Null(await kit.ValidateAsync(kit.Mint(spec with { Audience = "someone-elses-client" })));
        Assert.Null(await kit.ValidateAsync(kit.Mint(spec with { IssuedAt = kit.Clock.Now.AddHours(-3) })));
        using var foreign = System.Security.Cryptography.RSA.Create(2048);
        Assert.Null(await kit.ValidateAsync(kit.Mint(spec with { ForeignKey = foreign })));
    }

    [Fact]
    public async Task AnEntraTokenStillNeedsTheMfaSignal()
    {
        using var kit = Entra();
        Assert.Null(await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject, Amr = null })));
    }

    [Fact]
    public async Task TheRoleMapOnlyNarrowsTheRowsRoles()
    {
        using var kit = Entra(o => o.RoleMap[AppRole] = OperatorRoles.FlagsAdmin);

        var narrowed = await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject, Roles = [AppRole] }));
        Assert.Equal([OperatorRoles.FlagsAdmin], narrowed!.Roles);

        var none = await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject, Roles = ["Unmapped"] }));
        Assert.Empty(none!.Roles);

        // A mapped role the row does not hold is never granted.
        kit.Directory.Add("viewer-only", OperatorRoles.SupportViewer);
        var escalation = await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = "viewer-only", Roles = [AppRole] }));
        Assert.Empty(escalation!.Roles);
    }

    [Fact]
    public async Task TheRoleMapCanReadTheGroupsClaim()
    {
        const string group = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
        using var kit = Entra(o =>
        {
            o.RoleClaim = "groups";
            o.RoleMap[group] = OperatorRoles.SupportViewer;
        });

        var identity = await kit.ValidateAsync(kit.Mint(new OperatorTokenSpec { Subject = Subject, Roles = [group], RolesClaim = "groups" }));
        Assert.Equal([OperatorRoles.SupportViewer], identity!.Roles);
    }
}
