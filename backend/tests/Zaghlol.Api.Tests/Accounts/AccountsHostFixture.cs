using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using Zaghlol.Api.Endpoints.V1;
using Zaghlol.Api.Signing;
using Zaghlol.Api.Tests.Installs;
using Zaghlol.Application.Accounts;
using Zaghlol.Application.Seats;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Accounts;
using Zaghlol.Infrastructure.Entitlements;
using Zaghlol.Infrastructure.Seats;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Accounts;

/// <summary>
/// A scripted <see cref="IIdTokenVerifier"/>: <see cref="Mint"/> returns an opaque compact-JWS-shaped string that maps to the claims
/// the test chose (the real verifier is covered separately against <c>FakeOidcIssuer</c>). No network, no key.
/// </summary>
public sealed class FakeIdTokenVerifier : IIdTokenVerifier
{
    private readonly ConcurrentDictionary<string, IdTokenResult> tokens = new(StringComparer.Ordinal);

    public bool Down { get; set; }

    public int Calls => Volatile.Read(ref calls);

    private int calls;

    /// <summary><c>hex(SHA-256(raw))</c>: what the app hands the provider.</summary>
    public static string Hashed(string rawNonce) => Convert.ToHexStringLower(SHA256.HashData(Encoding.ASCII.GetBytes(rawNonce)));

    public static string NewRawNonce() => System.Buffers.Text.Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(16));

    /// <summary>A token for <paramref name="subject"/> whose nonce claim is <c>hex(SHA-256(rawNonce))</c> (or <paramref name="claim"/>, or none).</summary>
    public string Mint(
        string subject,
        string? rawNonce,
        DateTimeOffset now,
        bool omitNonceClaim = false,
        string? claim = null,
        TimeSpan? age = null,
        string? email = null,
        string audience = "test-client")
    {
        var nonce = omitNonceClaim ? null : claim ?? (rawNonce is null ? null : Hashed(rawNonce));
        var iat = now - (age ?? TimeSpan.FromSeconds(5));
        var token = "eyJhbGciOiJSUzI1NiJ9." + Guid.NewGuid().ToString("N") + ".c2ln";
        tokens[token] = new IdTokenResult(IdTokenOutcome.Verified, new VerifiedIdToken(subject, email, audience, nonce, iat, now + TimeSpan.FromHours(1)));
        return token;
    }

    public ValueTask<IdTokenResult> VerifyAsync(AccountProvider provider, Sensitive<string> idToken, CancellationToken cancellationToken)
    {
        Interlocked.Increment(ref calls);
        if (Down)
        {
            return ValueTask.FromResult(IdTokenResult.Unavailable);
        }

        return ValueTask.FromResult(tokens.TryGetValue(idToken.Reveal(), out var result) ? result : IdTokenResult.Invalid);
    }
}

/// <summary>A scripted Sign in with Apple token endpoint.</summary>
public sealed class FakeAppleAccountClient : IAppleAccountClient
{
    public bool FailExchange { get; set; }

    public AppleRevokeOutcome RevokeOutcome { get; set; } = AppleRevokeOutcome.Revoked;

    public ConcurrentQueue<string> Exchanged { get; } = new();

    public ConcurrentQueue<string> Revoked { get; } = new();

    public Task<AppleRefreshToken?> ExchangeCodeAsync(Sensitive<string> code, string clientId, string expectedSubject, CancellationToken cancellationToken)
    {
        if (FailExchange)
        {
            return Task.FromResult<AppleRefreshToken?>(null);
        }

        Exchanged.Enqueue(code.Reveal());
        return Task.FromResult<AppleRefreshToken?>(new AppleRefreshToken(clientId, new Sensitive<string>("refresh-for-" + code.Reveal())));
    }

    public Task<AppleRevokeOutcome> RevokeAsync(AppleRefreshToken token, CancellationToken cancellationToken)
    {
        if (RevokeOutcome == AppleRevokeOutcome.Revoked)
        {
            Revoked.Enqueue(token.Token.Reveal());
        }

        return Task.FromResult(RevokeOutcome);
    }
}

public sealed class RecordingTelemetry : ISeatTelemetry
{
    public ConcurrentQueue<(string Channel, string Kind)> Changes { get; } = new();

    public ConcurrentQueue<Guid> Alerts { get; } = new();

    public void Changed(string channel, string kind) => Changes.Enqueue((channel, kind));

    public void RebindOverCap(Guid purchaseId) => Alerts.Enqueue(purchaseId);
}

/// <summary>
/// The install host plus the real seat, seat-key, entitlement and account services and the account endpoints (T-135), with the ID-token
/// verifier and Apple's token endpoint scripted. Rows are seeded and read as superuser; every account and seat change itself goes
/// through the real endpoints on the App login.
/// </summary>
public sealed class AccountsHostFixture : InstallsHostFixture
{
    public const string AndroidPackage = "app.zaghlol.test";

