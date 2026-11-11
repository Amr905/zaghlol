using Zaghlol.Application.Seats.SeatKeys;

namespace Zaghlol.Application.Seats;

/// <summary>
/// The seat tables inside <b>the caller's</b> open transaction (T-184 design note §1–§2). The seat service never begins,
/// commits or rolls back. Lock order: <c>installs</c> (registration) → <c>purchases</c> → <c>purchase_seats</c>.
/// </summary>
public interface ISeatStore
{
    /// <summary><c>installs.seat_key_hash</c> / <c>seat_key_trusted</c>, no lock; null when the install doesn't exist.</summary>
    Task<InstallSeatKey?> ReadInstallSeatKeyAsync(Guid installId, CancellationToken cancellationToken);

    /// <summary>The same, <c>FOR UPDATE</c> on the install row.</summary>
    Task<InstallSeatKey?> LockInstallSeatKeyAsync(Guid installId, CancellationToken cancellationToken);

    /// <summary>Sets <c>seat_key_hash</c> (and <c>seat_key_trusted</c> when <paramref name="trusted"/>) only where it is NULL.</summary>
    Task<bool> RegisterInstallSeatKeyAsync(Guid installId, InstallKeyHash hash, bool trusted, CancellationToken cancellationToken);

    /// <summary>Sets <c>seat_key_trusted = true</c> only where <c>seat_key_hash</c> equals <paramref name="hash"/> (false → true only).</summary>
    Task<bool> TrustInstallSeatKeyAsync(Guid installId, InstallKeyHash hash, CancellationToken cancellationToken);

    /// <summary>
    /// <c>purchases</c> row <c>FOR UPDATE</c>, then its <c>purchase_seats</c> row <c>FOR UPDATE</c> (absent: <see cref="SeatSnapshot.SeatExists"/>
    /// false). Null when the purchase doesn't exist.
    /// </summary>
    Task<SeatSnapshot?> LockAsync(Guid purchaseId, CancellationToken cancellationToken);

    /// <summary>A Google predecessor's purchase and seat rows <c>FOR SHARE</c> (read after the successor's lock).</summary>
    Task<SeatSnapshot?> ReadPredecessorAsync(Guid purchaseId, CancellationToken cancellationToken);

    /// <summary>
    /// Copies <c>account_id</c>, <c>account_linked_by</c> (when the successor has no account) and <c>attach_reclaim_used_at</c>
    /// (when the successor's is NULL) from <paramref name="predecessorId"/> to <paramref name="successorId"/>.
    /// </summary>
    Task InheritAccountAsync(Guid successorId, Guid predecessorId, CancellationToken cancellationToken);

    /// <summary>Inserts (<paramref name="insert"/>) or updates the seat row. <paramref name="writeRebinds"/> false leaves <c>recent_rebinds</c> alone.</summary>
    Task SaveSeatAsync(SeatRow row, bool insert, bool writeRebinds, CancellationToken cancellationToken);

    /// <summary><c>attach_reclaim_used_at = at</c> where it is NULL (D-58, never cleared); false when it was already set.</summary>
    Task<bool> MarkAttachReclaimUsedAsync(Guid purchaseId, DateTimeOffset at, CancellationToken cancellationToken);

    /// <summary>Whether <c>account_installs</c> links the install to the account.</summary>
    Task<bool> IsLinkedToAccountAsync(Guid installId, Guid accountId, CancellationToken cancellationToken);

    /// <summary>Every claimant row of the purchase, expired ones included (callers filter by age).</summary>
    Task<IReadOnlyList<SeatClaimantRow>> ReadClaimantsAsync(Guid purchaseId, CancellationToken cancellationToken);

    /// <summary>Inserts the row, or refreshes the install's existing one (<c>device_key_hash = COALESCE(new, old)</c>).</summary>
    Task UpsertClaimantAsync(Guid purchaseId, SeatClaimantRow row, CancellationToken cancellationToken);

    Task DeleteClaimantAsync(Guid purchaseId, Guid installId, CancellationToken cancellationToken);

    /// <summary>One <c>purchase_events</c> row with <c>from_state = to_state = state</c>.</summary>
    Task WriteEventAsync(Guid purchaseId, Purchases.StoredPurchaseState state, string cause, DateTimeOffset at, CancellationToken cancellationToken);
}

/// <summary>The database login a seat transaction runs on.</summary>
public enum SeatLogin
{
    /// <summary><c>app_rw</c>: verify, restore, sign-in.</summary>
    App,

    /// <summary><c>ops_rw</c>: the support move (no INSERT on seats, no <c>recent_rebinds</c> grant).</summary>
    Support,
}

/// <summary>A caller-owned transaction with its seat store. Disposing without <see cref="CommitAsync"/> rolls back.</summary>
public interface ISeatTransaction : IAsyncDisposable
{
    ISeatStore Seats { get; }

    Task CommitAsync(CancellationToken cancellationToken);
}

/// <summary>Opens a READ COMMITTED transaction on <paramref name="login"/> for Application callers (T-135, T-185, T-186).</summary>
public interface ISeatTransactionFactory
{
    Task<ISeatTransaction> BeginAsync(SeatLogin login, CancellationToken cancellationToken);
}

/// <summary>Seat counters and the <c>seat_rebind</c> alert (purchase UUID only).</summary>
public interface ISeatTelemetry
{
    /// <param name="channel"><c>verify | restore | signin | support</c>.</param>
    /// <param name="kind"><c>bind | move | rebind | rebind_over_cap</c>.</param>
    void Changed(string channel, string kind);

    /// <summary>Every over-cap case (D-65(a)): the <c>seat_rebind</c> alert.</summary>
    void RebindOverCap(Guid purchaseId);
}
