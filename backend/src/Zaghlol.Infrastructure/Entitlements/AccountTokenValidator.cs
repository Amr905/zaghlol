using System.Buffers.Text;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using NpgsqlTypes;
using Zaghlol.Application.Entitlements;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Infrastructure.Entitlements;

/// <summary>
/// <see cref="IAccountTokenValidator"/> over the entitlement key ring (backend-api §3). Signature first, with the published
/// ES256 key of the header's <c>kid</c> (an active or retired key; a <c>next</c> key never signs), then the claims (<c>iid</c> =
/// the calling install, <c>exp</c> in the future, <c>sub</c> a UUID), then the database: the account exists and this install is
/// still linked to it (<c>account_installs</c> rows go with the account, R3-6). Every failure is the same <c>null</c>; nothing of the
/// token is logged or echoed.
/// </summary>
internal sealed class AccountTokenValidator(ISigner signer, IServiceProvider services) : IAccountTokenValidator
{
    /// <summary>A real token is about 250 characters; this caps what is parsed.</summary>
    internal const int MaxLength = 2048;

    private const string LinkedSql = """
        SELECT EXISTS (SELECT 1 FROM zaghlol.account_installs WHERE account_id = @account AND install_id = @install)
        """;

    public async Task<ValidatedAccountToken?> ValidateAsync(Sensitive<string>? token, InstallId caller, DateTimeOffset now, CancellationToken cancellationToken)
    {
        if (token?.Reveal() is not { Length: > 0 and <= MaxLength } text || !TryRead(text, caller, now, out var account, out var expires))
        {
            return null;
        }

        var source = services.GetRequiredKeyedService<NpgsqlDataSource>(DatabaseRole.App);
        await using var command = source.CreateCommand(LinkedSql);
        command.Parameters.AddWithValue("account", NpgsqlDbType.Uuid, account);
        command.Parameters.AddWithValue("install", NpgsqlDbType.Uuid, caller.Value);
        var linked = (bool)(await command.ExecuteScalarAsync(cancellationToken).ConfigureAwait(false))!;
        return linked ? new ValidatedAccountToken(account, expires) : null;
    }

    private bool TryRead(string text, InstallId caller, DateTimeOffset now, out Guid account, out DateTimeOffset expires)
    {
        account = Guid.Empty;
        expires = default;
        var parts = text.Split('.');
        if (parts.Length != 3 || parts.Any(p => p.Length == 0))
        {
            return false;
        }

        try
        {
            using var header = JsonDocument.Parse(Base64Url.DecodeFromChars(parts[0]));
            if (header.RootElement.ValueKind != JsonValueKind.Object
                || !header.RootElement.TryGetProperty("alg", out var alg) || alg.ValueKind != JsonValueKind.String || alg.GetString() != "ES256"
                || !header.RootElement.TryGetProperty("kid", out var kidElement) || kidElement.ValueKind != JsonValueKind.String)
            {
                return false;
            }

            var kid = kidElement.GetString();
            var key = signer.PublishedKeys(SigningPurpose.Entitlement)
                .FirstOrDefault(k => k.Kid == kid && k.Status is SigningKeyStatus.Active or SigningKeyStatus.Retired);
            var signature = Base64Url.DecodeFromChars(parts[2]);
            if (key is null || !key.PublicJwk.VerifiesDigest(SHA256.HashData(Encoding.ASCII.GetBytes(parts[0] + "." + parts[1])), signature))
            {
                return false;
            }

            using var payload = JsonDocument.Parse(Base64Url.DecodeFromChars(parts[1]));
            var root = payload.RootElement;
            if (root.ValueKind != JsonValueKind.Object
                || !root.TryGetProperty("sub", out var sub) || sub.ValueKind != JsonValueKind.String
                || !Guid.TryParseExact(sub.GetString(), "D", out account)
                || !root.TryGetProperty("iid", out var iid) || iid.ValueKind != JsonValueKind.String
                || !string.Equals(iid.GetString(), caller.ToString(), StringComparison.Ordinal)
                || !root.TryGetProperty("exp", out var exp) || exp.ValueKind != JsonValueKind.Number || !exp.TryGetInt64(out var expSeconds))
            {
                return false;
            }

            expires = DateTimeOffset.FromUnixTimeSeconds(expSeconds);
            return expires > now;
        }
        catch (Exception ex) when (ex is FormatException or JsonException or ArgumentException or CryptographicException or InvalidOperationException)
        {
            return false;
        }
    }
}

/// <summary>Entitlement and account-token JWS through the T-123 <see cref="ISigner"/> (ES256, active <c>e…</c> key, key in the KMS).</summary>
internal sealed class KmsEntitlementSigner(ISigner signer) : IEntitlementSigner
{
    public async Task<string> SignEntitlementAsync(EntitlementClaims claims, CancellationToken cancellationToken) =>
        await signer.CreateJwsAsync(SigningPurpose.Entitlement, claims, cancellationToken).ConfigureAwait(false);

    public async Task<string> SignAccountTokenAsync(AccountTokenClaims claims, CancellationToken cancellationToken) =>
        await signer.CreateJwsAsync(SigningPurpose.Entitlement, claims, cancellationToken).ConfigureAwait(false);
}
