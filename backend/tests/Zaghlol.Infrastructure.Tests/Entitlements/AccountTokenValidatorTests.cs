using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Application.Entitlements;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Entitlements;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Tests.Seats;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Entitlements;

/// <summary>T-132: what a <c>Zaghlol-Account</c> header proves (signature, install binding, expiry, live link) and the signer adapter.</summary>
public sealed class AccountTokenValidatorTests(EntitlementFixture fixture) : IClassFixture<EntitlementFixture>, IDisposable
{
    private static readonly DateTimeOffset Now = DateTimeOffset.UtcNow;

    private static readonly string[] ClaimNames = ["acct", "exp", "graceUntil", "iat", "iss", "movedBy", "nextMoveAt", "plan", "src", "status", "sub", "v"];

    private readonly FakeKms kms = FakeKms.CreateDefault();

    private SeatDb Db => fixture.Db;

    public void Dispose() => kms.Dispose();

    private async Task<(ISigner Signer, AccountTokenValidator Validator, ServiceProvider Provider)> BuildAsync()
    {
        var provider = kms.BuildServices();
        var signer = provider.GetRequiredService<ISigner>();
        await Task.CompletedTask;
        return (signer, new AccountTokenValidator(signer, fixture.Services), provider);
    }

    private static Task<string> MintAsync(ISigner signer, Guid account, InstallId install, TimeSpan life) =>
        new KmsEntitlementSigner(signer).SignAccountTokenAsync(
            new AccountTokenClaims(account.ToString("D"), install.ToString(), Now.ToUnixTimeSeconds(), (Now + life).ToUnixTimeSeconds()),
            CancellationToken.None);

    private static Task<ValidatedAccountToken?> CheckAsync(AccountTokenValidator validator, string? token, InstallId install) =>
        validator.ValidateAsync(token is null ? null : new Sensitive<string>(token), install, Now, CancellationToken.None);

    [Fact]
    public async Task ASignedTokenForThisInstallAndAStillLinkedAccountIsValid()
    {
        var (signer, validator, provider) = await BuildAsync();
        await using var _ = provider;
        var install = await Db.InstallAsync();
        var account = await Db.AccountAsync(install);

        var result = await CheckAsync(validator, await MintAsync(signer, account, install, TimeSpan.FromDays(10)), install);

        Assert.Equal(account, result!.AccountId);
        Assert.Equal(Now.AddDays(10).ToUnixTimeSeconds(), result.ExpiresAt.ToUnixTimeSeconds());
    }

    [Fact]
    public async Task ATokenForAnotherInstallsIidIsRejected()
    {
        var (signer, validator, provider) = await BuildAsync();
        await using var _ = provider;
        var install = await Db.InstallAsync();
        var other = await Db.InstallAsync();
        var account = await Db.AccountAsync(install, other);
        var token = await MintAsync(signer, account, install, TimeSpan.FromDays(10));

        Assert.NotNull(await CheckAsync(validator, token, install));
        Assert.Null(await CheckAsync(validator, token, other));
    }

    [Fact]
    public async Task AnExpiredTokenIsRejected()
    {
        var (signer, validator, provider) = await BuildAsync();
        await using var _ = provider;
        var install = await Db.InstallAsync();
        var account = await Db.AccountAsync(install);

        Assert.Null(await CheckAsync(validator, await MintAsync(signer, account, install, TimeSpan.FromSeconds(-1)), install));
    }

    [Fact]
    public async Task R36ATokenWhoseAccountWasDeletedOrWhoseInstallIsNoLongerLinkedIsRejectedBeforeExp()
    {
        var (signer, validator, provider) = await BuildAsync();
        await using var _ = provider;
        var install = await Db.InstallAsync();
        var gone = await Db.AccountAsync(install);
        var unlinked = await Db.AccountAsync();
        var goneToken = await MintAsync(signer, gone, install, TimeSpan.FromDays(10));
        var unlinkedToken = await MintAsync(signer, unlinked, install, TimeSpan.FromDays(10));

        await Db.DeleteAccountAsync(gone);

        Assert.Null(await CheckAsync(validator, goneToken, install));
        Assert.Null(await CheckAsync(validator, unlinkedToken, install));
    }

