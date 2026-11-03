using Zaghlol.Application.Health;

namespace Zaghlol.Application.Tests;

public class GetHealthHandlerTests
{
    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    [Fact]
    public void HandleReturnsOkWithServerTimeFromClock()
    {
        var now = new DateTimeOffset(2026, 11, 3, 10, 30, 0, TimeSpan.Zero);
        var handler = new GetHealthHandler(new FixedTimeProvider(now));

        var result = handler.Handle();

        Assert.Equal("ok", result.Status);
        Assert.Equal(now, result.ServerTime);
    }
}
