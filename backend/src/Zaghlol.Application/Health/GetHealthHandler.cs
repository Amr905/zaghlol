namespace Zaghlol.Application.Health;

/// <param name="Ready">False when the database is unreachable; the endpoint then answers 503.</param>
public sealed record HealthResult(bool Ready, DateTimeOffset ServerTime);

public sealed class GetHealthHandler(TimeProvider clock, IDatabaseReadiness database)
{
    public const string OkStatus = "ok";

    public async ValueTask<HealthResult> HandleAsync(CancellationToken cancellationToken)
    {
        var ready = await database.IsReadyAsync(cancellationToken);
        return new HealthResult(ready, clock.GetUtcNow());
    }
}
