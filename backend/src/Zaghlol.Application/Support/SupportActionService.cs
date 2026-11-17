using Zaghlol.Application.Audit;
using Zaghlol.Application.Purchases;
using Zaghlol.Application.Seats;
using Zaghlol.Domain;

namespace Zaghlol.Application.Support;

/// <summary>The pure rules of the support write path (backend-api 5.3, R5-5(b), R6-1): no I/O, unit-tested.</summary>
public static class SupportRules
{
    /// <summary>D-64: how long a correction freezes the purchase.</summary>
    public static readonly TimeSpan FreezeLength = TimeSpan.FromDays(30);

    /// <summary>R6-1: after an unfreeze the unfreezing operator may not make the next ordinary move on that purchase for this long.</summary>
    public static readonly TimeSpan UnfreezeLock = TimeSpan.FromHours(24);

    /// <summary>The move-back target's audit row must be younger than this (audit retention).</summary>
    public static readonly TimeSpan MoveBackMaxAge = TimeSpan.FromDays(365);

    /// <summary>A freeze runs while <c>now &lt; dispute_frozen_until</c>.</summary>
    public static bool Frozen(DateTimeOffset? until, DateTimeOffset now) => until is { } value && now < value;

    /// <summary>R6-1(2): the operator who unfroze this purchase less than 24 h ago may not make an ordinary move on it.</summary>
    public static bool UnfreezeLockActive(SupportAuditRow? lastUnfreeze, Guid caller, DateTimeOffset now) =>
        lastUnfreeze is { } row && row.OperatorId == caller && now - row.At < UnfreezeLock;

    /// <summary>
    /// R6-1(1): the caller must differ from the operator of the correction that started the freeze and from the operator of the row
    /// that correction reversed. Without a correction row the freezer can't be named, so the unfreeze fails closed (break-glass).
    /// </summary>
    public static bool UnfreezeOperatorAllowed(Guid caller, SupportAuditRow? freezeStart, SupportAuditRow? reversed) =>
        freezeStart is not null && freezeStart.OperatorId != caller && (reversed is null || reversed.OperatorId != caller);

    /// <summary>R6-1 (PO): an unfreeze is allowed only once <see cref="UnfreezeLock"/> has passed since the correction that started the freeze (the freeze row's server time).</summary>
    public static bool FreezeLockElapsed(SupportAuditRow? freezeStart, DateTimeOffset now) =>
        freezeStart is { } row && now - row.At >= UnfreezeLock;

    /// <summary>D-57(d): no account on the purchase, a target linked to an account, and a gone or silent buying install.</summary>
    public static bool AttachGate(Guid? purchaseAccount, Guid? targetAccount, bool buyingInstallSilent) =>
        purchaseAccount is null && targetAccount is not null && buyingInstallSilent;

    /// <summary>The row that a move-back correction may reverse (backend-api 5.3 *Who can receive the seat*, 3).</summary>
    public static bool IsMoveBackSource(SupportAuditRow? row, Guid target, DateTimeOffset now) =>
        row is { Action: "support_seat_move", Outcome: SupportOutcomes.Moved or SupportOutcomes.MovedAndAttached }
        && row.FromInstall == target
        && now - row.At < MoveBackMaxAge;

    /// <summary>The row a detach may reverse: a support attach of the purchase's current account.</summary>
    public static bool IsAttachSource(SupportAuditRow? row, Guid purchaseAccount) =>
        row is { Action: "support_seat_move", Outcome: SupportOutcomes.Attached or SupportOutcomes.MovedAndAttached }
        && row.AttachedAccountId == purchaseAccount;
}

