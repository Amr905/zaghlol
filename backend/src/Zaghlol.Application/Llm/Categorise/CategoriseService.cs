using System.Diagnostics;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Config;
using Zaghlol.Application.Llm.Ask;
using Zaghlol.Application.Llm.Prompts;
using Zaghlol.Application.Llm.Quota;
using Zaghlol.Application.Llm.Spend;

namespace Zaghlol.Application.Llm.Categorise;

public enum CategoriseKind
{
    /// <summary>200: <see cref="CategoriseResult.Answer"/> is set.</summary>
    Answered,

    /// <summary>A gate refused: see <see cref="CategoriseResult.Gate"/>.</summary>
    Refused,

    /// <summary><c>502 UPSTREAM_UNAVAILABLE</c>: the provider timed out, failed or its circuit is open. Nothing counted.</summary>
    Upstream,

    /// <summary><c>503 LLM_SERVICE_PAUSED</c>: paused after the gates (spend reservation, key, catalog or quota store).</summary>
    Paused,
}

public static class CategoriseStatus
{
    public const string Ok = "ok";
    public const string Unknown = "unknown";
    public const string LowConfidence = "low_confidence";
    public const string Rejected = "rejected";
    public const string Quota = "quota";
}

public static class CategoriseSource
{
    public const string Llm = "llm";
    public const string Cache = "cache";
    public const string Catalog = "catalog";
}

/// <summary>One per-merchant result; the merchant is sensitive and is revealed only by the endpoint, to write the response to the phone that sent it.</summary>
public sealed record CategoriseItem(LlmSensitive<string> Merchant, string Status, string? Category = null, int? Confidence = null, string? Source = null);

public sealed record CategoriseAnswer(IReadOnlyList<CategoriseItem> Items, int Counted, LlmQuotaView Quota);

public sealed record CategoriseResult(CategoriseKind Kind, LlmGateResult Gate, CategoriseAnswer? Answer = null);

