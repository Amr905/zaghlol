using System.Text;
using System.Text.Json;
using Zaghlol.Application.Llm;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.Llm;

/// <summary>
/// Replays recorded replies (Development and Testing only; <see cref="LlmStartupCheck"/> refuses it elsewhere). A fixture file is a
/// JSON array of <c>{ "contains": "&lt;substring of the question or null&gt;", "outcome": "Ok", "json": { ... }, "usage": { "inputTokens": 0, "cachedTokens": 0, "outputTokens": 0 } }</c>;
/// the first entry whose <c>contains</c> is null or occurs in the question wins, and none matching is <see cref="LlmOutcome.Invalid"/>.
/// <see cref="Calls"/> counts calls, so tests can prove a request never reached the provider.
/// </summary>
public sealed class FakeLlmProvider : ILlmProvider
{
    private readonly IReadOnlyList<FakeReply> replies;
    private int calls;

    public FakeLlmProvider(string id, IReadOnlyList<FakeReply> replies)
    {
        Id = id;
        this.replies = replies;
    }

    public string Id { get; }

    public int Calls => Volatile.Read(ref calls);

    public static FakeLlmProvider FromFixture(string id, string path)
    {
        var replies = JsonSerializer.Deserialize<List<FakeReply>>(File.ReadAllText(path), FixtureJson) ?? [];
        return new FakeLlmProvider(id, replies);
    }

    public Task<LlmResult> CompleteAsync(LlmCall request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        Interlocked.Increment(ref calls);
        cancellationToken.ThrowIfCancellationRequested();
        var question = request.UserText.Reveal();
        var reply = replies.FirstOrDefault(r => r.Contains is null || question.Contains(r.Contains, StringComparison.Ordinal));
        if (reply is null)
        {
            return Task.FromResult(LlmResult.Failed(LlmOutcome.Invalid));
        }

        var json = reply.Json is { } j ? new LlmSensitive<byte[]>(Encoding.UTF8.GetBytes(j.GetRawText())) : new LlmSensitive<byte[]>([]);
        return Task.FromResult(new LlmResult(reply.Outcome, json, reply.Usage ?? LlmUsage.None));
    }

    private static readonly JsonSerializerOptions FixtureJson = new(JsonSerializerDefaults.Web)
    {
        Converters = { new System.Text.Json.Serialization.JsonStringEnumConverter() },
    };
}

/// <summary>One recorded reply of the fake provider.</summary>
public sealed record FakeReply(string? Contains, LlmOutcome Outcome, JsonElement? Json, LlmUsage? Usage);
