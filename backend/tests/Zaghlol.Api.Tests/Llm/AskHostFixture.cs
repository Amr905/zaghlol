using System.Collections.Concurrent;
using System.Diagnostics;
using System.Diagnostics.Metrics;
using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using Serilog.Core;
using Zaghlol.Api.RateLimiting;
using Zaghlol.Api.Tests.Installs;
using Zaghlol.Application.Entitlements;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Ask;
using Zaghlol.Application.Llm.Attestation;
using Zaghlol.Application.Llm.Spend;
using Zaghlol.Domain;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Llm;

/// <summary>Maps <c>acct:&lt;guid&gt;</c> to that account (the real validator needs a signed token and an account row; T-135 tests it).</summary>
internal sealed class FakeAccountTokens : IAccountTokenValidator
{
    public Task<ValidatedAccountToken?> ValidateAsync(Sensitive<string>? token, InstallId caller, DateTimeOffset now, CancellationToken cancellationToken)
    {
        var text = token?.Reveal();
        return Task.FromResult<ValidatedAccountToken?>(
            text is not null && text.StartsWith("acct:", StringComparison.Ordinal) && Guid.TryParse(text.AsSpan(5), out var id)
                ? new ValidatedAccountToken(id, now.AddDays(1))
                : null);
    }
}

/// <summary>The real limiter unless a test forces a refusal.</summary>
internal sealed class SwitchableLimiter(ILlmRateLimiter inner) : ILlmRateLimiter
{
    public LlmRateDecision? Force { get; set; }

    public LlmRateDecision TryAcquire(LlmFeature feature, InstallId install, Guid? account, string networkKey) =>
        Force ?? inner.TryAcquire(feature, install, account, networkKey);
}

/// <summary>Delegates to the shared <see cref="FakeLlmProvider"/> (recorded replies) and can throw or stall for the paths the fake can't script.</summary>
internal sealed class ProbeProvider(FakeLlmProvider inner) : ILlmProvider
{
    public string Id => inner.Id;

    public int Calls => inner.Calls;

    public LlmCall? Last { get; private set; }

    public string? ThrowWhenQuestionContains { get; set; }

    public Task<LlmResult> CompleteAsync(LlmCall request, CancellationToken cancellationToken)
    {
        Last = request;
        if (ThrowWhenQuestionContains is { } marker && request.UserText.Reveal().Contains(marker, StringComparison.Ordinal))
        {
            Interlocked.Increment(ref throws);
            throw new InvalidOperationException("provider exploded on: " + request.UserText.Reveal());
        }

        return inner.CompleteAsync(request, cancellationToken);
    }

    private int throws;

    public int Throws => Volatile.Read(ref throws);
}

internal sealed class FakePrices : ILlmPriceList
{
    public bool TryGet(string providerId, out LlmPriceEntry entry)
    {
        entry = new LlmPriceEntry("model-x", new LlmPrices(1m, 0.5m, 4m));
        return providerId == AskHostFixture.ProviderId;
    }
}

internal sealed class FakeRegistry(ILlmProvider provider) : ILlmProviderRegistry
{
    public ValueTask<string> ActiveIdAsync(CancellationToken cancellationToken) => ValueTask.FromResult(provider.Id);

    public ValueTask<ILlmProvider> ActiveAsync(CancellationToken cancellationToken) => ValueTask.FromResult(provider);

    public ILlmProvider Resolve(string id) => provider;
}

internal sealed class FakeKeys : ILlmApiKeyProvider
{
    public bool HasKey(string providerId) => true;

    public ValueTask<LlmSensitive<string>> GetKeyAsync(string providerId, CancellationToken cancellationToken) => throw new NotSupportedException();
}

/// <summary>Every activity (any source, the OTel exporters' input) and every metric measurement, as text.</summary>
internal sealed class TelemetryCapture : IDisposable
{
    private readonly ConcurrentQueue<string> lines = new();
    private readonly ActivityListener activities;
    private readonly MeterListener meters = new();