/// <summary>
/// <c>POST /v1/categorise</c> after the body is parsed (llm-categorise §3; design note in <c>docs/04-tasks/tasks/T-352.md</c>): the shared gate chain, then per
/// merchant in request order privacy, published catalog (free), answer cache (free), a trim to the quota left, one provider call for the rest with the
/// <c>cat-v1</c> prompt and the closed category set, validation, one commit of the number of <c>ok/llm</c> answers and the cache upsert. Merchant names are
/// <see cref="LlmSensitive{T}"/>; logs carry fixed codes only and every provider or store exception is caught and its message dropped.
/// </summary>
public sealed partial class CategoriseService(
    LlmGateChain gates,
    ILlmProviderRegistry registry,
    ILlmPromptCatalog prompts,
    ISpendGuard spend,
    ICategoriseCatalog catalog,
    ICategoriseAnswerCache cache,
    ILlmQuotaStore quota,
    IRemoteConfigService config,
    ILlmMetrics metrics,
    TimeProvider clock,
    ILogger<CategoriseService> logger)
{
    public const int OutputTokensPerName = 25;
    public const int OutputTokensBase = 20;

    public static int MaxOutputTokens(int names) => (OutputTokensPerName * names) + OutputTokensBase;

    public async Task<CategoriseResult> CategoriseAsync(LlmGateRequest gate, CategoriseRequest request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(gate);
        ArgumentNullException.ThrowIfNull(request);

        var admitted = await gates.AdmitAsync(gate, cancellationToken).ConfigureAwait(false);
        if (!admitted.IsAdmitted)
        {
            return new CategoriseResult(CategoriseKind.Refused, admitted);
        }

        CategoriseCatalog published;
        RemoteConfigSnapshot settings;
        try
        {
            published = await catalog.GetAsync(cancellationToken).ConfigureAwait(false);
            settings = await config.GetAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
#pragma warning disable CA1031 // A store fault pauses the feature; the exception text is dropped.
        catch (Exception)
#pragma warning restore CA1031
        {
            LogFailed(logger, "catalog");
            metrics.Paused(LlmFeature.Categorise, "catalog_unavailable");
            return new CategoriseResult(CategoriseKind.Paused, admitted);
        }

        var codes = published.Codes.Count > 0 ? published.Codes : CategoriseContract.DefaultCodes;
        var live = codes.ToHashSet(StringComparer.Ordinal);
        var now = clock.GetUtcNow();
        var count = request.Merchants.Count;
        var items = new CategoriseItem?[count];

        // Steps 1 to 3: privacy, catalog, cache. None of them uses quota or calls a provider.
        var pending = new List<int>();
        for (var i = 0; i < count; i++)
        {
            var key = request.Keys[i].Reveal();
            if (!CategoriseNameFilter.IsAcceptable(request.Merchants[i].Reveal(), key))
            {
                items[i] = new CategoriseItem(request.Merchants[i], CategoriseStatus.Rejected);
            }
            else if (published.Aliases.Find(key) is { } code && live.Contains(code))
            {
                items[i] = new CategoriseItem(request.Merchants[i], CategoriseStatus.Ok, code, 100, CategoriseSource.Catalog);
            }
            else
            {
                pending.Add(i);
            }
        }

        var cached = await ReadCacheAsync(pending.Select(i => request.Keys[i].Reveal()).ToList(), now, cancellationToken).ConfigureAwait(false);
        var rest = new List<int>();
        var cacheFloor = settings.GetInt(RemoteConfigKeys.CatCacheMinConfidence);
        foreach (var i in pending)
        {
            // FU-439: a shared row serves other installs only at cat.cache_min_confidence (a raised floor retires weaker rows); the catalog was checked first.
            if (cached.TryGetValue(request.Keys[i].Reveal(), out var hit) && live.Contains(hit.Category) && hit.Confidence >= cacheFloor)
            {
                items[i] = new CategoriseItem(request.Merchants[i], CategoriseStatus.Ok, hit.Category, hit.Confidence, CategoriseSource.Cache);
            }
            else
            {
                rest.Add(i);
            }
        }

        // Step 4: trim to what is left of the counter (the lower of install and account). A retried request id was already counted: not trimmed.
        var pre = admitted.Quota!;
        var allowed = pre.IsRetry ? rest.Count : Math.Min(rest.Count, pre.Remaining);
        foreach (var i in rest.Skip(allowed))
        {
            items[i] = new CategoriseItem(request.Merchants[i], CategoriseStatus.Quota);
        }

        var send = rest.Take(allowed).ToList();
        var view = LlmQuotaView.From(pre);
        var counted = 0;
        if (send.Count > 0)
        {
            var outcome = await AskProviderAsync(gate, request, admitted, send, codes, settings, items, cancellationToken).ConfigureAwait(false);
            if (outcome.Failure is { } failure)
            {
                return new CategoriseResult(failure, admitted);
            }

            counted = outcome.Counted;
            view = outcome.Quota ?? view;
        }

        if (rest.Count > allowed)
        {
            metrics.QuotaHit(LlmFeature.Categorise);
        }

        return new CategoriseResult(CategoriseKind.Answered, admitted, new CategoriseAnswer([.. items.Select(i => i!)], counted, view));
    }

    private sealed record ProviderOutcome(CategoriseKind? Failure, int Counted = 0, LlmQuotaView? Quota = null);

    /// <summary>Steps 5 to 9 for the names that remain.</summary>
    private async Task<ProviderOutcome> AskProviderAsync(
        LlmGateRequest gate,
        CategoriseRequest request,
        LlmGateResult admitted,
        List<int> send,
        IReadOnlyList<string> codes,
        RemoteConfigSnapshot settings,
        CategoriseItem?[] items,
        CancellationToken cancellationToken)
    {
        ILlmProvider provider;
        string systemPrompt;
        try
        {
            provider = registry.Resolve(admitted.ProviderId);
            systemPrompt = prompts.GetSystemPrompt(LlmPromptIds.CatV1);
        }
        catch (LlmConfigurationException)
        {
            metrics.Paused(LlmFeature.Categorise, "provider_unknown");
            return new ProviderOutcome(CategoriseKind.Paused);
        }

        var live = codes.ToHashSet(StringComparer.Ordinal);
        var names = send.Select(i => request.Keys[i].Reveal()).ToList();
        var maxTokens = MaxOutputTokens(names.Count);
        var call = new LlmCall(
            LlmFeature.Categorise,
            LlmPromptIds.CatV1,
            new LlmSensitive<string>(CategoriseContract.UserText(request.Lang, names)),
            request.Lang,
            CategoriseContract.SchemaFor(codes),
            maxTokens);
        metrics.Prompt(LlmFeature.Categorise, EmbeddedLlmPromptCatalog.HashPrefix(systemPrompt));

        SpendReservation reservation;
        try
        {
            reservation = await spend.ReserveAsync(LlmFeature.Categorise, admitted.ProviderId, maxTokens, cancellationToken).ConfigureAwait(false);
        }
        catch (LlmServicePausedException)
        {
            return new ProviderOutcome(CategoriseKind.Paused);
        }

        LlmResult reply;
        await using (reservation.ConfigureAwait(false))
        {
            var timer = Stopwatch.StartNew();
            try
            {
                reply = await provider.CompleteAsync(call, cancellationToken).ConfigureAwait(false);
            }
            catch (LlmServicePausedException)
            {
                await reservation.SettleAsync(LlmOutcome.Upstream, LlmUsage.None, timer.Elapsed).ConfigureAwait(false);
                metrics.Paused(LlmFeature.Categorise, "no_key");
                return new ProviderOutcome(CategoriseKind.Paused);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                // The phone stopped waiting before the provider answered: nothing is counted; the disposed reservation is charged at its worst case.
                throw;
            }
#pragma warning disable CA1031 // Any other provider fault is an upstream failure; the exception (its message may quote a name) is dropped.
            catch (Exception)
#pragma warning restore CA1031
            {
                await reservation.SettleAsync(LlmOutcome.Upstream, LlmUsage.None, timer.Elapsed).ConfigureAwait(false);
                LogFailed(logger, "exception");
                return new ProviderOutcome(CategoriseKind.Upstream);
            }

            await reservation.SettleAsync(reply.Outcome, reply.Usage, timer.Elapsed).ConfigureAwait(false);
        }

        if (reply.Outcome is LlmOutcome.Timeout or LlmOutcome.Upstream)
        {
            LogFailed(logger, reply.Outcome == LlmOutcome.Timeout ? "timeout" : "upstream");
            return new ProviderOutcome(CategoriseKind.Upstream);
        }

        CategoriseVerdict?[] verdicts;
        if (reply.Outcome == LlmOutcome.Ok)
        {
            verdicts = CategoriseReplyValidator.Validate(reply.Json.Reveal(), send.Count, live);
            if (verdicts.Any(v => v is null))
            {
                metrics.ValidationFailure(LlmFeature.Categorise, "item");
            }
        }
        else
        {
            // Invalid or refused: no usable answer for any name; not counted.
            metrics.ValidationFailure(LlmFeature.Categorise, reply.Outcome == LlmOutcome.Refused ? "provider_refused" : "schema_invalid");
            verdicts = new CategoriseVerdict?[send.Count];
        }

        // Steps 6 and 7: no answer or "unknown" is unknown; below cat.min_confidence is low_confidence; the rest are candidates.
        var minConfidence = settings.GetInt(RemoteConfigKeys.CatMinConfidence);
        var candidates = new List<(int Index, CategoriseVerdict Verdict)>();
        for (var k = 0; k < send.Count; k++)
        {
            var i = send[k];
            if (verdicts[k] is not { } verdict || verdict.Code == CategoriseContract.Unknown)
            {
                items[i] = new CategoriseItem(request.Merchants[i], CategoriseStatus.Unknown);
            }
            else if (verdict.Confidence < minConfidence)
            {
                items[i] = new CategoriseItem(request.Merchants[i], CategoriseStatus.LowConfidence, null, verdict.Confidence);
            }
            else
            {
                candidates.Add((i, verdict));
            }
        }

        if (candidates.Count == 0)
        {
            return new ProviderOutcome(null);
        }

        // Step 8: commit n after a validated reply, never cancelled by a client that leaves now. A retried request id is a no-op (already counted).
        var pre = admitted.Quota!;
        var commit = await quota.CommitAsync(LlmFeature.Categorise, gate.Install, admitted.Account, gate.RetryKey, candidates.Count, CancellationToken.None).ConfigureAwait(false);
        if (commit.Kind == LlmQuotaCheckKind.Unavailable)
        {
            metrics.Paused(LlmFeature.Categorise, "quota_unavailable");
            return new ProviderOutcome(CategoriseKind.Paused);
        }

        var keep = commit.IsRetry || pre.IsRetry ? candidates.Count : Math.Min(candidates.Count, commit.Applied);
        for (var c = keep; c < candidates.Count; c++)
        {
            items[candidates[c].Index] = new CategoriseItem(request.Merchants[candidates[c].Index], CategoriseStatus.Quota);
        }

        var writes = new List<CacheWrite>();
        var cacheMin = settings.GetInt(RemoteConfigKeys.CatCacheMinConfidence);
        for (var c = 0; c < keep; c++)
        {
            var (index, verdict) = candidates[c];
            items[index] = new CategoriseItem(request.Merchants[index], CategoriseStatus.Ok, verdict.Code, verdict.Confidence, CategoriseSource.Llm);
            // FU-439: the cache is shared, so an answer is stored only when its name was the only one in the prompt (no sibling name can steer it).
            if (verdict.Confidence >= cacheMin && send.Count == 1)
            {
                writes.Add(new CacheWrite(request.Keys[index].Reveal(), verdict.Code, verdict.Confidence, admitted.ProviderId, LlmPromptIds.CatV1));
            }
        }

        await WriteCacheAsync(writes).ConfigureAwait(false);

        var view = commit.IsRetry || pre.IsRetry
            ? LlmQuotaView.From(pre)
            : new LlmQuotaView(pre.Limit, Math.Max(0, pre.Limit - commit.Remaining), commit.Remaining, pre.ResetsAt);
        return new ProviderOutcome(null, keep, view);
    }

    private async Task<IReadOnlyDictionary<string, CachedAnswer>> ReadCacheAsync(List<string> keys, DateTimeOffset now, CancellationToken cancellationToken)
    {
        if (keys.Count == 0)
        {
            return new Dictionary<string, CachedAnswer>();
        }

        try
        {
            return await cache.GetAsync(keys, now, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
#pragma warning disable CA1031 // A cache fault is a miss; the exception (a database detail can quote the row) is dropped.
        catch (Exception)
#pragma warning restore CA1031
        {
            LogFailed(logger, "cache_read");
            return new Dictionary<string, CachedAnswer>();
        }
    }

    private async Task WriteCacheAsync(List<CacheWrite> rows)
    {
        if (rows.Count == 0)
        {
            return;
        }

        try
        {
            await cache.PutAsync(rows, clock.GetUtcNow(), CancellationToken.None).ConfigureAwait(false);
        }
#pragma warning disable CA1031 // The answer is already counted and returned; a failed cache write only skips the cache.
        catch (Exception)
#pragma warning restore CA1031
        {
            LogFailed(logger, "cache_write");
        }
    }

    [LoggerMessage(EventId = 1, Level = LogLevel.Warning, Message = "categorise_failed {Kind}")]
    private static partial void LogFailed(ILogger logger, string kind);
}
