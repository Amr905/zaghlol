namespace Zaghlol.Application.Health;

/// <summary>Whether the API's database (as its own least-privilege role) answers right now (FU-003).</summary>
public interface IDatabaseReadiness
{
    /// <summary>
    /// True when a trivial query succeeds within the probe timeout. Implementations cache the answer briefly so the
    /// unauthenticated health endpoint can't be used to load the database.
    /// </summary>
    ValueTask<bool> IsReadyAsync(CancellationToken cancellationToken);
}