    public FakeIdTokenVerifier Tokens { get; } = new();

    public FakeAppleAccountClient Apple { get; } = new();

    public RecordingTelemetry Telemetry { get; } = new();

    protected override IReadOnlyDictionary<string, string?> Settings
    {
        get
        {
            var settings = new Dictionary<string, string?>(base.Settings)
            {
                ["RateLimits:PerToken:TokenLimit"] = "1000",
                ["RateLimits:PerToken:TokensPerPeriod"] = "1000",
                ["Accounts:AndroidPackage"] = AndroidPackage,
            };
            return settings;
        }
    }

    protected override void ConfigureServices(IServiceCollection services)
    {
        services.AddSingleton<ISeatTelemetry>(Telemetry);
        services.AddZaghlolSeatKeys();
        services.AddZaghlolSeats();
        services.AddZaghlolEntitlements();
        services.AddZaghlolAccounts();
        services.RemoveAll<IIdTokenVerifier>();
        services.AddSingleton<IIdTokenVerifier>(Tokens);
        services.RemoveAll<IAppleAccountClient>();
        services.AddSingleton<IAppleAccountClient>(Apple);
    }

    protected override void MapEndpoints(WebApplication application) => application.MapAccounts();

    /// <summary>A 22-plus character raw nonce plus the token for it, as the app would send.</summary>
    public (string Raw, string IdToken) Credential(string subject, bool omitNonceClaim = false, string? claim = null, TimeSpan? age = null, string? email = null)
    {
        var raw = FakeIdTokenVerifier.NewRawNonce();
        return (raw, Tokens.Mint(subject, raw, Clock.Now, omitNonceClaim, claim, age, email));
    }

    public static string SignInBody(
        string provider, string idToken, string? nonce, string? authorizationCode = null, bool? replaceLink = null, IEnumerable<(string PublicKey, string Signature)>? seatKeys = null)
    {
        var members = new List<string> { $"\"provider\":\"{provider}\"", $"\"idToken\":\"{idToken}\"" };
        if (nonce is not null)
        {
            members.Add($"\"nonce\":\"{nonce}\"");
        }

        if (authorizationCode is not null)
        {
            members.Add($"\"authorizationCode\":\"{authorizationCode}\"");
        }

        if (replaceLink is { } replace)
        {
            members.Add($"\"replaceLink\":{(replace ? "true" : "false")}");
        }

        if (seatKeys is not null)
        {
            members.Add("\"seatKeys\":[" + string.Join(',', seatKeys.Select(k => $"{{\"publicKey\":\"{k.PublicKey}\",\"signature\":\"{k.Signature}\"}}")) + "]");
        }

        return "{" + string.Join(',', members) + "}";
    }

    public async Task<HttpResponseMessage> SignInAsync(string installToken, string body, string? key = null, string? timeNonce = null, string? accountToken = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/accounts/signin");
        request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + installToken);
        request.Headers.Add(Idempotency.IdempotencyKeys.HeaderName, key ?? NewKey());
        if (timeNonce is not null)
        {
            request.Headers.Add(TimeNonceFilter.HeaderName, timeNonce);
        }

        if (accountToken is not null)
        {
            request.Headers.Add("Zaghlol-Account", accountToken);
        }

