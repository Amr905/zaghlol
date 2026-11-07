using Zaghlol.Application.Health;

namespace Zaghlol.Application.Tests;

public class GetHealthHandlerTests
{
    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class StubReadiness(bool ready) : IDatabaseReadiness
    {
        public int Calls { get; private set; }

        public ValueTask<bool> IsReadyAsync(CancellationToken cancellationToken)
        {
            Calls++;
            return ValueTask.FromResult(ready);
        }
    }

    [Fact]
    public async Task HandleReturnsReadyWithServerTimeFromClock()
    {
        var now = new DateTimeOffset(2026, 11, 3, 10, 30, 0, TimeSpan.Zero);
        var readiness = new StubReadiness(ready: true);
        var handler = new GetHealthHandler(new FixedTimeProvider(now), readiness);

        var result = await handler.HandleAsync(CancellationToken.None);

        Assert.True(result.Ready);
        Assert.Equal(now, result.ServerTime);
        Assert.Equal(1, readiness.Calls);
        Assert.Equal("ok", GetHealthHandler.OkStatus);
    }

    [Fact]
    public async Task HandleReportsNotReadyWhenTheDatabaseIsUnreachable()
    {
        var handler = new GetHealthHandler(TimeProvider.System, new StubReadiness(ready: false));

        var result = await handler.HandleAsync(CancellationToken.None);

        Assert.False(result.Ready);
    }
}
