using System.Text.Json;
using Zaghlol.Application.Audit;
using Zaghlol.Application.Support;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Support;

/// <summary>T-136: the support lookup's view rules, the e-mail key and the closed audit entries.</summary>
public class SupportLookupTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 10, 12, 0, 0, TimeSpan.Zero);
    private static readonly string[] InstallSeats = ["holder", "claimant", "none"];
    private static readonly string[] EmailSeats = ["held", "vacant"];
    private static readonly bool?[] BuyingFlags = [true, false, false];

    private static SupportPurchaseRow Row(
        string state = "active",
        bool held = true,
        bool holder = false,
        bool claimant = false,
        bool buyer = false,
        long claimants = 0,
        long rebinds = 0,
        DateTimeOffset? frozen = null,
        bool linked = false) =>
        new(
            Guid.NewGuid(),
            "yearly",
            state,
            "app_store",
            Now.AddDays(20),
            linked,
            linked ? "support" : null,
            frozen,
            held,
            holder,
            claimant,
            buyer,
            null,
            null,
            claimants,
            false,
            rebinds);

    [Theory]
    [InlineData("active", "active")]
    [InlineData("canceled_active", "active")]
    [InlineData("in_grace", "grace")]
    [InlineData("on_hold", "paused")]
    [InlineData("paused", "paused")]
    [InlineData("expired", "expired")]
    [InlineData("refunded", "refunded")]
    [InlineData("revoked", "refunded")]
    [InlineData("pending", "none")]
    public void TheHeldSeatsStateDecidesTheStatus(string state, string status)
    {
        var view = SupportEntitlementBuilder.Build(SupportLookupKind.Install, [Row(state, holder: true)], Now);

        Assert.Equal(status, view.Status);
        Assert.Equal(status == "grace" ? Now.AddDays(20) : (DateTimeOffset?)null, view.GraceUntil);
    }

    [Fact]
    public void ActiveBeatsGraceBeatsPaused()
    {
        var view = SupportEntitlementBuilder.Build(
            SupportLookupKind.Install,
            [Row("paused", holder: true), Row("in_grace", holder: true), Row("active", holder: true)],
            Now);

        Assert.Equal("active", view.Status);
        Assert.Equal("yearly", view.Plan);
    }

    [Fact]
    public void ABuyerOrClaimantWhoseSeatIsElsewhereSeesMoved()
    {
        Assert.Equal("moved", SupportEntitlementBuilder.Build(SupportLookupKind.Install, [Row(buyer: true)], Now).Status);
        Assert.Equal("moved", SupportEntitlementBuilder.Build(SupportLookupKind.Install, [Row(claimant: true)], Now).Status);
        Assert.Equal("none", SupportEntitlementBuilder.Build(SupportLookupKind.Install, [Row(buyer: true, held: false)], Now).Status);
    }

    [Fact]
    public void AnInstallLookupNamesTheRelationAndAnEmailLookupOnlyHeldOrVacant()
    {
        var install = SupportEntitlementBuilder.Build(
            SupportLookupKind.Install,
            [Row(holder: true, buyer: true), Row(claimant: true), Row()],
            Now);
        var email = SupportEntitlementBuilder.Build(SupportLookupKind.Email, [Row(held: true), Row(held: false)], Now);

        Assert.Equal(InstallSeats, install.Purchases.Select(p => p.Seat));
        Assert.Equal(BuyingFlags, install.Purchases.Select(p => p.IsBuyingInstall));
        Assert.Equal(EmailSeats, email.Purchases.Select(p => p.Seat));
        Assert.All(email.Purchases, p => Assert.Null(p.IsBuyingInstall));
        Assert.Equal("active", email.Status);
    }

    [Fact]
    public void CountersAreClampedAndAnEndedFreezeIsNull()
    {
        var view = SupportEntitlementBuilder.Build(
            SupportLookupKind.Install,
            [Row(holder: true, claimants: 9, rebinds: 5, frozen: Now.AddDays(3)), Row(claimants: -1, rebinds: -1, frozen: Now.AddSeconds(-1))],
            Now);

        Assert.Equal(3, view.Purchases[0].PendingClaimants);
        Assert.Equal(2, view.Purchases[0].RebindsLast30Days);
        Assert.Equal(Now.AddDays(3), view.Purchases[0].DisputeFrozenUntil);
        Assert.Equal(0, view.Purchases[1].PendingClaimants);
        Assert.Equal(0, view.Purchases[1].RebindsLast30Days);
        Assert.Null(view.Purchases[1].DisputeFrozenUntil);
    }

    [Fact]
    public void AtMostTwentyPurchasesAreListedAndLinkedByOnlyWhenLinked()
    {
        var rows = Enumerable.Range(0, 25).Select(i => Row(linked: i % 2 == 0)).ToList();

        var view = SupportEntitlementBuilder.Build(SupportLookupKind.Email, rows, Now);

        Assert.Equal(SupportEntitlementBuilder.MaxPurchases, view.Purchases.Count);
        Assert.All(view.Purchases, p => Assert.Equal(p.AccountLinked, p.LinkedBy is not null));
    }

    [Theory]
    [InlineData("Someone@Example.COM", "someone@example.com")]
    [InlineData("  someone@example.com\t", "someone@example.com")]
    [InlineData("ANA.SALMA+GOLD@EXAMPLE.EG", "ana.salma+gold@example.eg")]
    public void EmailsAreLoweredTrimmedAndNfcNormalised(string raw, string expected)
    {
        Assert.True(SupportEmail.TryNormalize(raw, out var normalized));
        Assert.Equal(expected, normalized);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("no-at-sign")]
    [InlineData("@example.com")]
    [InlineData("someone@")]
    [InlineData("a@b@example.com")]
    [InlineData("some one@example.com")]
    [InlineData("someone@exa\u0000mple.com")]
    public void ImplausibleEmailsAreRefused(string? raw)
    {
        Assert.False(SupportEmail.TryNormalize(raw, out _));
    }

    [Fact]
    public void AnEmailOverTheSpecLengthIsRefused()
    {
        Assert.False(SupportEmail.TryNormalize(new string('a', 250) + "@b.eg", out _));
    }

    [Fact]
    public void ASupportLookupAuditNeverHoldsTheEmail()
    {
        var mac = new byte[32];
        mac[0] = 0xAB;
        var account = Guid.NewGuid();
        var other = Guid.NewGuid();

        var byEmail = SupportLookupAudit.ForEmail(EmailPseudonym.FromMac(mac), [account, other], 2);
        var byInstall = SupportLookupAudit.ForInstall(InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77"), 0);

        Assert.Equal("support_lookup", byEmail.Action);
        Assert.Matches("^email:ab0{62}$", byEmail.Target);
        using var details = JsonDocument.Parse(byEmail.Details());
        Assert.Equal(account.ToString(), details.RootElement.GetProperty("account_id").GetString());
        Assert.Equal(2, details.RootElement.GetProperty("account_ids").GetArrayLength());
        Assert.Equal("email", details.RootElement.GetProperty("key").GetString());
        Assert.Equal("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77", byInstall.Target);
        Assert.DoesNotContain("account_id", byInstall.Details(), StringComparison.Ordinal);
        Assert.Throws<ArgumentException>(() => EmailPseudonym.FromMac(new byte[16]));
    }

    [Fact]
    public void ExistingAuditShapesAreUnchanged()
    {
        Assert.Equal("{\"value\":true,\"version\":3,\"rules\":{\"rolloutPercent\":5}}", new FlagUpdateAudit("zakah", true, 3, "{\"rolloutPercent\":5}").Details());
        Assert.Equal("flag:zakah", new FlagUpdateAudit("zakah", true, 3, "{}").Target);
        Assert.Equal("catalog_draft_delete", new CatalogDraftAudit(CatalogDraftAction.Delete, "aliases", "812:a2V5").Action);
        Assert.Equal("aliases/812:a2V5", new CatalogDraftAudit(CatalogDraftAction.Delete, "aliases", "812:a2V5").Target);
        Assert.Equal("{\"entity\":\"aliases\"}", new CatalogDraftAudit(CatalogDraftAction.Put, "aliases", "812:a2V5").Details());
        Assert.Equal("catalog/7", new CatalogPublishAudit(7, 12).Target);
        Assert.Equal("{\"version\":7,\"ops\":12}", new CatalogPublishAudit(7, 12).Details());
        Assert.Equal("{\"categories\":1,\"merchants\":2,\"aliases\":3,\"keywords\":4}", new CatalogSeedImportAudit(1, 2, 3, 4).Details());
    }
}