        request.Content = new StringContent(body, Encoding.UTF8, "application/json");
        return await Client.SendAsync(request);
    }

    public async Task<HttpResponseMessage> AccountCallAsync(HttpMethod method, string path, string installToken, string? accountToken, string? timeNonce = null)
    {
        using var request = new HttpRequestMessage(method, path);
        request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + installToken);
        if (accountToken is not null)
        {
            request.Headers.Add("Zaghlol-Account", accountToken);
        }

        if (timeNonce is not null)
        {
            request.Headers.Add(TimeNonceFilter.HeaderName, timeNonce);
        }

        return await Client.SendAsync(request);
    }

    /// <summary>Registers an install of <paramref name="platform"/> through the real endpoint.</summary>
    public async Task<(Guid InstallId, string Token)> NewInstallOfAsync(string platform)
    {
        var installId = NewInstallId();
        using var response = await RegisterAsync(InstallBody(installId, platform), NewKey());
        Assert.Equal(System.Net.HttpStatusCode.Created, response.StatusCode);
        return (Guid.Parse(installId), await TokenOf(response));
    }

    // ---- seeding and reading as superuser -------------------------------------------------------------------------------------

    /// <param name="nextMoveAt">Must be a whole UTC hour (the seat CHECK); the cooldown runs while it lies ahead of the host clock.</param>
    public async Task<Guid> PurchaseAsync(Guid? buyer, Guid? holder, string state = "active", DateTimeOffset? nextMoveAt = null)
    {
        var id = Guid.CreateVersion7();
        await ExecuteAsync(
            """
            INSERT INTO zaghlol.purchases (id, store, product_id, plan, store_key, install_id, state, environment, last_verified_at)
            VALUES (@id, 'google_play', 'zaghlol_gold_monthly', 'monthly', @key, @buyer::uuid, @state, 'production', now())
            """,
            ("id", id),
            ("key", Guid.NewGuid().ToString("N")),
            ("buyer", (object?)buyer ?? DBNull.Value),
            ("state", state));
        if (holder is not null)
        {
            await ExecuteAsync(
                """
                INSERT INTO zaghlol.purchase_seats (purchase_id, install_id, proof, bound_at, last_moved_at, next_move_at, recent_rebinds)
                VALUES (@id, @holder, 'binding', now(), @next::timestamptz - interval '30 days', @next::timestamptz, '{}')
                """,
                ("id", id),
                ("holder", holder.Value),
                ("next", (object?)nextMoveAt?.UtcDateTime ?? DBNull.Value));
        }

        return id;
    }

    public async Task ExecuteAsync(string sql, params (string Name, object Value)[] parameters)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        foreach (var (name, value) in parameters)
        {
            command.Parameters.Add(value is DBNull
                ? new NpgsqlParameter(name, NpgsqlTypes.NpgsqlDbType.Unknown) { Value = DBNull.Value }
                : new NpgsqlParameter(name, value));
        }

        await command.ExecuteNonQueryAsync();
    }

    public async Task<T?> ScalarAsync<T>(string sql, params (string Name, object Value)[] parameters)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        foreach (var (name, value) in parameters)
        {
            command.Parameters.AddWithValue(name, value);
        }

        var result = await command.ExecuteScalarAsync();
        return result is null or DBNull ? default : (T)result;
    }

    public Task<long> CountAsync(string sql, params (string Name, object Value)[] parameters) => ScalarAsync<long>(sql, parameters);

    public async Task<(Guid? Account, string? LinkedBy, DateTimeOffset? Reclaim)> PurchaseLinkAsync(Guid purchase)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT account_id, account_linked_by, attach_reclaim_used_at FROM zaghlol.purchases WHERE id = @id", connection);
        command.Parameters.AddWithValue("id", purchase);
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        return (
            reader.IsDBNull(0) ? null : reader.GetGuid(0),
            reader.IsDBNull(1) ? null : reader.GetString(1),
            reader.IsDBNull(2) ? null : reader.GetFieldValue<DateTimeOffset>(2));
    }

    public async Task<(Guid? Holder, DateTimeOffset? NextMoveAt, bool KeyTrusted, bool HasKey)> SeatAsync(Guid purchase)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "SELECT install_id, next_move_at, device_key_trusted, device_key_hash IS NOT NULL FROM zaghlol.purchase_seats WHERE purchase_id = @id", connection);
        command.Parameters.AddWithValue("id", purchase);
        await using var reader = await command.ExecuteReaderAsync();
        Assert.True(await reader.ReadAsync());
        return (
            reader.IsDBNull(0) ? null : reader.GetGuid(0),
            reader.IsDBNull(1) ? null : reader.GetFieldValue<DateTimeOffset>(1),
            reader.GetBoolean(2),
            reader.GetBoolean(3));
    }

    public async Task<List<string>> EventsAsync(Guid purchase)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT cause FROM zaghlol.purchase_events WHERE purchase_id = @id ORDER BY occurred_at, id", connection);
        command.Parameters.AddWithValue("id", purchase);
        await using var reader = await command.ExecuteReaderAsync();
        var causes = new List<string>();
        while (await reader.ReadAsync())
        {
            causes.Add(reader.GetString(0));
        }

        return causes;
    }

    public async Task<List<(Guid Install, string Channel)>> ClaimantsAsync(Guid purchase)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT install_id, channel FROM zaghlol.seat_claimants WHERE purchase_id = @id", connection);
        command.Parameters.AddWithValue("id", purchase);
        await using var reader = await command.ExecuteReaderAsync();
        var rows = new List<(Guid, string)>();
        while (await reader.ReadAsync())
        {
            rows.Add((reader.GetGuid(0), reader.GetString(1)));
        }

        return rows;
    }

    /// <summary>The <c>status</c> claim of an entitlement JWS (payload only; the signature is covered by the signing tests).</summary>
    public static string StatusOf(string entitlementToken)
    {
        using var payload = JsonDocument.Parse(System.Buffers.Text.Base64Url.DecodeFromChars(entitlementToken.Split('.')[1]));
        return payload.RootElement.GetProperty("status").GetString()!;
    }
}