    public TelemetryCapture()
    {
        activities = new ActivityListener
        {
            ShouldListenTo = _ => true,
            Sample = (ref ActivityCreationOptions<ActivityContext> _) => ActivitySamplingResult.AllDataAndRecorded,
            ActivityStopped = a => lines.Enqueue(string.Join(
                ' ',
                new[] { a.Source.Name, a.DisplayName, a.OperationName, a.StatusDescription ?? string.Empty }
                    .Concat(a.TagObjects.Select(t => $"{t.Key}={t.Value}"))
                    .Concat(a.Events.SelectMany(e => e.Tags.Select(t => $"{e.Name}:{t.Key}={t.Value}"))))),
        };
        ActivitySource.AddActivityListener(activities);
        meters.InstrumentPublished = (instrument, listener) => listener.EnableMeasurementEvents(instrument);
        meters.SetMeasurementEventCallback<long>((i, v, tags, _) => Record(i, tags));
        meters.SetMeasurementEventCallback<double>((i, v, tags, _) => Record(i, tags));
        meters.SetMeasurementEventCallback<int>((i, v, tags, _) => Record(i, tags));
        meters.SetMeasurementEventCallback<decimal>((i, v, tags, _) => Record(i, tags));
        meters.Start();
    }

    public IReadOnlyList<string> Lines => [.. lines];

    public void Dispose()
    {
        activities.Dispose();
        meters.Dispose();
    }

    private void Record(Instrument instrument, ReadOnlySpan<KeyValuePair<string, object?>> tags)
    {
        var text = instrument.Name;
        foreach (var tag in tags)
        {
            text += $" {tag.Key}={tag.Value}";
        }

        lines.Enqueue(text);
    }
}

/// <summary>
/// The real API (<c>Program</c>) over a migrated PostgreSQL 17 with the fake KMS, Fake attestation (a dev proof), a movable clock, the recorded
/// <see cref="FakeLlmProvider"/> as the only provider, and the two flags ON. Everything between the request and the provider is production code.
/// </summary>
public sealed class AskHostFixture : IAsyncLifetime
{
    public const string ProviderId = "fake-a";
    public const string Lang = "en";

    private static readonly byte[] DevKey = Enumerable.Range(0, 32).Select(i => (byte)(i + 7)).ToArray();

    private readonly FakeKms kms = FakeKms.CreateDefault();
    private WebApplicationFactory<Program>? factory;

    internal ManualClock Clock { get; } = new();

    internal CapturingSink LogSink { get; } = new();

    internal List<FakeReply> Replies { get; } = [];

    internal ProbeProvider Provider { get; private set; } = null!;

    internal SwitchableLimiter Limiter { get; private set; } = null!;

    public ZaghlolTestDatabase Database { get; private set; } = null!;

