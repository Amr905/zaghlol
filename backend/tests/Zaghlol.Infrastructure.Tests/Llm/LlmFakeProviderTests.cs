using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Llm;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Llm;

public sealed class LlmFakeProviderTests
{
    private static FakeLlmProvider Fake() =>
        FakeLlmProvider.FromFixture("fake", Path.Combine(AppContext.BaseDirectory, "Llm", "fixtures", "fake-replies.json"));

    [Fact]
    public async Task ReplaysTheFirstMatchingRecordedReplyAndCountsCalls()
    {
        var fake = Fake();

        var refused = await fake.CompleteAsync(LlmFixtures.Call("please refuse-me"), CancellationToken.None);
        var ok = await fake.CompleteAsync(LlmFixtures.Call("anything else"), CancellationToken.None);

        Assert.Equal(LlmOutcome.Refused, refused.Outcome);
        Assert.Equal(LlmOutcome.Ok, ok.Outcome);
        Assert.Equal(new LlmUsage(10, 4, 20), ok.Usage);
        Assert.Contains("PL-SUGGEST", System.Text.Encoding.UTF8.GetString(ok.Json.Reveal()), StringComparison.Ordinal);
        Assert.Equal(2, fake.Calls);
    }

    [Fact]
    public async Task NoMatchingReplyIsInvalid()
    {
        var result = await new FakeLlmProvider("empty", []).CompleteAsync(LlmFixtures.Call(), CancellationToken.None);

        Assert.Equal(LlmOutcome.Invalid, result.Outcome);
    }
}
