using System.Collections.Concurrent;
using System.Diagnostics;
using System.Diagnostics.Metrics;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using WireMock.RequestBuilders;
using WireMock.ResponseBuilders;
using WireMock.Server;
using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Infrastructure.Llm;
using Zaghlol.Infrastructure.Llm.Keys;
using Zaghlol.Infrastructure.Seats;
using Zaghlol.Infrastructure.Tests.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Llm;

/// <summary>
/// T-333: LLM provider keys from the KMS secret stores (File, HostSecrets, OpenBao). Every key value is random per test and built
/// at run time; none is committed.
/// </summary>
public sealed class LlmApiKeyTests : IDisposable
{
    private const string Id = "p1";
    private readonly string scratch = Directory.CreateTempSubdirectory("zaghlol-llm-keys-").FullName;

    public void Dispose() => Directory.Delete(scratch, recursive: true);

    /// <summary>A synthetic key: visible ASCII, random, never a real credential shape.</summary>
    internal static string Marker() => string.Concat("zz", "llmkey", Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(16)));

    internal static Dictionary<string, string?> ProviderSettings(Dictionary<string, string?> settings, string endpoint = "https://llm.example.test/")
    {
        settings[$"Llm:Providers:{Id}:DisplayNameAr"] = "مساعد";
        settings[$"Llm:Providers:{Id}:DisplayNameEn"] = "Helper";
        settings[$"Llm:Providers:{Id}:Kind"] = "OpenAiResponses";
        settings[$"Llm:Providers:{Id}:Model"] = "some-model";
        settings[$"Llm:Providers:{Id}:Endpoint"] = endpoint;
        settings[$"Llm:Providers:{Id}:PriceInPerMTok"] = "0.10";
        settings[$"Llm:Providers:{Id}:PriceCachedPerMTok"] = "0.01";
        settings[$"Llm:Providers:{Id}:PriceOutPerMTok"] = "0.50";
        settings["Llm:ActiveProvider"] = Id;
        return settings;
    }

    internal static ServiceProvider Host(string environment, IConfigurationRoot configuration, string contentRoot, FileKmsHost.CapturingLogs logs)
    {
        var services = new ServiceCollection();
        services.AddSingleton<IConfiguration>(configuration);
        services.AddSingleton<IHostEnvironment>(new FileKmsHost.TestEnvironment(environment, contentRoot));
        services.AddLogging(l => l.ClearProviders().AddProvider(logs).SetMinimumLevel(LogLevel.Trace));
        services.AddZaghlolKms();
        if (configuration["Kms:Scope"] != "Envelope")
        {
            services.AddZaghlolSeatKeys();
        }

        services.AddSingleton<ILlmPromptCatalog, TestPrompts>();
        services.AddZaghlolLlm(configuration);
        return services.BuildServiceProvider();
    }

    private ServiceProvider Host(string environment, Dictionary<string, string?> settings, FileKmsHost.CapturingLogs? logs = null) =>
        Host(environment, new ConfigurationBuilder().AddInMemoryCollection(settings).Build(), scratch, logs ?? new FileKmsHost.CapturingLogs());

    private static string HostValue(string text, string member = "secret", string name = "llm_" + Id) => HostSecretsKeySet.Value(name, member, text);

    // AC1 (HostSecrets): the wrapper with a secret member loads; the key is held, not logged.
    [Theory]
    [InlineData("Testing")]
    [InlineData("Production")]
    public async Task AC1_HostSecretsLoadsTheKeyFromZaghlolKeys(string environment)
    {
        var marker = Marker();
        var keys = new HostSecretsKeySet();
        var settings = ProviderSettings(keys.Settings());
        settings["ZAGHLOL_KEYS:llm_" + Id] = HostValue(marker + "\n");
        var logs = new FileKmsHost.CapturingLogs();
        await using var services = Host(environment, settings, logs);

        await FileKmsHost.StartAsync(services);

        var store = services.GetRequiredService<ILlmApiKeyProvider>();
        Assert.IsType<LlmApiKeyStore>(store);
        Assert.True(store.HasKey(Id));
        Assert.Equal(marker, (await store.GetKeyAsync(Id, CancellationToken.None)).Reveal());
        Assert.Contains(logs.Lines, l => l.Contains($"LLM key for provider {Id} loaded from HostSecrets", StringComparison.Ordinal));
        Assert.DoesNotContain(logs.Lines, l => l.Contains(marker, StringComparison.Ordinal));
    }

    // AC1: a '-' in the id may be written '_' in the variable name (shell-safe), as for the KMS keys.
    [Fact]
    public async Task AC1_HostSecretsAcceptsTheUnderscoreSpellingOfTheId()
    {
        var marker = Marker();
        var settings = new HostSecretsKeySet().Settings();
        foreach (var (key, value) in ProviderSettings([]))
        {
            settings[key.Replace(":p1:", ":open-ai:", StringComparison.Ordinal)] = value == Id ? "open-ai" : value;
        }

        settings["ZAGHLOL_KEYS:llm_open_ai"] = HostSecretsKeySet.Value("llm_open-ai", "secret", marker);
        await using var services = Host("Testing", settings);

        await FileKmsHost.StartAsync(services);

        Assert.Equal(marker, (await services.GetRequiredService<ILlmApiKeyProvider>().GetKeyAsync("open-ai", CancellationToken.None)).Reveal());
    }

    // AC1: malformed wrapper, empty value, wrong name, wrong member, a value no header can carry -> start refused, source named, no value.
    [Theory]
    [InlineData("member")]
    [InlineData("name")]
    [InlineData("empty")]
    [InlineData("not-base64url")]
    [InlineData("space")]
    [InlineData("empty-secret")]
    public async Task AC1_AMalformedHostSecretsValueRefusesTheStartWithoutTheValue(string fault)
    {
        var marker = Marker();
        var settings = ProviderSettings(new HostSecretsKeySet().Settings());
        settings["ZAGHLOL_KEYS:llm_" + Id] = fault switch
        {
            "member" => HostValue(marker, member: "key"),
            "name" => HostValue(marker, name: "llm_other"),
            "empty" => string.Empty,
            "not-base64url" => marker + "+/=",
            "space" => HostValue(marker[..10] + " " + marker[10..]),
            _ => HostValue(string.Empty),
        };
        await using var services = Host("Testing", settings);

        var error = await Assert.ThrowsAsync<LlmKeyConfigurationException>(() => FileKmsHost.StartAsync(services));

        Assert.Contains("HostSecrets (ZAGHLOL_KEYS__llm_p1)", error.Message, StringComparison.Ordinal);
        Assert.DoesNotContain(marker, error.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain(marker[..8], error.Message, StringComparison.Ordinal);
    }

    // AC1 / ADR-026: an LLM key in an appsettings file is refused like a KMS key, and the custody flag gates the source.
    [Fact]
    public async Task AC1_HostSecretsKeepsTheFileRefusalAndTheCustodyGate()
    {
        var settings = ProviderSettings(new HostSecretsKeySet().Settings());
        settings["ZAGHLOL_KEYS:llm_" + Id] = HostValue(Marker());
        await File.WriteAllTextAsync(Path.Combine(scratch, "appsettings.Production.json"), "{\"ZAGHLOL_KEYS\":{}}");
        await using (var services = Host("Testing", settings))
        {
            var error = await Assert.ThrowsAsync<KmsConfigurationException>(() => FileKmsHost.StartAsync(services));
            Assert.Equal(HostSecretsKms.InFileMessage, error.Message);
        }

        File.Delete(Path.Combine(scratch, "appsettings.Production.json"));
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(settings).Build();
        Assert.Throws<KmsConfigurationException>(() => HostSecretsKms.CheckCustody(
            new ConfigurationBuilder().AddInMemoryCollection(settings.Where(p => p.Key != HostSecretsKms.CustodyKey)).Build(),
            new FileKmsHost.TestEnvironment("Production", scratch)));
        HostSecretsKms.CheckCustody(configuration, new FileKmsHost.TestEnvironment("Production", scratch));
    }

    // AC2: a key-looking setting under Llm from a JSON file, the environment or the command line refuses the start.
    [Theory]
    [InlineData("json")]
    [InlineData("environment")]
    [InlineData("commandline")]
    public async Task AC2_AKeyInConfigurationRefusesTheStart(string source)
    {
        var marker = Marker();
        var builder = new ConfigurationBuilder().AddInMemoryCollection(ProviderSettings(new HostSecretsKeySet().Settings()));
        var prefix = "ZTEST_" + Convert.ToHexString(RandomNumberGenerator.GetBytes(4)) + "_";
        switch (source)
        {
            case "json":
                builder.AddJsonStream(new MemoryStream(System.Text.Encoding.UTF8.GetBytes(
                    "{\"Llm\":{\"Providers\":{\"p1\":{\"ApiKey\":\"" + marker + "\"}}}}")));
                break;
            case "environment":
                Environment.SetEnvironmentVariable(prefix + "Llm__Providers__p1__api_key", marker);
                builder.AddEnvironmentVariables(prefix);
                break;
            default:
                builder.AddCommandLine(["--Llm:Providers:p1:Secret=" + marker]);
                break;
        }

        try
        {
            await using var services = Host("Testing", builder.Build(), scratch, new FileKmsHost.CapturingLogs());

            var error = await Assert.ThrowsAsync<LlmKeyConfigurationException>(() => FileKmsHost.StartAsync(services));

            Assert.Equal(LlmKeyConfigurationScan.Message, error.Message);
            Assert.DoesNotContain(marker, error.ToString(), StringComparison.Ordinal);
        }
        finally
        {
            Environment.SetEnvironmentVariable(prefix + "Llm__Providers__p1__api_key", null);
        }
    }

    [Theory]
    [InlineData("ApiKey", true)]
    [InlineData("api_key", true)]
    [InlineData("OpenAiApiKey", true)]
    [InlineData("Secret", true)]
    [InlineData("Token", true)]
    [InlineData("Credentials", true)]
    [InlineData("ServiceAccountJson", true)]
    [InlineData("Password", true)]
    [InlineData("Model", false)]
    [InlineData("Endpoint", false)]
    [InlineData("PriceCachedPerMTok", false)]
    [InlineData("TimeoutMs", false)]
    [InlineData("ActiveProvider", false)]
    public void AC2_KeyNamesAreRecognised(string segment, bool forbidden) =>
        Assert.Equal(forbidden, LlmKeyConfigurationScan.IsKeyName(segment));

    // AC2: the scan also runs when the host brings its own key provider.
    [Fact]
    public async Task AC2_TheScanRunsEvenWithAnotherKeyProvider()
    {
        var settings = ProviderSettings([]);
        settings["Llm:Providers:p1:Credentials:Json"] = "x";
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(settings).Build();
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton<IConfiguration>(configuration);
        services.AddSingleton<IHostEnvironment>(new FileKmsHost.TestEnvironment("Testing", scratch));
        services.AddSingleton<ILlmApiKeyProvider, TestKeys>();
        services.AddSingleton<ILlmPromptCatalog, TestPrompts>();
        services.AddZaghlolLlm(configuration);
        await using var provider = services.BuildServiceProvider();

        await Assert.ThrowsAsync<LlmKeyConfigurationException>(() => FileKmsHost.StartAsync(provider));
    }

    // AC3: no key for the active provider -> the rest starts, the provider is paused before the circuit guard.
    [Fact]
    public async Task AC3_AMissingKeyPausesTheLlmModuleAndTheBackendStarts()
    {
        var logs = new FileKmsHost.CapturingLogs();
        await using var services = Host("Production", ProviderSettings(new HostSecretsKeySet().Settings()), logs);

        await FileKmsHost.StartAsync(services);

        // The rest of the backend works (KMS signer up), the LLM key provider says paused.
        _ = await services.GetRequiredService<ISigner>().SignAsync(SigningPurpose.Sync, "{}"u8.ToArray(), CancellationToken.None);
        var keys = services.GetRequiredService<ILlmApiKeyProvider>();
        Assert.False(keys.HasKey(Id));
        await Assert.ThrowsAsync<LlmServicePausedException>(() => keys.GetKeyAsync(Id, CancellationToken.None).AsTask());
        var provider = await services.GetRequiredService<ILlmProviderRegistry>().ActiveAsync(CancellationToken.None);
        var paused = await Assert.ThrowsAsync<LlmServicePausedException>(() => provider.CompleteAsync(LlmFixtures.Call(), CancellationToken.None));
        Assert.Equal(LlmServicePausedException.DefaultMessage, paused.Message);
        Assert.Contains(logs.Lines, l => l.Contains("Warning No LLM key for provider p1 in HostSecrets", StringComparison.Ordinal));
    }

    // AC3: no KMS provider (no secret store) -> every provider paused, nothing thrown.
    [Fact]
    public async Task AC3_NoSecretStoreMeansPausedNotAFailedStart()
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(ProviderSettings([])).Build();
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton<IConfiguration>(configuration);
        services.AddSingleton<IHostEnvironment>(new FileKmsHost.TestEnvironment("Testing", scratch));
        services.AddSingleton<ILlmPromptCatalog, TestPrompts>();
        services.AddZaghlolLlm(configuration);
        await using var provider = services.BuildServiceProvider();

        await FileKmsHost.StartAsync(provider);

        Assert.False(provider.GetRequiredService<ILlmApiKeyProvider>().HasKey(Id));
    }

    [Fact]
    public async Task TheStoreLoadsOnceAndNeverPrintsAKey()
    {
        var marker = Marker();
        var store = new LlmApiKeyStore();
        store.Set(new Dictionary<string, LlmSensitive<string>> { [Id] = new(marker) });

        Assert.Throws<InvalidOperationException>(() => store.Set(new Dictionary<string, LlmSensitive<string>>()));
        Assert.DoesNotContain(marker, store.ToString(), StringComparison.Ordinal);
        var key = await store.GetKeyAsync(Id, CancellationToken.None);
        Assert.Equal("***", key.ToString());
        Assert.Equal("\"***\"", JsonSerializer.Serialize(key));
        Assert.Equal("{\"Key\":\"***\"}", JsonSerializer.Serialize(new { Key = key }));
    }

    [Theory]
    [InlineData("ok", true)]
    [InlineData("crlf", true)]
    [InlineData("tab", false)]
    [InlineData("long", false)]
    [InlineData("non-ascii", false)]
    public void BearerKeysAreVisibleAscii(string shape, bool accepted)
    {
        var marker = Marker();
        var value = shape switch
        {
            "ok" => marker + "\n",
            "crlf" => marker + "\r\n",
            "tab" => marker + "\t",
            "long" => new string('a', LlmKeyFormats.MaxBearerChars + 1),
            _ => marker + "é",
        };

        var key = LlmKeyFormats.Check(value, LlmKeyFormat.BearerToken, out var reason);

        Assert.Equal(accepted, key is not null);
        Assert.Equal(accepted, reason is null);
        if (accepted)
        {
            Assert.Equal(marker, key);
        }
    }

    // Vertex (T-338) keeps a service-account JSON as its secret.
    [Fact]
    public void ServiceAccountJsonIsCheckedForShapeOnly()
    {
        var good = new JsonObject
        {
            ["type"] = "service_account",
            ["client_email"] = "llm@example.test",
            ["private_key"] = "placeholder-" + Marker(),
        }.ToJsonString();

        Assert.NotNull(LlmKeyFormats.Check(good, LlmKeyFormat.ServiceAccountJson, out _));
        Assert.Null(LlmKeyFormats.Check("{\"type\":\"user\"}", LlmKeyFormat.ServiceAccountJson, out var reason));
        Assert.Equal(LlmKeyFormats.ServiceAccountReason, reason);
        Assert.Null(LlmKeyFormats.Check("{not json " + good, LlmKeyFormat.ServiceAccountJson, out reason));
        Assert.DoesNotContain("placeholder", reason!, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("P1")]
    [InlineData("a/b")]
    [InlineData("..")]
    [InlineData("-x")]
    public async Task ProviderIdsThatCanNotNameAFileRefuseTheStart(string id)
    {
        var settings = new HostSecretsKeySet().Settings();
        foreach (var (key, value) in ProviderSettings([]))
        {
            settings[key.Replace(":p1:", ":" + id + ":", StringComparison.Ordinal)] = value == Id ? id : value;
        }

        await using var services = Host("Testing", settings);

        await Assert.ThrowsAsync<LlmKeyConfigurationException>(() => FileKmsHost.StartAsync(services));
    }

    // AC4 (negative proof 1) and AC5 (negative proof 2): load, 401 and 5xx paths through the real adapter and WireMock.
    [Fact]
    public async Task AC4_AC5_TheKeyReachesOnlyTheAuthorizationHeader()
    {
        var marker = Marker();
        using var server = WireMockServer.Start();
        var settings = ProviderSettings(new HostSecretsKeySet().Settings(), server.Url + "/");
        settings["ZAGHLOL_KEYS:llm_" + Id] = HostValue(marker);
        var logs = new FileKmsHost.CapturingLogs();
        using var telemetry = new TelemetryCapture();

        await using var services = Host("Testing", settings, logs);
        await FileKmsHost.StartAsync(services);
        var provider = await services.GetRequiredService<ILlmProviderRegistry>().ActiveAsync(CancellationToken.None);

        var exceptions = new List<string>();
        foreach (var status in new[] { 401, 500, 503 })
        {
            server.Reset();
            server.Given(Request.Create().WithPath("/v1/responses").UsingPost())
                .RespondWith(Response.Create().WithStatusCode(status).WithHeader("Content-Type", "application/json")
                    .WithBody("{\"error\":{\"message\":\"Incorrect API key provided\",\"type\":\"invalid_request_error\"}}"));
            var result = await provider.CompleteAsync(LlmFixtures.Call(), CancellationToken.None);
            Assert.Equal(LlmOutcome.Upstream, result.Outcome);
            exceptions.Add(JsonSerializer.Serialize(result));

            var entry = Assert.Single(server.LogEntries).RequestMessage!;
            Assert.Equal("Bearer " + marker, entry.Headers!["Authorization"].Single());
            Assert.DoesNotContain(marker, entry.Url, StringComparison.Ordinal);
            Assert.DoesNotContain(marker, entry.AbsoluteUrl, StringComparison.Ordinal);
            Assert.True(string.IsNullOrEmpty(entry.RawQuery));
            Assert.DoesNotContain(marker, entry.Body ?? string.Empty, StringComparison.Ordinal);
            Assert.DoesNotContain(
                entry.Headers!.Where(h => h.Key != "Authorization").SelectMany(h => h.Value),
                v => v.Contains(marker, StringComparison.Ordinal));
        }

        // A malformed key on another start: the refusal carries no part of it.
        var bad = ProviderSettings(new HostSecretsKeySet().Settings());
        bad["ZAGHLOL_KEYS:llm_" + Id] = HostValue(marker + " " + marker);
        await using (var refused = Host("Testing", bad, logs))
        {
            exceptions.Add((await Assert.ThrowsAsync<LlmKeyConfigurationException>(() => FileKmsHost.StartAsync(refused))).ToString());
        }

        // Paused path: its exception and message carry no key either.
        exceptions.Add(new LlmServicePausedException().ToString());

        var haystack = string.Join('\n', logs.Lines.Concat(telemetry.Lines).Concat(exceptions));
        Assert.Contains("loaded from HostSecrets", haystack, StringComparison.Ordinal);
        Assert.NotEmpty(telemetry.Lines);
        Assert.DoesNotContain(marker, haystack, StringComparison.Ordinal);
        Assert.DoesNotContain(marker[..12], haystack, StringComparison.Ordinal);
    }

    // AC1 (File KMS): llm_<id>.secret in the key directory, same owner and mode rules.
    [SupportedOSPlatform("linux")]
    [LinuxTheory]
    [InlineData("ok")]
    [InlineData("mode")]
    [InlineData("empty")]
    [InlineData("symlink")]
    [InlineData("absent")]
    public async Task AC1_FileKmsReadsTheSecretFileUnderTheT200Rules(string shape)
    {
        var marker = Marker();
        using var keys = new FileKmsKeySet();
        var path = Path.Combine(keys.Directory, "llm_" + Id + ".secret");
        switch (shape)
        {
            case "symlink":
                var outside = Path.Combine(keys.Root, "elsewhere");
                await File.WriteAllTextAsync(outside, marker);
                File.CreateSymbolicLink(path, outside);
                break;
            case "absent":
                break;
            default:
                await File.WriteAllTextAsync(path, shape == "empty" ? "\n" : marker + "\n");
                File.SetUnixFileMode(path, shape == "mode" ? UnixFileMode.UserRead | UnixFileMode.GroupRead | UnixFileMode.OtherRead : FileKmsKeySet.Mode0400);
                break;
        }

        var logs = new FileKmsHost.CapturingLogs();
        await using var services = Host("Production", ProviderSettings(keys.Settings()), logs);

        if (shape is "ok" or "absent")
        {
            await FileKmsHost.StartAsync(services);
            var store = services.GetRequiredService<ILlmApiKeyProvider>();
            Assert.Equal(shape == "ok", store.HasKey(Id));
            if (shape == "ok")
            {
                Assert.Equal(marker, (await store.GetKeyAsync(Id, CancellationToken.None)).Reveal());
            }
        }
        else
        {
            // The KMS's own directory check may refuse the entry first; either way the File source is named and the value isn't.
            var error = await Assert.ThrowsAnyAsync<Exception>(() => FileKmsHost.StartAsync(services));
            Assert.True(error is KmsConfigurationException or LlmKeyConfigurationException);
            Assert.Contains(shape == "empty" ? "File KMS (Kms:File:KeyDirectory/llm_p1.secret)" : "Kms:File:KeyDirectory", error.Message, StringComparison.Ordinal);
            Assert.DoesNotContain(marker, error.ToString(), StringComparison.Ordinal);
        }

        Assert.DoesNotContain(logs.Lines, l => l.Contains(marker, StringComparison.Ordinal));
    }

    /// <summary>Every activity (any source, the OTel exporters' input) and every metric measurement, as text.</summary>
    private sealed class TelemetryCapture : IDisposable
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
}

