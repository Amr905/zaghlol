namespace Zaghlol.Application.Seats;

/// <summary>Who holds the seat, seen from the caller (support: from the target).</summary>
public enum HolderRelation
{
    /// <summary>The purchase has no seat row yet.</summary>
    None,

    Self,

    Other,

    /// <summary>The seat row exists with no holder (install deleted or purged).</summary>
    Vacant,
}

/// <summary>What the decision does to the seat row.</summary>
public enum SeatAction
{
    None,

    /// <summary>First holder of a seatless purchase (not a move).</summary>
    Bind,

    /// <summary>The caller stays holder; only its key may be written.</summary>
    Refresh,

    /// <summary>A move: window restarts.</summary>
    Move,

    /// <summary>A rebind inside the cap: window unchanged, the time appended to <c>recent_rebinds</c>.</summary>
    Rebind,

    /// <summary>An over-cap rebind: window restarts, <c>recent_rebinds</c> unchanged.</summary>
    RebindOverCap,

    /// <summary>The account-attach reclaim: a move that ignores the cooldown and spends <c>attach_reclaim_used_at</c>.</summary>
    Reclaim,

    /// <summary>The support move: window restarts, key from the target's claimant entry.</summary>
    SupportMove,
}

/// <summary>The inputs of one decision, all read under the seat lock (T-184 design note §4).</summary>
/// <param name="Cooldown"><c>now &lt; next_move_at</c>.</param>
/// <param name="KeyMatch">An element at position ≥ 1 matches <c>device_key_hash</c> (restore and sign-in only).</param>
/// <param name="CapReached"><c>recent_rebinds</c>, pruned to 30 days, already holds <see cref="SeatClock.RebindCap"/> entries.</param>
/// <param name="KeyTrusted"><c>device_key_trusted</c>.</param>
/// <param name="AccountBlocks">
/// Verify / restore: the purchase is account-linked and the request has no valid account token for that account. Sign-in: the
/// purchase isn't linked to the signed-in account.
/// </param>
/// <param name="NewPayment">Verify: a new payment from this install (D-59).</param>
/// <param name="ReclaimEligible">
/// Sign-in: attached in this request, <c>attach_reclaim_used_at</c> NULL, the caller is the buying install and the holder isn't
/// linked to the account (or there is none).
/// </param>
/// <param name="SupportEligible">Support: the target is an unexpired claimant or the move-back target.</param>
public readonly record struct SeatFacts(
    SeatChannel Channel,
    HolderRelation Holder,
    bool Cooldown = false,
    bool KeyMatch = false,
    bool CapReached = false,
    bool KeyTrusted = false,
    bool AccountBlocks = false,
    bool NewPayment = false,
    bool ReclaimEligible = false,
    bool SupportEligible = false);

/// <summary>One cell of the state table.</summary>
/// <param name="Cell">The row of the design-note table (V1…P3), for tests and diagnostics.</param>
/// <param name="Claimant">Record the caller as a pending claimant on this channel.</param>
/// <param name="Cause">The <c>purchase_events.cause</c> to write, or null for none.</param>
/// <param name="Alert">Raise the <c>seat_rebind</c> alert.</param>
public sealed record SeatDecision(
    string Cell,
    SeatOutcome Outcome,
    SeatAction Action,
    SeatClaimantChannel? Claimant,
    string? Cause,
    bool RestoreSuggested = false,
    bool Alert = false);

/// <summary>The documented <c>purchase_events.cause</c> values a seat change writes (backend-schema <c>purchase_events</c>).</summary>
public static class SeatCauses
{
    public const string Bind = "seat_bind";
    public const string MoveVerify = "seat_move:verify";
    public const string MoveRestore = "seat_move:restore";
    public const string MoveSignIn = "seat_move:signin";
    public const string MoveSupport = "seat_move:support";
    public const string MoveAccountAttach = "seat_move:account_attach";
    public const string RebindRestore = "seat_rebind:restore";
    public const string RebindSignIn = "seat_rebind:signin";
    public const string RebindOverCapRestore = "seat_rebind_over_cap:restore";
    public const string RebindOverCapSignIn = "seat_rebind_over_cap:signin";
}

/// <summary>
/// The pure seat decision: the state table of the T-184 design note §4, first matching row wins. No I/O, no clock; the
/// service gathers <see cref="SeatFacts"/> under the lock and applies the result.
/// </summary>
public static class SeatRules
{
    public static SeatDecision Decide(SeatFacts f) => f.Channel switch
    {
        SeatChannel.Verify => Verify(f),
        SeatChannel.Restore => Restore(f),
        SeatChannel.SignIn => SignIn(f),
        SeatChannel.Support => Support(f),
        _ => throw new ArgumentOutOfRangeException(nameof(f), "Unknown seat channel."),
    };

