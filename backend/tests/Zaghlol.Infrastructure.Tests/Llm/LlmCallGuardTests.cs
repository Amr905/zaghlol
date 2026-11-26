using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Llm;

namespace Zaghlol.Infrastructure.Tests.Llm;

/// <summary>The circuit breaker thresholds of ask-llm.md §3, on a controlled clock (AC3).</summary>
public sealed class LlmCallGuardTests
{
    private static readonly DateTimeOffset Start = new(2026, 11, 26, 10, 0, 0, TimeSpan.Zero);

    private static Task<LlmResult> Ok(CancellationToken _) => Task.FromResult(new LlmResult(LlmOutcome.Ok, new(Array.Empty<byte>()), LlmUsage.None));

    private static Task<LlmResult> Fail(CancellationToken _) => Task.FromResult(LlmResult.Failed(LlmOutcome.Upstream));

    private static async Task Run(LlmCallGuard guard, Func<CancellationToken, Task<LlmResult>> attempt, int times, TestClock? clock = null, TimeSpan? step = null)
    {
        for (var i = 0; i < times; i++)
        {
            await guard.RunAsync(attempt, CancellationToken.None);
            if (step is { } s)
            {
                clock!.Advance(s);
            }
        }
    }

    [Fact]
    public async Task FiveFailuresInARowOpenTheCircuitAndOpenMeansUpstreamWithoutACall()
    {
        var clock = new TestClock(Start);
        var guard = LlmFixtures.Guard(clock);
        await Run(guard, Fail, 4);
        Assert.Equal(LlmCircuitState.Closed, guard.State);

        await Run(guard, Fail, 1);
        Assert.Equal(LlmCircuitState.Open, guard.State);

        var called = false;
        var result = await guard.RunAsync(ct => { called = true; return Ok(ct); }, CancellationToken.None);
        Assert.Equal(LlmOutcome.Upstream, result.Outcome);
        Assert.False(called);
    }

    [Fact]
    public async Task FourFailuresThenASuccessDoesNotOpen()
    {
        var guard = LlmFixtures.Guard(new TestClock(Start));
        await Run(guard, Fail, 4);
        await Run(guard, Ok, 1);
        await Run(guard, Fail, 4);

        Assert.Equal(LlmCircuitState.Closed, guard.State);
    }

    [Fact]
    public async Task HalfFailuresOverTenCallsOpenTheCircuit()
    {
        var guard = LlmFixtures.Guard(new TestClock(Start));
        for (var i = 0; i < 5; i++)
        {
            await Run(guard, Ok, 1);
            Assert.Equal(LlmCircuitState.Closed, guard.State);
            await Run(guard, Fail, 1);
        }

        // 10 calls, 5 failures (never more than one in a row).
        Assert.Equal(LlmCircuitState.Open, guard.State);
    }

    [Fact]
    public async Task FailuresSpreadOverMoreThanTheSamplingWindowDoNotOpen()
    {
        var clock = new TestClock(Start);
        var guard = LlmFixtures.Guard(clock);
        for (var i = 0; i < 10; i++)
        {
            await Run(guard, Ok, 1);
            await Run(guard, Fail, 1);
            clock.Advance(TimeSpan.FromSeconds(10));
        }

        // At most about 3 failures are inside any 30 s window, below the 10-call minimum.
        Assert.Equal(LlmCircuitState.Closed, guard.State);
    }

    [Fact]
    public async Task AfterThirtySecondsOneProbeIsLetThroughAndSuccessCloses()
    {
        var clock = new TestClock(Start);
        var guard = LlmFixtures.Guard(clock);
        await Run(guard, Fail, 5);
        clock.Advance(TimeSpan.FromSeconds(29));
        Assert.Equal(LlmCircuitState.Open, guard.State);

        clock.Advance(TimeSpan.FromSeconds(2));
        Assert.Equal(LlmCircuitState.HalfOpen, guard.State);

        // While the probe is in flight a second call is refused.
        var release = new TaskCompletionSource();
        var probe = guard.RunAsync(async ct => { await release.Task; return await Ok(ct); }, CancellationToken.None);
        var second = await guard.RunAsync(Ok, CancellationToken.None);
        Assert.Equal(LlmOutcome.Upstream, second.Outcome);

        release.SetResult();
        Assert.Equal(LlmOutcome.Ok, (await probe).Outcome);
        Assert.Equal(LlmCircuitState.Closed, guard.State);
    }