/// <summary>
/// The audited support write path (T-186; backend-api 5.3): <c>seat:move</c>, <c>purchase:detach</c>, <c>purchase:unfreeze</c>. Two
/// phases, so no database lock is held while a store answers: phase 1 locks the purchase and runs every check that needs no store
/// (a refusal is audited and committed there, with no store call); phase 2 runs the live ownership check on no connection, then a new
/// transaction re-locks, re-runs every check, and either applies the effect or audits the failed check. Exactly one audit row per
/// call. The order ID is only ever handed to <see cref="ISupportOwnershipCheck"/>.
/// </summary>
public sealed class SupportActionService(
    ISupportActionStore store,
    ISupportOwnershipCheck ownership,
    SeatService seats,
    ISupportAlerts alerts,
    TimeProvider time)
{
    private const int MovesPerPurchaseAlertAbove = 2;
    private const int ActionsPerOperatorAlertAbove = 20;
    private const int OwnershipFailuresAlertAbove = 5;

    // ---------------------------------------------------------------------------------------------------------------------------
    // seat:move
    // ---------------------------------------------------------------------------------------------------------------------------

    public async Task<SupportActionResult<SupportSeatMoveOutcome>> MoveSeatAsync(SupportSeatMoveCommand command, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);
        _ = SupportTicketRef.Require(command.TicketRef);
        var correction = command.Reason == SupportReason.Correction;
        if (correction != command.CorrectsAuditId.HasValue || (correction && command.Attach))
        {
            throw new ArgumentException("A correction names the row it corrects, no other move does, and a correction never attaches.", nameof(command));
        }

        SupportPurchase gated;
        await using (var tx = await store.BeginAsync(cancellationToken).ConfigureAwait(false))
        {
            var purchase = await tx.LockPurchaseAsync(command.PurchaseId, Now(), cancellationToken).ConfigureAwait(false);
            if (purchase is null)
            {
                return await RefuseMoveAsync(tx, command, null, SupportOutcomes.Refused, SupportOwnershipOutcomes.NotRun, SupportActionStatus.NotFound, cancellationToken)
                    .ConfigureAwait(false);
            }

            if (await MoveRefusalAsync(tx, command, purchase, Now(), cancellationToken).ConfigureAwait(false) is { } refusal)
            {
                return await RefuseMoveAsync(tx, command, purchase, refusal, SupportOwnershipOutcomes.NotRun, SupportActionStatus.Conflict, cancellationToken)
                    .ConfigureAwait(false);
            }

            gated = purchase;
        }

        var check = await ownership.CheckAsync(gated, command.OrderId, cancellationToken).ConfigureAwait(false);

        await using var apply = await store.BeginAsync(cancellationToken).ConfigureAwait(false);
        var now = Now();
        var locked = await apply.LockPurchaseAsync(command.PurchaseId, now, cancellationToken).ConfigureAwait(false);
        var outcome = OutcomeText(check);
        if (locked is null)
        {
            return await RefuseMoveAsync(apply, command, null, SupportOutcomes.Refused, outcome, SupportActionStatus.NotFound, cancellationToken).ConfigureAwait(false);
        }

        if (await MoveRefusalAsync(apply, command, locked, now, cancellationToken).ConfigureAwait(false) is { } again)
        {
            return await RefuseMoveAsync(apply, command, locked, again, outcome, SupportActionStatus.Conflict, cancellationToken).ConfigureAwait(false);
        }

        if (check != OwnershipOutcome.Pass)
        {
            return await RefuseMoveAsync(apply, command, locked, FailureOutcome(check), outcome, FailureStatus(check), cancellationToken).ConfigureAwait(false);
        }

        return await ApplyMoveAsync(apply, command, locked, now, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>Checks 1 and 2 of the order: the dispute freeze (D-64), then the R6-1 lock after an unfreeze. Both apply to ordinary moves only.</summary>
    private static async Task<string?> MoveRefusalAsync(
        ISupportActionTransaction tx, SupportSeatMoveCommand command, SupportPurchase purchase, DateTimeOffset now, CancellationToken cancellationToken)
    {
        if (command.Reason == SupportReason.Correction)
        {
            return null;
        }

        if (SupportRules.Frozen(purchase.DisputeFrozenUntil, now))
        {
            return SupportOutcomes.DisputeFrozen;
        }

        var lastUnfreeze = await tx.NewestUnfreezeAsync(command.PurchaseId, cancellationToken).ConfigureAwait(false);
        if (lastUnfreeze is null)
        {
            return null;
        }

        // The audit row's `at` is the database's now(): compare the 24 h edge against the database clock, not the app clock.
        var dbNow = await tx.DatabaseNowAsync(cancellationToken).ConfigureAwait(false);
        return SupportRules.UnfreezeLockActive(lastUnfreeze, command.OperatorId, dbNow) ? SupportOutcomes.Refused : null;
    }

    private async Task<SupportActionResult<SupportSeatMoveOutcome>> ApplyMoveAsync(
        ISupportActionTransaction tx, SupportSeatMoveCommand command, SupportPurchase purchase, DateTimeOffset now, CancellationToken cancellationToken)
    {
        var target = command.ToInstall.Value;
        var seat = purchase.Seat;
        var correction = command.Reason == SupportReason.Correction;
        var targetHolds = seat.Holder == target;
        var moveBack = false;

        if (correction)
        {
            // FU-112 184-2: the move back is derived here from the audit row, never from the request.
            var source = await tx.ReadAuditAsync(command.PurchaseId, command.CorrectsAuditId!.Value, cancellationToken).ConfigureAwait(false);
            if (!SupportRules.IsMoveBackSource(source, target, now) || !await tx.InstallLiveAsync(target, cancellationToken).ConfigureAwait(false))
            {
                return await RefuseMoveAsync(tx, command, purchase, SupportOutcomes.Refused, SupportOwnershipOutcomes.Pass, SupportActionStatus.Conflict, cancellationToken)
                    .ConfigureAwait(false);
            }

            moveBack = true;
        }

        if (!targetHolds && seat.AccountId is { } account
            && !await tx.Seats.IsLinkedToAccountAsync(target, account, cancellationToken).ConfigureAwait(false))
        {
            return await RefuseMoveAsync(tx, command, purchase, SupportOutcomes.Refused, SupportOwnershipOutcomes.Pass, SupportActionStatus.Conflict, cancellationToken)
                .ConfigureAwait(false);
        }

        Guid? attachAccount = null;
        if (command.Attach)
        {
            var targetAccount = await tx.AccountOfInstallAsync(target, cancellationToken).ConfigureAwait(false);
            if (!SupportRules.AttachGate(seat.AccountId, targetAccount, purchase.BuyingInstallSilent))
            {
                return await RefuseMoveAsync(tx, command, purchase, SupportOutcomes.Refused, SupportOwnershipOutcomes.Pass, SupportActionStatus.Conflict, cancellationToken)
                    .ConfigureAwait(false);
            }

            attachAccount = targetAccount;
        }

        var moved = false;
        var next = SeatClock.CooldownRunning(seat.NextMoveAt, now) ? seat.NextMoveAt : null;
        if (!targetHolds)
        {
            var result = await seats.SupportMoveAsync(tx.Seats, new SupportSeatMoveRequest(command.PurchaseId, command.ToInstall, moveBack), cancellationToken)
                .ConfigureAwait(false);
            if (result.Outcome != SeatOutcome.Moved)
            {
                // Not a claimant and not the move-back target: the primitive wrote nothing.
                return await RefuseMoveAsync(tx, command, purchase, SupportOutcomes.Refused, SupportOwnershipOutcomes.Pass, SupportActionStatus.Conflict, cancellationToken)
                    .ConfigureAwait(false);
            }

            moved = true;
            next = result.NextMoveAt;
        }

        if (attachAccount is { } link)
        {
            await tx.LinkAccountBySupportAsync(command.PurchaseId, link, cancellationToken).ConfigureAwait(false);
        }

        if (correction && moved)
        {
            await tx.StartDisputeFreezeAsync(command.PurchaseId, SupportRules.FreezeLength, cancellationToken).ConfigureAwait(false);
        }

        var outcome = (moved, attachAccount is not null) switch
        {
            (true, true) => SupportOutcomes.MovedAndAttached,
            (true, false) => SupportOutcomes.Moved,
            (false, true) => SupportOutcomes.Attached,
            _ => SupportOutcomes.Noop,
        };
        var entry = new SupportSeatMoveAudit(
            command.PurchaseId, seat.Holder, target, SupportReasons.Wire(command.Reason), command.TicketRef, attachAccount, command.CorrectsAuditId,
            SupportOwnershipOutcomes.Pass, outcome);
        var auditId = await CommitAuditAsync(tx, command.OperatorId, command.PurchaseId, entry, moved, cancellationToken).ConfigureAwait(false);
        return new(SupportActionStatus.Ok, new SupportSeatMoveOutcome(command.PurchaseId, moved, attachAccount is not null, next, auditId));
    }

    private async Task<SupportActionResult<SupportSeatMoveOutcome>> RefuseMoveAsync(
        ISupportActionTransaction tx,
        SupportSeatMoveCommand command,
        SupportPurchase? purchase,
        string outcome,
        string ownershipOutcome,
        SupportActionStatus status,
        CancellationToken cancellationToken)
    {
        var entry = new SupportSeatMoveAudit(
            command.PurchaseId, purchase?.Seat.Holder, command.ToInstall.Value, SupportReasons.Wire(command.Reason), command.TicketRef, null,
            command.CorrectsAuditId, ownershipOutcome, outcome);
        await CommitAuditAsync(tx, command.OperatorId, command.PurchaseId, entry, false, cancellationToken).ConfigureAwait(false);
        return new(status);
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // purchase:detach
    // ---------------------------------------------------------------------------------------------------------------------------

    public async Task<SupportActionResult<SupportDetachOutcome>> DetachAsync(SupportDetachCommand command, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);
        _ = SupportTicketRef.Require(command.TicketRef);

        SupportPurchase gated;
        await using (var tx = await store.BeginAsync(cancellationToken).ConfigureAwait(false))
        {
            var purchase = await tx.LockPurchaseAsync(command.PurchaseId, Now(), cancellationToken).ConfigureAwait(false);
            if (purchase is null)
            {
                return await RefuseDetachAsync(tx, command, SupportOwnershipOutcomes.NotRun, SupportOutcomes.Refused, SupportActionStatus.NotFound, cancellationToken)
                    .ConfigureAwait(false);
            }

            if (await DetachRefusedAsync(tx, command, purchase, cancellationToken).ConfigureAwait(false))
            {
                // Certain to be refused: no store call.
                return await RefuseDetachAsync(tx, command, SupportOwnershipOutcomes.NotRun, SupportOutcomes.Refused, SupportActionStatus.Conflict, cancellationToken)
                    .ConfigureAwait(false);
            }

            gated = purchase;
        }

        var check = await ownership.CheckAsync(gated, command.OrderId, cancellationToken).ConfigureAwait(false);

        await using var apply = await store.BeginAsync(cancellationToken).ConfigureAwait(false);
        var now = Now();
        var locked = await apply.LockPurchaseAsync(command.PurchaseId, now, cancellationToken).ConfigureAwait(false);
        var outcome = OutcomeText(check);
        if (locked is null)
        {
            return await RefuseDetachAsync(apply, command, outcome, SupportOutcomes.Refused, SupportActionStatus.NotFound, cancellationToken).ConfigureAwait(false);
        }

        if (check != OwnershipOutcome.Pass)
        {
            return await RefuseDetachAsync(apply, command, outcome, FailureOutcome(check), FailureStatus(check), cancellationToken).ConfigureAwait(false);
        }

        if (locked.Seat.AccountId is not { } account)
        {
            // Idempotent by nature: an unlinked purchase stays unlinked.
            var noop = new SupportDetachAudit(command.PurchaseId, null, command.TicketRef, command.CorrectsAuditId, outcome, SupportOutcomes.Noop);
            var noopId = await CommitAuditAsync(apply, command.OperatorId, command.PurchaseId, noop, false, cancellationToken).ConfigureAwait(false);
            return new(SupportActionStatus.Ok, new SupportDetachOutcome(command.PurchaseId, false, noopId));
        }

        // A link the owner made from the buying phone (or by signing in) can't be detached by support (D-57(e)).
        if (await DetachRefusedAsync(apply, command, locked, cancellationToken).ConfigureAwait(false))
        {
            return await RefuseDetachAsync(apply, command, outcome, SupportOutcomes.Refused, SupportActionStatus.Conflict, cancellationToken).ConfigureAwait(false);
        }

        await apply.UnlinkAccountAsync(command.PurchaseId, cancellationToken).ConfigureAwait(false);
        await apply.StartDisputeFreezeAsync(command.PurchaseId, SupportRules.FreezeLength, cancellationToken).ConfigureAwait(false);
        var entry = new SupportDetachAudit(command.PurchaseId, account, command.TicketRef, command.CorrectsAuditId, outcome, SupportOutcomes.Detached);
        var auditId = await CommitAuditAsync(apply, command.OperatorId, command.PurchaseId, entry, false, cancellationToken).ConfigureAwait(false);
        return new(SupportActionStatus.Ok, new SupportDetachOutcome(command.PurchaseId, true, auditId));
    }

    /// <summary>The link and source checks of a detach (no store needed). An unlinked purchase is a no-op, not a refusal.</summary>
    private static async Task<bool> DetachRefusedAsync(
        ISupportActionTransaction tx, SupportDetachCommand command, SupportPurchase purchase, CancellationToken cancellationToken)
    {
        if (purchase.Seat.AccountId is not { } account)
        {
            return false;
        }

        var source = await tx.ReadAuditAsync(command.PurchaseId, command.CorrectsAuditId, cancellationToken).ConfigureAwait(false);
        return !string.Equals(purchase.AccountLinkedBy, "support", StringComparison.Ordinal) || !SupportRules.IsAttachSource(source, account);
    }

    private async Task<SupportActionResult<SupportDetachOutcome>> RefuseDetachAsync(
        ISupportActionTransaction tx,
        SupportDetachCommand command,
        string ownershipOutcome,
        string outcome,
        SupportActionStatus status,
        CancellationToken cancellationToken)
    {
        var entry = new SupportDetachAudit(command.PurchaseId, null, command.TicketRef, command.CorrectsAuditId, ownershipOutcome, outcome);
        await CommitAuditAsync(tx, command.OperatorId, command.PurchaseId, entry, false, cancellationToken).ConfigureAwait(false);
        return new(status);
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // purchase:unfreeze
    // ---------------------------------------------------------------------------------------------------------------------------

    public async Task<SupportActionResult<SupportUnfreezeOutcome>> UnfreezeAsync(SupportUnfreezeCommand command, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(command);
        _ = SupportTicketRef.Require(command.TicketRef);

        SupportPurchase gated;
        await using (var tx = await store.BeginAsync(cancellationToken).ConfigureAwait(false))
        {
            var now = Now();
            var purchase = await tx.LockPurchaseAsync(command.PurchaseId, now, cancellationToken).ConfigureAwait(false);
            if (purchase is null)
            {
                return await FinishUnfreezeAsync(tx, command, null, null, SupportOwnershipOutcomes.NotRun, SupportOutcomes.Refused, SupportActionStatus.NotFound, cancellationToken)
                    .ConfigureAwait(false);
            }

            var step = await UnfreezeGateAsync(tx, command, purchase, now, cancellationToken).ConfigureAwait(false);
            if (step.Outcome is { } done)
            {
                return await FinishUnfreezeAsync(
                    tx, command, step.FreezeId, purchase.DisputeFrozenUntil, SupportOwnershipOutcomes.NotRun, done,
                    done == SupportOutcomes.Noop ? SupportActionStatus.Ok : SupportActionStatus.Conflict, cancellationToken).ConfigureAwait(false);
            }

            gated = purchase;
        }

        var check = await ownership.CheckAsync(gated, command.OrderId, cancellationToken).ConfigureAwait(false);

        await using var apply = await store.BeginAsync(cancellationToken).ConfigureAwait(false);
        var at = Now();
        var locked = await apply.LockPurchaseAsync(command.PurchaseId, at, cancellationToken).ConfigureAwait(false);
        var outcome = OutcomeText(check);
        if (locked is null)
        {
            return await FinishUnfreezeAsync(apply, command, null, null, outcome, SupportOutcomes.Refused, SupportActionStatus.NotFound, cancellationToken).ConfigureAwait(false);
        }

        var gate = await UnfreezeGateAsync(apply, command, locked, at, cancellationToken).ConfigureAwait(false);
        if (gate.Outcome is { } stopped)
        {
            return await FinishUnfreezeAsync(
                apply, command, gate.FreezeId, locked.DisputeFrozenUntil, outcome, stopped,
                stopped == SupportOutcomes.Noop ? SupportActionStatus.Ok : SupportActionStatus.Conflict, cancellationToken).ConfigureAwait(false);
        }

        if (check != OwnershipOutcome.Pass)
        {
            return await FinishUnfreezeAsync(
                apply, command, gate.FreezeId, locked.DisputeFrozenUntil, outcome, FailureOutcome(check), FailureStatus(check), cancellationToken).ConfigureAwait(false);
        }

        // Moves nothing: the seat, the account, next_move_at, recent_rebinds and the claimants are not touched.
        await apply.SetDisputeFreezeAsync(command.PurchaseId, null, cancellationToken).ConfigureAwait(false);
        return await FinishUnfreezeAsync(
            apply, command, gate.FreezeId, locked.DisputeFrozenUntil, outcome, SupportOutcomes.Unfrozen, SupportActionStatus.Ok, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>R5-5(b) checks 1 and 2 with R6-1: a final outcome (<c>noop</c> or <c>refused</c>), or none when the unfreeze may go on to the ownership check.</summary>
    private static async Task<(string? Outcome, long? FreezeId)> UnfreezeGateAsync(
        ISupportActionTransaction tx, SupportUnfreezeCommand command, SupportPurchase purchase, DateTimeOffset now, CancellationToken cancellationToken)
    {
        if (!SupportRules.Frozen(purchase.DisputeFrozenUntil, now))
        {
            return (SupportOutcomes.Noop, null);
        }

        var freeze = await tx.NewestFreezeStartAsync(command.PurchaseId, cancellationToken).ConfigureAwait(false);
        SupportAuditRow? reversed = null;
        if (freeze?.CorrectsAuditId is { } corrected)
        {
            reversed = await tx.ReadAuditAsync(command.PurchaseId, corrected, cancellationToken).ConfigureAwait(false);
        }

        var dbNow = await tx.DatabaseNowAsync(cancellationToken).ConfigureAwait(false);
        return SupportRules.UnfreezeOperatorAllowed(command.OperatorId, freeze, reversed) && SupportRules.FreezeLockElapsed(freeze, dbNow)
            ? (null, freeze!.Id)
            : (SupportOutcomes.Refused, freeze?.Id);
    }

    private async Task<SupportActionResult<SupportUnfreezeOutcome>> FinishUnfreezeAsync(
        ISupportActionTransaction tx,
        SupportUnfreezeCommand command,
        long? freezeAuditId,
        DateTimeOffset? frozenUntil,
        string ownershipOutcome,
        string outcome,
        SupportActionStatus status,
        CancellationToken cancellationToken)
    {
        var entry = new SupportUnfreezeAudit(
            command.PurchaseId, command.TicketRef, freezeAuditId, outcome == SupportOutcomes.Noop ? null : frozenUntil, ownershipOutcome, outcome);
        var auditId = await CommitAuditAsync(tx, command.OperatorId, command.PurchaseId, entry, false, cancellationToken).ConfigureAwait(false);
        return status == SupportActionStatus.Ok
            ? new(status, new SupportUnfreezeOutcome(command.PurchaseId, outcome == SupportOutcomes.Unfrozen, auditId))
            : new(status);
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // shared
    // ---------------------------------------------------------------------------------------------------------------------------

    /// <summary>Writes the call's one audit row, reads the alert counters, commits, and only then raises the alerts.</summary>
    private async Task<long> CommitAuditAsync(
        ISupportActionTransaction tx, Guid operatorId, Guid purchaseId, AuditEntry entry, bool moved, CancellationToken cancellationToken)
    {
        var id = await tx.WriteAuditAsync(operatorId, entry, cancellationToken).ConfigureAwait(false);
        var counts = await tx.CountsAsync(operatorId, purchaseId, cancellationToken).ConfigureAwait(false);
        await tx.CommitAsync(cancellationToken).ConfigureAwait(false);

        if (entry is SupportSeatMoveAudit { Outcome: SupportOutcomes.DisputeFrozen })
        {
            alerts.DisputeFrozen(purchaseId);
        }

        if (entry is SupportUnfreezeAudit)
        {
            alerts.Unfreeze(purchaseId);
        }

        if (moved && counts.SuccessfulMovesLast90Days > MovesPerPurchaseAlertAbove)
        {
            alerts.MovesPerPurchase(purchaseId);
        }

        if (counts.ActionsLastDay > ActionsPerOperatorAlertAbove)
        {
            alerts.ActionsPerOperator(operatorId);
        }

        if (counts.OwnershipFailuresLastDay > OwnershipFailuresAlertAbove)
        {
            alerts.OwnershipFailuresPerOperator(operatorId);
        }

        return id;
    }

    private static string OutcomeText(OwnershipOutcome outcome) => outcome switch
    {
        OwnershipOutcome.Pass => SupportOwnershipOutcomes.Pass,
        OwnershipOutcome.Fail => SupportOwnershipOutcomes.Fail,
        _ => SupportOwnershipOutcomes.Unavailable,
    };

    private static string FailureOutcome(OwnershipOutcome outcome) =>
        outcome == OwnershipOutcome.Fail ? SupportOutcomes.OwnershipFailed : SupportOutcomes.UpstreamUnavailable;

    private static SupportActionStatus FailureStatus(OwnershipOutcome outcome) =>
        outcome == OwnershipOutcome.Fail ? SupportActionStatus.OwnershipFailed : SupportActionStatus.Unavailable;

    private DateTimeOffset Now() => SeatClock.ToDatabasePrecision(time.GetUtcNow());
}
