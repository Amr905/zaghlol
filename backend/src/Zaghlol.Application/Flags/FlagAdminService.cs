namespace Zaghlol.Application.Flags;

/// <summary>Reads and writes flag rows with the admin login (never the app login).</summary>
public interface IFlagAdminStore
{
    /// <summary>The stored row, or <c>null</c> when the flag was never set.</summary>
    Task<FlagState?> GetAsync(string key, CancellationToken cancellationToken);

    /// <summary>
    /// One transaction: upsert the flag, increment its <c>version</c>, and insert exactly one <c>audit_log</c> row naming the
    /// operator. <paramref name="rules"/> <c>null</c> keeps the stored rules; an empty rule set clears them.
    /// </summary>
    Task<FlagState> UpsertAsync(string key, bool value, FlagRules? rules, Guid operatorId, DateTimeOffset now, CancellationToken cancellationToken);
}

/// <summary>Reads every stored flag with the app login, for the sync response (T-128).</summary>
public interface IFlagReader
{
    Task<IReadOnlyList<FlagState>> ListAsync(CancellationToken cancellationToken);
}

/// <summary>Posts to the ops channel (observability doc: "every flag change posts to the ops channel").</summary>
public interface IOpsNotifier
{
    /// <summary>Best effort: never throws, and a failure never fails the change that was already committed.</summary>
    Task FlagChangedAsync(FlagState state, CancellationToken cancellationToken);
}

/// <summary>The admin use cases for <c>GET/PUT /admin/v1/flags/{key}</c>.</summary>
public sealed class FlagAdminService(IFlagAdminStore store, IOpsNotifier notifier, TimeProvider clock)
{
    /// <summary>The flag, or <c>null</c> for a key outside <see cref="FlagKeys.Known"/>. A known flag never set is the OFF default.</summary>
    public async Task<FlagState?> GetAsync(string key, CancellationToken cancellationToken)
    {
        if (!FlagKeys.IsKnown(key))
        {
            return null;
        }

        return await store.GetAsync(key, cancellationToken) ?? FlagState.Default(key);
    }

    /// <summary>Applies a validated change and returns the new state; <c>null</c> for an unknown key.</summary>
    public async Task<FlagState?> UpdateAsync(string key, bool value, FlagRules? rules, Guid operatorId, CancellationToken cancellationToken)
    {
        if (!FlagKeys.IsKnown(key))
        {
            return null;
        }

        var state = await store.UpsertAsync(key, value, rules, operatorId, clock.GetUtcNow(), cancellationToken);
        await notifier.FlagChangedAsync(state, cancellationToken);
        return state;
    }
}