    private static SeatDecision Verify(SeatFacts f)
    {
        if (f.Holder == HolderRelation.None)
        {
            return new("V1", SeatOutcome.Bound, SeatAction.Bind, null, SeatCauses.Bind);
        }

        if (f.Holder == HolderRelation.Self)
        {
            return new("V3", SeatOutcome.Unchanged, SeatAction.Refresh, null, null);
        }

        if (!f.NewPayment)
        {
            return new("V4", SeatOutcome.Unchanged, SeatAction.None, null, null);
        }

        if (f.AccountBlocks)
        {
            return new("V5", SeatOutcome.AccountRequired, SeatAction.None, SeatClaimantChannel.Verify, null);
        }

        return f.Cooldown
            ? new("V7", SeatOutcome.ClaimantAdded, SeatAction.None, SeatClaimantChannel.Verify, null)
            : new("V6", SeatOutcome.Moved, SeatAction.Move, null, SeatCauses.MoveVerify);
    }

    private static SeatDecision Restore(SeatFacts f)
    {
        if (f.AccountBlocks)
        {
            return new("R1", SeatOutcome.AccountRequired, SeatAction.None, null, null);
        }

        if (f.Holder == HolderRelation.Self)
        {
            return new("R2", SeatOutcome.Unchanged, SeatAction.Refresh, null, null);
        }

        if (f.KeyMatch && f.Holder != HolderRelation.None)
        {
            return f.CapReached
                ? new("R4", SeatOutcome.ReboundOverCap, SeatAction.RebindOverCap, null, SeatCauses.RebindOverCapRestore, Alert: true)
                : new("R3", SeatOutcome.Rebound, SeatAction.Rebind, null, SeatCauses.RebindRestore);
        }

        return f.Cooldown
            ? new("R6", SeatOutcome.Refused, SeatAction.None, SeatClaimantChannel.Restore, null)
            : new("R5", SeatOutcome.Moved, SeatAction.Move, null, SeatCauses.MoveRestore);
    }

    private static SeatDecision SignIn(SeatFacts f)
    {
        if (f.AccountBlocks)
        {
            return new("S1", SeatOutcome.AccountRequired, SeatAction.None, null, null);
        }

        if (f.Holder == HolderRelation.Self)
        {
            return new("S2", SeatOutcome.Unchanged, SeatAction.Refresh, null, null);
        }

        if (f.ReclaimEligible)
        {
            return new("S3", SeatOutcome.Moved, SeatAction.Reclaim, null, SeatCauses.MoveAccountAttach);
        }

        if (f.KeyMatch && f.Holder != HolderRelation.None)
        {
            if (!f.CapReached)
            {
                return new("S4", SeatOutcome.Rebound, SeatAction.Rebind, null, SeatCauses.RebindSignIn);
            }

            if (f.KeyTrusted)
            {
                return new("S5", SeatOutcome.ReboundOverCap, SeatAction.RebindOverCap, null, SeatCauses.RebindOverCapSignIn, Alert: true);
            }

            // Over the cap against an untrusted seat key: an ordinary move under the cooldown (D-65(a) as narrowed by D-66).
            return f.Cooldown
                ? new("S7", SeatOutcome.Refused, SeatAction.None, SeatClaimantChannel.SignIn, SeatCauses.RebindOverCapSignIn, RestoreSuggested: true, Alert: true)
                : new("S6", SeatOutcome.Moved, SeatAction.Move, null, SeatCauses.RebindOverCapSignIn, RestoreSuggested: true, Alert: true);
        }

        return f.Cooldown
            ? new("S9", SeatOutcome.Refused, SeatAction.None, SeatClaimantChannel.SignIn, null)
            : new("S8", SeatOutcome.Moved, SeatAction.Move, null, SeatCauses.MoveSignIn);
    }

    private static SeatDecision Support(SeatFacts f)
    {
        if (f.Holder == HolderRelation.None || (!f.SupportEligible && f.Holder != HolderRelation.Self))
        {
            return new("P1", SeatOutcome.NotEligible, SeatAction.None, null, null);
        }

        return f.Holder == HolderRelation.Self
            ? new("P2", SeatOutcome.Unchanged, SeatAction.None, null, null)
            : new("P3", SeatOutcome.Moved, SeatAction.SupportMove, null, SeatCauses.MoveSupport);
    }
}