    [Fact]
    public async Task ATamperedPayloadAForeignKeyAndGarbageAreRejected()
    {
        var (signer, validator, provider) = await BuildAsync();
        await using var _ = provider;
        var install = await Db.InstallAsync();
        var account = await Db.AccountAsync(install);
        var otherAccount = await Db.AccountAsync(install);
        var token = await MintAsync(signer, account, install, TimeSpan.FromDays(10));
        var parts = token.Split('.');
        var swapped = (await MintAsync(signer, otherAccount, install, TimeSpan.FromDays(10))).Split('.')[1];
        var tampered = parts[0] + "." + swapped + "." + parts[2];

        // A token of an attacker's own P-256 key under the real kid.
        using var attacker = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var header = Base64Url.EncodeToString(Encoding.UTF8.GetBytes("{\"alg\":\"ES256\",\"kid\":\"" + FakeKms.EntitlementKid + "\",\"typ\":\"JWT\"}"));
        var payload = Base64Url.EncodeToString(Encoding.UTF8.GetBytes(
            $"{{\"sub\":\"{account}\",\"iid\":\"{install}\",\"iat\":{Now.ToUnixTimeSeconds()},\"exp\":{Now.AddDays(5).ToUnixTimeSeconds()}}}"));
        var signature = attacker.SignData(Encoding.ASCII.GetBytes(header + "." + payload), HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
        var forged = header + "." + payload + "." + Base64Url.EncodeToString(signature);

        Assert.NotNull(await CheckAsync(validator, token, install));
        Assert.Null(await CheckAsync(validator, tampered, install));
        Assert.Null(await CheckAsync(validator, forged, install));
        Assert.Null(await CheckAsync(validator, "not-a-jwt", install));
        Assert.Null(await CheckAsync(validator, new string('a', AccountTokenValidator.MaxLength + 1), install));
        Assert.Null(await CheckAsync(validator, "a.b.c", install));
        Assert.Null(await CheckAsync(validator, null, install));
    }

    [Fact]
    public async Task AnEntitlementTokenOfTheSameKeyIsNotAnAccountToken()
    {
        var (signer, validator, provider) = await BuildAsync();
        await using var _ = provider;
        var install = await Db.InstallAsync();
        await Db.AccountAsync(install);

        var entitlement = await new KmsEntitlementSigner(signer).SignEntitlementAsync(
            new EntitlementClaims("zaghlol", install.ToString(), null, "none", "none", Now.ToUnixTimeSeconds() + 100, Now.ToUnixTimeSeconds() + 200, Now.ToUnixTimeSeconds(), null, null, [], 1),
            CancellationToken.None);

        Assert.Null(await CheckAsync(validator, entitlement, install));
    }

    [Fact]
    public async Task TheEntitlementJwsCarriesTheDocumentedClaimsAndVerifiesWithThePublishedKey()
    {
        var (signer, _, provider) = await BuildAsync();
        await using var _ = provider;
        var install = SeatDb.NewInstallId();
        var claims = EntitlementRules.Build(
            install,
            new EntitlementFacts([], []),
            null,
            Now);

        var jws = await new KmsEntitlementSigner(signer).SignEntitlementAsync(claims, CancellationToken.None);

        var parts = jws.Split('.');
        using var header = System.Text.Json.JsonDocument.Parse(Base64Url.DecodeFromChars(parts[0]));
        Assert.Equal("ES256", header.RootElement.GetProperty("alg").GetString());
        Assert.Equal(FakeKms.EntitlementKid, header.RootElement.GetProperty("kid").GetString());
        using var payload = System.Text.Json.JsonDocument.Parse(Base64Url.DecodeFromChars(parts[1]));
        var names = payload.RootElement.EnumerateObject().Select(p => p.Name).Order().ToArray();
        Assert.Equal(ClaimNames, names);
        Assert.Equal(install.ToString(), payload.RootElement.GetProperty("sub").GetString());
        var key = signer.PublishedKeys(SigningPurpose.Entitlement).Single(k => k.Kid == FakeKms.EntitlementKid);
        Assert.True(key.PublicJwk.VerifiesDigest(SHA256.HashData(Encoding.ASCII.GetBytes(parts[0] + "." + parts[1])), Base64Url.DecodeFromChars(parts[2])));
    }
}
