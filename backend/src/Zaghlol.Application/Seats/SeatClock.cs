namespace Zaghlol.Application.Seats;

/// <summary>The seat time rules (R3-4, D-52, D-63, backend-api §4.3).</summary>
public static class SeatClock
{
    /// <summary>One move per rolling 30 days (D-52).</summary>
    public static readonly TimeSpan MoveWindow = TimeSpan.FromDays(30);

    /// <summary>The rolling window of the same-iPhone rebind cap (D-63).</summary>
    public static readonly TimeSpan RebindWindow = TimeSpan.FromDays(30);

    /// <summary>At most this many cooldown-free rebinds per purchase in <see cref="RebindWindow"/> (D-63).</summary>
    public const int RebindCap = 2;

    /// <summary>A pending claimant is kept this long (R3-4).</summary>
    public static readonly TimeSpan ClaimantLifetime = TimeSpan.FromDays(7);

    /// <summary>At most this many pending claimants per purchase (R3-4).</summary>
    public const int MaxClaimants = 3;

    /// <summary>
    /// The next whole UTC hour at or after <paramref name="t"/> (<paramref name="t"/> itself when it already is one). Always
    /// returned with a zero offset, so the stored value satisfies <c>ck_purchase_seats_next_move_whole_hour</c>.
    /// </summary>
    public static DateTimeOffset CeilHour(DateTimeOffset t)
    {
        var ticks = t.UtcTicks;
        var rest = ticks % TimeSpan.TicksPerHour;
        return new DateTimeOffset(rest == 0 ? ticks : ticks - rest + TimeSpan.TicksPerHour, TimeSpan.Zero);
    }

    /// <summary><c>next_move_at</c> for a move at <paramref name="now"/>: <c>CeilHour(now + 30 d)</c>.</summary>
    public static DateTimeOffset NextMoveAfter(DateTimeOffset now) => CeilHour(now + MoveWindow);

    /// <summary>The cooldown runs while <c>now &lt; next_move_at</c>; the stored value is the only one checked (R3-4).</summary>
    public static bool CooldownRunning(DateTimeOffset? nextMoveAt, DateTimeOffset now) => nextMoveAt is { } next && now < next;

    /// <summary>PostgreSQL keeps microseconds; a time written and read back must compare equal.</summary>
    public static DateTimeOffset ToDatabasePrecision(DateTimeOffset t)
    {
        var ticks = t.UtcTicks;
        return new DateTimeOffset(ticks - (ticks % 10), TimeSpan.Zero);
    }

    /// <summary>The rebind times still inside the rolling window at <paramref name="now"/>, oldest first.</summary>
    public static DateTimeOffset[] PruneRebinds(IEnumerable<DateTimeOffset> recent, DateTimeOffset now)
    {
        ArgumentNullException.ThrowIfNull(recent);
        var cutoff = now - RebindWindow;
        return [.. recent.Where(r => r > cutoff).Order()];
    }
}