    public HttpClient Client { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        Database = await ZaghlolTestDatabase.StartAsync();
        Provider = new ProbeProvider(new FakeLlmProvider(ProviderId, Replies));
        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseSetting("ConnectionStrings:App", Database.Api);
            builder.UseSetting("ConnectionStrings:Admin", Database.Admin);
            builder.UseSetting("Llm:Attestation:Mode", "Fake");
            builder.UseSetting("Llm:Attestation:DevProofKey", Convert.ToBase64String(DevKey));
            builder.UseSetting("RateLimits:PerNetwork:TokenLimit", "100000");
            builder.UseSetting("RateLimits:PerNetwork:TokensPerPeriod", "100000");
            builder.UseSetting("RateLimits:PerToken:TokenLimit", "100000");
            builder.UseSetting("RateLimits:PerToken:TokensPerPeriod", "100000");
            builder.UseSetting("RateLimits:Register:TokenLimit", "100000");
            builder.UseSetting("RateLimits:Register:TokensPerPeriod", "100000");
            builder.UseSetting("RateLimits:AskInstall:TokenLimit", "1000");
            builder.UseSetting("RateLimits:AskInstall:TokensPerPeriod", "1000");
            builder.UseSetting("RateLimits:AskInstallPerDay", "1000");
            builder.UseSetting("RateLimits:AskAccount:TokenLimit", "1000");
            builder.UseSetting("RateLimits:AskAccount:TokensPerPeriod", "1000");
            builder.UseSetting("RateLimits:AskAccountPerDay", "1000");
            builder.UseSetting("RateLimits:AskNetwork:TokenLimit", "1000");
            builder.UseSetting("RateLimits:AskNetwork:TokensPerPeriod", "1000");
            foreach (var (key, value) in kms.Settings())
            {
                builder.UseSetting(key, value);
            }

            builder.ConfigureServices(services =>
            {
                kms.Use(services);
                services.AddSingleton<ILogEventSink>(LogSink);
                services.RemoveAll<TimeProvider>();
                services.AddSingleton<TimeProvider>(Clock);
                services.RemoveAll<ILlmProviderRegistry>();
                services.AddSingleton<ILlmProviderRegistry>(new FakeRegistry(Provider));
                services.RemoveAll<ILlmApiKeyProvider>();
                services.AddSingleton<ILlmApiKeyProvider>(new FakeKeys());
                services.RemoveAll<ILlmPriceList>();
                services.AddSingleton<ILlmPriceList>(new FakePrices());
                services.RemoveAll<IAccountTokenValidator>();
                services.AddSingleton<IAccountTokenValidator>(new FakeAccountTokens());
                services.RemoveAll<ILlmRateLimiter>();
                services.AddSingleton<ILlmRateLimiter>(provider => Limiter = new SwitchableLimiter(ActivatorUtilities.CreateInstance<LlmRateLimiter>(provider)));
            });
        });
        Client = factory.CreateDefaultClient(new AppHeaderHandler());
        _ = factory.Services; // start the host (and set Limiter)
        Limiter = (SwitchableLimiter)factory.Services.GetRequiredService<ILlmRateLimiter>();
        await SetFlagAsync("ask_llm", true);
        await SetFlagAsync("ask_llm_invest", true);
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

    /// <summary>Back to the real time, and the replies, forced limiter and throw marker cleared.</summary>
    public void Reset()
    {
        Clock.Advance(DateTimeOffset.UtcNow - Clock.Now);
        Replies.Clear();
        Limiter.Force = null;
        Provider.ThrowWhenQuestionContains = null;
    }

    public void SetClock(DateTimeOffset utc) => Clock.Advance(utc - Clock.Now);

    public Task SetFlagAsync(string key, bool value) => ZaghlolTestDatabase.ExecuteAsync(
        Database.Superuser,
        $"INSERT INTO zaghlol.feature_flags (key, enabled, rules, version, updated_at, updated_by) VALUES ('{key}', {(value ? "true" : "false")}, '{{}}'::jsonb, 1, now(), gen_random_uuid()) " +
        $"ON CONFLICT (key) DO UPDATE SET enabled = {(value ? "true" : "false")}, version = zaghlol.feature_flags.version + 1");

    public Task SetConfigAsync(string key, string value) => ZaghlolTestDatabase.ExecuteAsync(
        Database.Superuser,
        $"INSERT INTO zaghlol.remote_config (key, value, version, updated_at) VALUES ('{key}', '{value}', 1, now()) ON CONFLICT (key) DO UPDATE SET value = '{value}', version = zaghlol.remote_config.version + 1");

    /// <summary>Registers a new install; returns its id and token.</summary>
    public async Task<(string InstallId, string Token)> NewInstallAsync()
    {
        var installId = InstallsHostFixture.NewInstallId();
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/installs");
        request.Content = new StringContent(InstallsHostFixture.InstallBody(installId), Encoding.UTF8, "application/json");
        request.Headers.Add(Zaghlol.Api.Idempotency.IdempotencyKeys.HeaderName, InstallsHostFixture.NewKey());
        using var response = await Client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (installId, await InstallsHostFixture.TokenOf(response));
    }

    public static string NewRequestId()
    {
        const string Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
        var bytes = RandomNumberGenerator.GetBytes(24);
        return "01" + string.Concat(bytes.Select(b => Alphabet[b % 32]));
    }

    /// <summary>The body with its dev proof bound to it (<see cref="LlmBinding"/>), or without any when <paramref name="attest"/> is false.</summary>
    public static string Body(
        string installId,
        string q,
        string? requestId = null,
        string lang = Lang,
        string provider = ProviderId,
        int consentVersion = 1,
        bool attest = true,
        string extra = "")
    {
        var core = $"\"planVersion\":1,\"requestId\":\"{requestId ?? NewRequestId()}\",\"q\":{JsonSerializer.Serialize(q)},\"lang\":\"{lang}\",\"consent\":{{\"provider\":\"{provider}\",\"v\":{consentVersion.ToString(CultureInfo.InvariantCulture)}}}{extra}";
        if (!attest)
        {
            return "{" + core + "}";
        }

        using var document = JsonDocument.Parse("{" + core + "}");
        var hash = LlmBinding.BodyHash(LlmFeature.Ask, InstallId.Parse(installId), document.RootElement)!;
        var proof = Base64Url(HMACSHA256.HashData(DevKey, hash));
        return "{" + core + $",\"attestation\":{{\"type\":\"dev\",\"proof\":\"{proof}\"}}}}";
    }

    private static string Base64Url(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    public async Task<HttpResponseMessage> PostAsync(string token, string body, string? account = null, string mediaType = "application/json")
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/ask/plan");
        request.Headers.TryAddWithoutValidation("Authorization", "Bearer " + token);
        if (account is not null)
        {
            request.Headers.TryAddWithoutValidation("Zaghlol-Account", account);
        }

        request.Content = new StringContent(body, Encoding.UTF8);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue(mediaType);
        return await Client.SendAsync(request);
    }

    /// <summary>One question end to end: a fresh install unless given.</summary>
    public async Task<(HttpResponseMessage Response, string Text)> AskAsync(string token, string installId, string q, string? requestId = null, string? account = null)
    {
        var response = await PostAsync(token, Body(installId, q, requestId), account);
        return (response, await response.Content.ReadAsStringAsync());
    }

    public static FakeReply Reply(string contains, string planJson, LlmOutcome outcome = LlmOutcome.Ok)
    {
        using var document = JsonDocument.Parse(planJson);
        return new FakeReply(contains, outcome, document.RootElement.Clone(), new LlmUsage(900, 800, 120));
    }

    public async Task<int> UsedAsync(string kind, string subject)
    {
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand("SELECT coalesce(sum(used), 0)::int FROM zaghlol.llm_quota_counters WHERE feature = 'ask' AND subject_kind = $1 AND subject_id = $2::uuid", connection);
        command.Parameters.Add(new NpgsqlParameter { Value = kind });
        command.Parameters.Add(new NpgsqlParameter { Value = subject });
        return (int)(await command.ExecuteScalarAsync())!;
    }

    /// <summary>Every row of every table of the schema, as JSON text (for "nothing of the question is stored").</summary>
    public async Task<string> DumpAllTablesAsync()
    {
        var text = new StringBuilder();
        await using var connection = new NpgsqlConnection(Database.Superuser);
        await connection.OpenAsync();
        var tables = new List<string>();
        await using (var list = new NpgsqlCommand("SELECT table_name FROM information_schema.tables WHERE table_schema = 'zaghlol' AND table_type = 'BASE TABLE'", connection))
        await using (var reader = await list.ExecuteReaderAsync())
        {
            while (await reader.ReadAsync())
            {
                tables.Add(reader.GetString(0));
            }
        }

        foreach (var table in tables)
        {
            await using var command = new NpgsqlCommand($"SELECT coalesce(string_agg(row_to_json(t)::text, E'\\n'), '') FROM zaghlol.\"{table}\" t", connection);
            text.AppendLine((string)(await command.ExecuteScalarAsync())!);
        }

        return text.ToString();
    }
}
