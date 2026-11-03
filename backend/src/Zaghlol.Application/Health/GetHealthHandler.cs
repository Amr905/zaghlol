namespace Zaghlol.Application.Health;

public sealed record HealthResult(string Status, DateTimeOffset ServerTime);

public sealed class GetHealthHandler(TimeProvider clock)
{
    public const string OkStatus = "ok";

    public HealthResult Handle() => new(OkStatus, clock.GetUtcNow());
}
