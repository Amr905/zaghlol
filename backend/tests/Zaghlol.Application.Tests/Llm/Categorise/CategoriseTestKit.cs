using System.Text;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Config;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Ask;
using Zaghlol.Application.Llm.Categorise;
using Zaghlol.Application.Llm.Quota;
using Zaghlol.Application.Tests.Llm.Ask;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Llm.Categorise;

/// <summary>The categorise pipeline over the scripted gates of <see cref="AskTestKit"/>, a scripted catalog and an in-memory cache.</summary>
internal sealed class CategoriseTestKit
{
    public const string RequestId = "01JD8Z3Q4F6R7T9V0W1X2Y3Z4A";

    public AskTestKit Ask { get; } = new();

    public FakeCatalog Catalog { get; } = new();

    public MemoryCache Cache { get; } = new();

    public CapturingLog Logs { get; } = new();

    public CategoriseService Service { get; }

    public CategoriseTestKit()
    {
        Ask.Flags.On.Add(LlmGateFeature.Categorise);
        Ask.Quota.Check = new LlmQuotaCheck(LlmQuotaCheckKind.Allowed, 15, 4, 11, ScriptedQuota.Resets);
        Ask.Quota.Commit = new LlmQuotaCommit(LlmQuotaCheckKind.Allowed, 1, 10, false);
        Service = new CategoriseService(Ask.Chain, Ask.Registry, new Zaghlol.Application.Llm.Prompts.EmbeddedLlmPromptCatalog(), Ask.Spend, Catalog, Cache, Ask.Quota, new Config(), Ask.Metrics, new AskTestKit.Clock(), Logs);
    }

    public static LlmGateRequest Gate(string requestId = RequestId) => new(
        LlmFeature.Categorise, AskTestKit.Install, "android", "1.0.0", null, "10.0.0.0/24", "p1", 1, requestId, new byte[32], null);

    public static CategoriseRequest Request(params string[] merchants) => new(
        RequestId,
        "en",
        [.. merchants.Select(m => new LlmSensitive<string>(m))],
        [.. merchants.Select(m => new LlmSensitive<string>(Zaghlol.Application.Catalog.CatalogText.Normalize(m)))],
        "p1",
        1,
        null,
        false);

    public Task<CategoriseResult> RunAsync(string[] merchants, LlmGateRequest? gate = null, CancellationToken ct = default) =>
        Service.CategoriseAsync(gate ?? Gate(), Request(merchants), ct);

    /// <summary>A provider reply for a batch: one <c>{"i","c","p"}</c> item per entry.</summary>
    public static string Reply(params (int I, string C, int P)[] items) =>
        "{\"r\":[" + string.Join(',', items.Select(x => $"{{\"i\":{x.I},\"c\":\"{x.C}\",\"p\":{x.P}}}")) + "]}";

    public void ProviderReplies(string json) => Ask.Provider.Reply = (_, _) => Task.FromResult(ScriptedProvider.Ok(json));

    public static string[] Statuses(CategoriseResult result) => [.. result.Answer!.Items.Select(i => i.Status + (i.Source is null ? string.Empty : "/" + i.Source))];

    internal sealed class Config : IRemoteConfigService
    {
        public Task<RemoteConfigSnapshot> GetAsync(CancellationToken cancellationToken) => Task.FromResult(RemoteConfigService.Build([]));
    }

    internal sealed class FakeCatalog : ICategoriseCatalog
    {
        public Exception? Throw { get; set; }

        public CatalogAliasIndex Index { get; set; } = new([new CatalogAliasEntry(1, "green leaf pharmacy", "exact")], new Dictionary<int, string> { [1] = "health" });

        public Task<CategoriseCatalog> GetAsync(CancellationToken cancellationToken) =>
            Throw is { } e ? Task.FromException<CategoriseCatalog>(e) : Task.FromResult(new CategoriseCatalog(1, [.. CategoriseContract.DefaultCodes], Index));
    }

    internal sealed class MemoryCache : ICategoriseAnswerCache
    {
        public Dictionary<string, CachedAnswer> Rows { get; } = new(StringComparer.Ordinal);

        public Dictionary<string, int> Hits { get; } = new(StringComparer.Ordinal);

        public Exception? ThrowOnRead { get; set; }

        public Exception? ThrowOnWrite { get; set; }

        public int Writes { get; private set; }

        public Task<IReadOnlyDictionary<string, CachedAnswer>> GetAsync(IReadOnlyList<string> keys, DateTimeOffset now, CancellationToken cancellationToken)
        {
            if (ThrowOnRead is { } e)
            {
                return Task.FromException<IReadOnlyDictionary<string, CachedAnswer>>(e);
            }

            var found = keys.Where(Rows.ContainsKey).ToDictionary(k => k, k => Rows[k], StringComparer.Ordinal);
            foreach (var key in found.Keys)
            {
                Hits[key] = Hits.GetValueOrDefault(key) + 1;
            }

            return Task.FromResult<IReadOnlyDictionary<string, CachedAnswer>>(found);
        }

        public Task PutAsync(IReadOnlyList<CacheWrite> rows, DateTimeOffset now, CancellationToken cancellationToken)
        {
            if (ThrowOnWrite is { } e)
            {
                return Task.FromException(e);
            }

            Writes += rows.Count;
            foreach (var row in rows)
            {
                Rows[row.Key] = new CachedAnswer(row.Category, row.Confidence);
            }

            return Task.CompletedTask;
        }
    }

    internal sealed class CapturingLog : ILogger<CategoriseService>
    {
        public List<string> Lines { get; } = [];

        public IDisposable? BeginScope<TState>(TState state)
            where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
            Lines.Add(formatter(state, exception) + exception);
    }
}