    [Fact]
    public async Task AFailedProbeReopensForAnotherThirtySeconds()
    {
        var clock = new TestClock(Start);
        var guard = LlmFixtures.Guard(clock);
        await Run(guard, Fail, 5);
        clock.Advance(TimeSpan.FromSeconds(31));

        await Run(guard, Fail, 1);

        Assert.Equal(LlmCircuitState.Open, guard.State);
        clock.Advance(TimeSpan.FromSeconds(29));
        Assert.Equal(LlmCircuitState.Open, guard.State);
        clock.Advance(TimeSpan.FromSeconds(2));
        Assert.Equal(LlmCircuitState.HalfOpen, guard.State);
    }

    [Fact]
    public async Task ModelAnswersAreNotProviderFailures()
    {
        var guard = LlmFixtures.Guard(new TestClock(Start));
        await Run(guard, _ => Task.FromResult(LlmResult.Failed(LlmOutcome.Refused)), 20);
        await Run(guard, _ => Task.FromResult(LlmResult.Failed(LlmOutcome.Invalid)), 20);

        Assert.Equal(LlmCircuitState.Closed, guard.State);
    }

    [Fact]
    public async Task ACancelledCallIsNeitherSuccessNorFailureAndFreesTheProbe()
    {
        var clock = new TestClock(Start);
        var guard = LlmFixtures.Guard(clock);
        await Run(guard, Fail, 5);
        clock.Advance(TimeSpan.FromSeconds(31));
        using var cts = new CancellationTokenSource();
        cts.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => guard.RunAsync(ct => Task.FromCanceled<LlmResult>(ct), cts.Token));

        Assert.Equal(LlmCircuitState.HalfOpen, guard.State);
        Assert.Equal(LlmOutcome.Ok, (await guard.RunAsync(Ok, CancellationToken.None)).Outcome);
    }

    [Fact]
    public async Task TheTotalBudgetEndsALongAttempt()
    {
        var options = LlmGuardOptions.Default with { AttemptTimeout = TimeSpan.FromSeconds(5), TotalTimeout = TimeSpan.FromMilliseconds(200) };
        var guard = LlmFixtures.Guard(options: options);

        var result = await guard.RunAsync(async ct => { await Task.Delay(TimeSpan.FromSeconds(3), ct); return await Ok(ct); }, CancellationToken.None);

        Assert.Equal(LlmOutcome.Timeout, result.Outcome);
    }

    // FU-406
    [Fact]
    public async Task ALateResultOfACallThatStartedBeforeTheCircuitOpenedIsNotTheProbes()
    {
        var clock = new TestClock(Start);
        var guard = LlmFixtures.Guard(clock);
        var releaseLate = new TaskCompletionSource();
        var late = guard.RunAsync(async ct => { await releaseLate.Task; return await Ok(ct); }, CancellationToken.None);
        await Run(guard, Fail, 5);
        Assert.Equal(LlmCircuitState.Open, guard.State);

        releaseLate.SetResult();
        await late;

        // The late success must not close the circuit.
        Assert.Equal(LlmCircuitState.Open, guard.State);
    }

    [Fact]
    public async Task AConnectionDroppedMidBodyIsUpstreamAndCountsAsAFailure()
    {
        var guard = LlmFixtures.Guard(new TestClock(Start));

        var result = await guard.RunAsync(_ => throw new IOException("reset while reading the body"), CancellationToken.None);

        Assert.Equal(LlmOutcome.Upstream, result.Outcome);
        for (var i = 0; i < 4; i++)
        {
            await guard.RunAsync(_ => throw new IOException("reset"), CancellationToken.None);
        }

        Assert.Equal(LlmCircuitState.Open, guard.State);
    }
}
