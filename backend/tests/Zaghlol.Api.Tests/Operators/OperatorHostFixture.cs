using System.Collections;
using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.Routing.Patterns;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http.Metadata;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using OpenTelemetry.Trace;
using Serilog.Core;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Tests.Flags;
using Zaghlol.Application.Flags;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Operators;

/// <summary>A collection the span exporter can add to while a test reads it.</summary>
public sealed class LockedCollection<T> : ICollection<T>
{
    private readonly List<T> items = [];

    public int Count
    {
        get
        {
            lock (items)
            {
                return items.Count;
            }
        }
    }

    public bool IsReadOnly => false;

    public void Add(T item)
    {
        lock (items)
        {
            items.Add(item);
        }
    }

    public void Clear()
    {
        lock (items)
        {
            items.Clear();
        }
    }

    public bool Contains(T item)
    {
        lock (items)
        {
            return items.Contains(item);
        }
    }

    public void CopyTo(T[] array, int arrayIndex)
    {
        lock (items)
        {
            items.CopyTo(array, arrayIndex);
        }
    }

    public bool Remove(T item)
    {
        lock (items)
        {
            return items.Remove(item);
        }
    }

    public IEnumerator<T> GetEnumerator() => Snapshot().GetEnumerator();

    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();

    public List<T> Snapshot()
    {
        lock (items)
        {
            return [.. items];
        }
    }
}

/// <summary>An <c>/admin/v1</c> endpoint of the running host: method, route template and the operator roles it requires.</summary>
public sealed record AdminEndpoint(string Method, string Route, IReadOnlyList<string> Roles)
{
    public string Key => Method + " " + Route;
}

/// <summary>
/// The real API (<c>Program</c>) over a migrated PostgreSQL 17 with the fake KMS and the real OIDC validator, whose IdP is
/// <see cref="FakeOidcIssuer"/> (Advisory mode, Entra profile). Logs go to <see cref="Logs"/> and spans (after the redacting
/// processor) to <see cref="Spans"/>. The support-lookup bucket is 3 per operator, so the rate-limit test needs few calls;
/// every test makes its own operators.
/// </summary>
public sealed class OperatorHostFixture : IAsyncLifetime
{
    public const string ContextId = "c1";

    private readonly FakeKms kms = FakeKms.CreateDefault();
    private WebApplicationFactory<Program>? factory;

    public FakeOidcIssuer Issuer { get; } = new();

    public CapturingSink Logs { get; } = new();

    public LockedCollection<Activity> Spans { get; } = new();

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public HttpClient Client { get; private set; } = null!;

    public IServiceProvider Services => factory!.Services;