/// <summary>T-333 AC1/AC3 (OpenBao): KV v2 <c>zaghlol/llm/&lt;id&gt;</c> read with the API's AppRole under the setup.sh api policy.</summary>
[SupportedOSPlatform("linux")]
public sealed class LlmApiKeyOpenBaoTests : IAsyncLifetime
{
    private OpenBaoTestBed bed = null!;

    public async Task InitializeAsync() => bed = await OpenBaoTestBed.CreateAsync();

    public async Task DisposeAsync() => await bed.DisposeAsync();

    [LinuxTheory]
    [InlineData("ok")]
    [InlineData("absent")]
    [InlineData("extra-member")]
    [InlineData("not-a-string")]
    [InlineData("newline-inside")]
    public async Task AC1_AC3_OpenBaoKvHoldsTheKey(string shape)
    {
        var marker = LlmApiKeyTests.Marker();
        switch (shape)
        {
            case "ok":
                bed.Stub.PutKv("llm/p1", new JsonObject { ["secret"] = marker });
                break;
            case "extra-member":
                bed.Stub.PutKv("llm/p1", new JsonObject { ["secret"] = marker, ["note"] = "x" });
                break;
            case "not-a-string":
                bed.Stub.PutKv("llm/p1", new JsonObject { ["secret"] = new JsonArray(marker) });
                break;
            case "newline-inside":
                bed.Stub.PutKv("llm/p1", new JsonObject { ["secret"] = marker + "\n" + marker });
                break;
        }

        var logs = new FileKmsHost.CapturingLogs();
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(LlmApiKeyTests.ProviderSettings(bed.Settings())).Build();
        await using var services = LlmApiKeyTests.Host("Production", configuration, AppContext.BaseDirectory, logs);

        if (shape is "ok" or "absent")
        {
            await FileKmsHost.StartAsync(services);
            var keys = services.GetRequiredService<ILlmApiKeyProvider>();
            Assert.Equal(shape == "ok", keys.HasKey("p1"));
            if (shape == "ok")
            {
                Assert.Equal(marker, (await keys.GetKeyAsync("p1", CancellationToken.None)).Reveal());
                Assert.Contains(bed.Stub.Requests, r => r.StartsWith("GET /v1/zaghlol/data/llm/p1", StringComparison.Ordinal));
            }
            else
            {
                Assert.Contains(logs.Lines, l => l.Contains("No LLM key for provider p1 in OpenBao", StringComparison.Ordinal));
            }
        }
        else
        {
            var error = await Assert.ThrowsAsync<LlmKeyConfigurationException>(() => FileKmsHost.StartAsync(services));
            Assert.Contains("OpenBao KV (zaghlol/llm/p1)", error.Message, StringComparison.Ordinal);
            Assert.DoesNotContain(marker, error.ToString(), StringComparison.Ordinal);
        }

        Assert.DoesNotContain(logs.Lines, l => l.Contains(marker, StringComparison.Ordinal));
    }

    // AC3: a policy that can't read the path (the worker's) leaves the provider paused; the backend still starts.
    [LinuxFact]
    public async Task AC3_APolicyWithoutTheKvPathPausesTheProvider()
    {
        bed.Stub.PutKv("llm/p1", new JsonObject { ["secret"] = LlmApiKeyTests.Marker() });
        var settings = LlmApiKeyTests.ProviderSettings(bed.Settings(worker: true));
        var logs = new FileKmsHost.CapturingLogs();
        await using var services = LlmApiKeyTests.Host("Production", new ConfigurationBuilder().AddInMemoryCollection(settings).Build(), AppContext.BaseDirectory, logs);

        await FileKmsHost.StartAsync(services);

        Assert.False(services.GetRequiredService<ILlmApiKeyProvider>().HasKey("p1"));
        Assert.Contains(logs.Lines, l => l.Contains("could not be read from OpenBao KV", StringComparison.Ordinal));
    }
}
