using System.Collections.Concurrent;
using System.Net.Http.Headers;
using System.Text;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using Zaghlol.Api.Auth;
using Zaghlol.Application.Flags;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Flags;

/// <summary>Maps test bearer tokens to operators; stands in for the OIDC validator that T-136 adds.</summary>
internal sealed class FakeOperatorValidator : IOperatorTokenValidator
{
    private readonly ConcurrentDictionary<string, OperatorIdentity> tokens = new(StringComparer.Ordinal);

    public string Issue(Guid operatorId, params string[] roles)
    {
        var token = "op-" + Guid.NewGuid().ToString("N");
        tokens[token] = new OperatorIdentity(operatorId, roles);
        return token;
    }

    public ValueTask<OperatorIdentity?> ValidateAsync(string bearerToken, CancellationToken cancellationToken) =>
        ValueTask.FromResult(tokens.GetValueOrDefault(bearerToken));
}

/// <summary>Records what would have been posted to the ops channel.</summary>
internal sealed class RecordingOpsNotifier : IOpsNotifier
{
    public ConcurrentQueue<FlagState> Posted { get; } = new();

    public Task FlagChangedAsync(FlagState state, CancellationToken cancellationToken)
    {
        Posted.Enqueue(state);
        return Task.CompletedTask;
    }
}

/// <summary>
/// The real API (<c>Program</c>) over a migrated PostgreSQL 17 with the fake KMS, with the operator validator and the ops
/// channel replaced by fakes. Every test makes its own operator, so per-operator rate-limit buckets don't leak between tests.
/// </summary>
public class AdminFlagFixture : IAsyncLifetime
{
    private readonly FakeKms kms = FakeKms.CreateDefault();
    private WebApplicationFactory<Program>? factory;

    internal FakeOperatorValidator Operators { get; } = new();

    internal RecordingOpsNotifier Notifier { get; } = new();

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public HttpClient Client { get; private set; } = null!;

    public IServiceProvider Services => factory!.Services;

    protected virtual IReadOnlyDictionary<string, string?> Settings { get; } = new Dictionary<string, string?>();

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseSetting("ConnectionStrings:App", Database.Api);
            builder.UseSetting("ConnectionStrings:Admin", Database.Admin);
            foreach (var (key, value) in kms.Settings())
            {
                builder.UseSetting(key, value);
            }

            foreach (var (key, value) in Settings)
            {
                builder.UseSetting(key, value);
            }

            builder.ConfigureServices(services =>
            {
                kms.Use(services);
                services.RemoveAll<IOperatorTokenValidator>();
                services.AddSingleton<IOperatorTokenValidator>(Operators);
                services.RemoveAll<IOpsNotifier>();
                services.AddSingleton<IOpsNotifier>(Notifier);
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

    /// <summary>An operator row (the audit log references it) and a token that authenticates it with <paramref name="roles"/>.</summary>
    internal async Task<(Guid OperatorId, string Token)> NewOperatorAsync(params string[] roles)
    {
        var id = Guid.NewGuid();
        await ZaghlolTestDatabase.ExecuteAsync(
            Database.Migrator,
            $"INSERT INTO zaghlol.operators (id, oidc_subject, display_name, roles) VALUES ('{id}', 'sub-{id}', 'Test operator', ARRAY['{string.Join("','", roles)}'])");
        return (id, Operators.Issue(id, roles));
    }

    public async Task<HttpResponseMessage> SendAsync(
        HttpMethod method,
        string path,
        string? token,
        string? body = null,
        string contentType = "application/json")
    {
        using var request = new HttpRequestMessage(method, path);
        if (token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        }

        if (body is not null)
        {
            request.Content = new StringContent(body, Encoding.UTF8);
            request.Content.Headers.ContentType = new MediaTypeHeaderValue(contentType);
        }

        return await Client.SendAsync(request);
    }

    public async Task<long> AuditCountAsync(Guid operatorId)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT count(*) FROM zaghlol.audit_log WHERE operator_id = @id AND action = 'flag_update'", connection);
        command.Parameters.AddWithValue("id", operatorId);
        return (long)(await command.ExecuteScalarAsync())!;
    }
}

/// <summary>Per operator: burst 3, then one a hour.</summary>
public sealed class RateLimitedAdminFlagFixture : AdminFlagFixture
{
    protected override IReadOnlyDictionary<string, string?> Settings { get; } = new Dictionary<string, string?>
    {
        ["RateLimits:PerToken:TokenLimit"] = "3",
        ["RateLimits:PerToken:TokensPerPeriod"] = "1",
        ["RateLimits:PerToken:PeriodSeconds"] = "3600",
    };
}