    public string SnapshotDirectory { get; } = Path.Combine(Path.GetTempPath(), "zaghlol-t136-" + Guid.NewGuid().ToString("N"));

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            var settings = new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["ConnectionStrings:App"] = Database.Api,
                ["ConnectionStrings:Admin"] = Database.Admin,
                ["OperatorAuth:Enabled"] = "true",
                ["OperatorAuth:Profile"] = "Entra",
                ["OperatorAuth:Issuer"] = FakeOidcIssuer.DefaultIssuer,
                ["OperatorAuth:Audiences:0"] = FakeOidcIssuer.CliAudience,
                ["OperatorAuth:Audiences:1"] = FakeOidcIssuer.AdminAudience,
                ["OperatorAuth:PhishingResistantMode"] = "Advisory",
                ["OperatorAuth:RequiredAcrs"] = ContextId,
                ["Catalog:Snapshots:Directory"] = SnapshotDirectory,
                ["Catalog:Snapshots:BaseUrl"] = "https://api.zaghlol.test",
                ["RateLimits:PerNetwork:TokenLimit"] = "100000",
                ["RateLimits:PerNetwork:TokensPerPeriod"] = "100000",
                ["RateLimits:PerNetwork:PeriodSeconds"] = "60",
                ["RateLimits:PerToken:TokenLimit"] = "100000",
                ["RateLimits:PerToken:TokensPerPeriod"] = "100000",
                ["RateLimits:PerToken:PeriodSeconds"] = "60",
                ["RateLimits:SupportLookup:TokenLimit"] = "3",
                ["RateLimits:SupportLookup:TokensPerPeriod"] = "1",
                ["RateLimits:SupportLookup:PeriodSeconds"] = "3600",
            };
            foreach (var (key, value) in settings)
            {
                builder.UseSetting(key, value);
            }

            foreach (var (key, value) in kms.Settings())
            {
                builder.UseSetting(key, value);
            }

            builder.ConfigureServices(services =>
            {
                kms.Use(services);
                services.AddSingleton<ILogEventSink>(Logs);
                services.AddOpenTelemetry().WithTracing(tracing => tracing.AddInMemoryExporter(Spans));
                services.AddHttpClient(OidcKeyCache.HttpClientName).ConfigurePrimaryHttpMessageHandler(() => Issuer.CreateHandler());
                services.RemoveAll<IOpsNotifier>();
                services.AddSingleton<IOpsNotifier>(new RecordingOpsNotifier());
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
        Issuer.Dispose();
        if (Directory.Exists(SnapshotDirectory))
        {
            Directory.Delete(SnapshotDirectory, recursive: true);
        }
    }

    /// <summary>A new <c>operators</c> row (as <c>seed-operator.sql</c> would create it) and its OIDC subject.</summary>
    public async Task<(Guid Id, string Subject)> NewOperatorAsync(params string[] roles)
    {
        var id = Guid.NewGuid();
        var subject = "sub-" + Guid.NewGuid().ToString("N");
        await using var connection = new NpgsqlConnection(Database.Migrator);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(
            "INSERT INTO zaghlol.operators (id, oidc_subject, display_name, roles) VALUES (@id, @sub, 'T-136 operator', @roles)",
            connection);
        command.Parameters.AddWithValue("id", id);
        command.Parameters.AddWithValue("sub", subject);
        command.Parameters.AddWithValue("roles", roles);
        await command.ExecuteNonQueryAsync();
        return (id, subject);
    }

    /// <summary>A fresh, valid MFA token for <paramref name="subject"/>.</summary>
    public string Token(string subject, IReadOnlyList<string>? acrs = null) =>
        Issuer.Mint(new OperatorTokenSpec { Subject = subject, Acrs = acrs }, DateTimeOffset.UtcNow);

    public async Task<HttpResponseMessage> SendAsync(HttpMethod method, string path, string? token, string? body = null)
    {
        using var request = new HttpRequestMessage(method, path);
        if (token is not null)
        {
            request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        }

        if (body is not null)
        {
            request.Content = new StringContent(body, Encoding.UTF8);
            request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        }

        return await Client.SendAsync(request);
    }

    public async Task<object?> ScalarAsync(string sql, params (string Name, object Value)[] parameters)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        foreach (var (name, value) in parameters)
        {
            command.Parameters.AddWithValue(name, value);
        }

        var result = await command.ExecuteScalarAsync();
        return result is DBNull ? null : result;
    }

    public async Task ExecuteAsync(string sql, params (string Name, object Value)[] parameters)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        foreach (var (name, value) in parameters)
        {
            command.Parameters.AddWithValue(name, value);
        }

        await command.ExecuteNonQueryAsync();
    }

    public async Task<long> AuditCountAsync(Guid operatorId) =>
        (long)(await ScalarAsync("SELECT count(*) FROM zaghlol.audit_log WHERE operator_id = @id", ("id", operatorId)))!;

    /// <summary>Every route endpoint of the running host whose template starts with <paramref name="prefix"/>.</summary>
    public IReadOnlyList<AdminEndpoint> Endpoints(string prefix)
    {
        var source = Services.GetRequiredService<EndpointDataSource>();
        var result = new List<AdminEndpoint>();
        foreach (var endpoint in source.Endpoints.OfType<RouteEndpoint>())
        {
            var route = Template(endpoint.RoutePattern);
            if (!route.StartsWith(prefix, StringComparison.Ordinal))
            {
                continue;
            }

            var roles = endpoint.Metadata.GetOrderedMetadata<IAuthorizeData>()
                .Select(a => a.Policy)
                .OfType<string>()
                .Where(p => p.StartsWith(OperatorAuthentication.PolicyPrefix, StringComparison.Ordinal))
                .Select(p => p[OperatorAuthentication.PolicyPrefix.Length..])
                .Distinct(StringComparer.Ordinal)
                .ToList();
            foreach (var method in endpoint.Metadata.GetMetadata<IHttpMethodMetadata>()?.HttpMethods ?? new[] { "*" })
            {
                result.Add(new AdminEndpoint(method, route, roles));
            }
        }

        return result;
    }

    /// <summary>The route template rebuilt from its segments (group prefixes included).</summary>
    public static string Template(RoutePattern pattern)
    {
        ArgumentNullException.ThrowIfNull(pattern);

        return "/" + string.Join('/', pattern.PathSegments.Select(segment => string.Concat(segment.Parts.Select(part => part switch
        {
            RoutePatternLiteralPart literal => literal.Content,
            RoutePatternParameterPart parameter => "{" + parameter.Name + "}",
            RoutePatternSeparatorPart separator => separator.Content,
            _ => "?",
        }))));
    }
}
