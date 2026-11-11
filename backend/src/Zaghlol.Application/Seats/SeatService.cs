using System.Security.Cryptography;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;

namespace Zaghlol.Application.Seats;

/// <summary>
/// The one place that decides who holds a purchase's single Gold seat (T-184; backend-api §4.3, §4.6, §5.3). Every method runs in
/// the caller's transaction (<see cref="ISeatStore"/>), under <c>SELECT … FOR UPDATE</c> on the purchase and its seat row, decides
/// with <see cref="SeatRules"/> and writes the seat, the claimants and at most one <c>purchase_events</c> row. KMS failures
/// propagate (the caller's transaction rolls back); nothing is decided on a failed hash.
/// </summary>
public sealed class SeatService(SeatKeyHasher hasher, ISeatTelemetry telemetry, TimeProvider time)
{
    /// <summary>
    /// Element 0 against <c>installs.seat_key_hash</c> (R4-1(1)): registers it when the install has none (set once), and marks it
    /// trusted only with <paramref name="attested"/> (R5-2), which must name this install, cover exactly these public keys and
    /// come with a restore proof. Verify and sign-in pass null and register untrusted. A mismatch writes nothing.
    /// </summary>
    public async Task<SeatKeyRegistration> RegisterElementZeroAsync(
        ISeatStore store, VerifiedSeatKeys keys, AppAttestVerified? attested, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(store);
        ArgumentNullException.ThrowIfNull(keys);
        var trust = attested is not null;
        if (attested is not null
            && (keys.Op != SeatOp.Restore || attested.InstallId != keys.InstallId
                || !CryptographicOperations.FixedTimeEquals(attested.SeatKeysDigest, keys.Digest())))
        {
            throw new ArgumentException("The App Attest capability doesn't cover these seat keys.", nameof(attested));
        }

        var install = keys.InstallId.Value;

        // Hash before any lock (KMS latency must not hold row locks), then decide against the locked value: a concurrent request
        // of the same install may have registered in between.
        var seen = await store.ReadInstallSeatKeyAsync(install, cancellationToken).ConfigureAwait(false)
            ?? throw new InvalidOperationException("The install does not exist.");
        var check = await hasher.CheckElementZeroAsync(keys.InstallId, seen.Registered, keys, cancellationToken).ConfigureAwait(false);
        var locked = await store.LockInstallSeatKeyAsync(install, cancellationToken).ConfigureAwait(false)
            ?? throw new InvalidOperationException("The install does not exist.");

        if (locked.Registered is null)
        {
            if (!await store.RegisterInstallSeatKeyAsync(install, check.Computed, trust, cancellationToken).ConfigureAwait(false))
            {
                throw new InvalidOperationException("The seat key registration lost its row lock.");
            }

            return new(SeatKeyRegistrationStatus.Registered, new RegisteredSeatKey(keys, locked.Trusted || trust));
        }

        if (!check.Computed.Matches(locked.Registered))
        {
            return new(SeatKeyRegistrationStatus.Mismatch, null);
        }

        var trusted = locked.Trusted;
        if (trust && !trusted)
        {
            trusted = await store.TrustInstallSeatKeyAsync(install, check.Computed, cancellationToken).ConfigureAwait(false);
        }

        return new(SeatKeyRegistrationStatus.AlreadyRegistered, new RegisteredSeatKey(keys, trusted));
    }

    /// <summary>Verify (backend-api §4.3 <i>Seat at verify</i>): bind, refresh, or the plan-change rules. Never refuses.</summary>
    public async Task<SeatResult> VerifyAsync(ISeatStore store, VerifySeatRequest request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(store);
        ArgumentNullException.ThrowIfNull(request);
        CheckKey(request.Key, request.Caller, SeatOp.Verify);
        var holderHash = await HolderHashAsync(request.PurchaseId, request.Key, cancellationToken).ConfigureAwait(false);
        var now = Now();

        var snapshot = await LockAsync(store, request.PurchaseId, cancellationToken).ConfigureAwait(false);
        if (!snapshot.SeatExists && request.PredecessorPurchaseId is { } predecessorId && predecessorId != request.PurchaseId)
        {
            var predecessor = await store.ReadPredecessorAsync(predecessorId, cancellationToken).ConfigureAwait(false);
            if (predecessor is { SeatExists: true })
            {
                // D-59/R3-7: a Google successor inherits the predecessor's seat (holder, window, key and rebind budget), account
                // and reclaim marker. Not a move, so no event.
                await store.InheritAccountAsync(request.PurchaseId, predecessorId, cancellationToken).ConfigureAwait(false);
                await store.SaveSeatAsync(
                    new SeatRow(
                        request.PurchaseId,
                        predecessor.Holder,
                        predecessor.Proof,
                        predecessor.BoundAt,
                        predecessor.LastMovedAt,
                        predecessor.NextMoveAt,
                        predecessor.DeviceKeyHash,
                        predecessor.DeviceKeyTrusted,
                        SeatClock.PruneRebinds(predecessor.RecentRebinds, now)),
                    insert: true,
                    writeRebinds: true,
                    cancellationToken).ConfigureAwait(false);
                snapshot = await LockAsync(store, request.PurchaseId, cancellationToken).ConfigureAwait(false);
            }
        }

        var facts = new SeatFacts(
            SeatChannel.Verify,
            Relation(snapshot, request.Caller),
            Cooldown: SeatClock.CooldownRunning(snapshot.NextMoveAt, now),
            AccountBlocks: snapshot.AccountId is { } account && request.PresentedAccountId != account,
            NewPayment: request.IsNewPayment);
        return await ApplyAsync(
            store, snapshot, SeatRules.Decide(facts), request.Caller, request.Key, holderHash, SeatProofKind.Binding, now, cancellationToken)
            .ConfigureAwait(false);
    }

    /// <summary>Restore step 4–5 for one item (backend-api §4.3), after attestation and store verification passed.</summary>
    public async Task<SeatResult> RestoreAsync(ISeatStore store, RestoreSeatRequest request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(store);
        ArgumentNullException.ThrowIfNull(request);
        CheckKey(request.Key, request.Caller, SeatOp.Restore);
        var holderHash = await HolderHashAsync(request.PurchaseId, request.Key, cancellationToken).ConfigureAwait(false);
        var now = Now();

        var snapshot = await LockAsync(store, request.PurchaseId, cancellationToken).ConfigureAwait(false);
        var relation = Relation(snapshot, request.Caller);
        var accountBlocks = snapshot.AccountId is { } account && request.PresentedAccountId != account;
        var match = !accountBlocks && await MatchAsync(snapshot, relation, request.Key, cancellationToken).ConfigureAwait(false);
        var facts = new SeatFacts(
            SeatChannel.Restore,
            relation,
            Cooldown: SeatClock.CooldownRunning(snapshot.NextMoveAt, now),
            KeyMatch: match,
            CapReached: CapReached(snapshot, now),
            KeyTrusted: snapshot.DeviceKeyTrusted,
            AccountBlocks: accountBlocks);
        var proof = request.Proof == RestoreProof.Basic ? SeatProofKind.Basic : SeatProofKind.Attested;
        return await ApplyAsync(store, snapshot, SeatRules.Decide(facts), request.Caller, request.Key, holderHash, proof, now, cancellationToken)
            .ConfigureAwait(false);
    }

    /// <summary>Sign-in steps 4–5 for one purchase (backend-api §4.6): the account-attach reclaim, rebinds and moves. Never 409.</summary>
    public async Task<SeatResult> SignInAsync(ISeatStore store, SignInSeatRequest request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(store);
        ArgumentNullException.ThrowIfNull(request);
        CheckKey(request.Key, request.Caller, SeatOp.SignIn);
        var holderHash = await HolderHashAsync(request.PurchaseId, request.Key, cancellationToken).ConfigureAwait(false);
        var now = Now();

        var snapshot = await LockAsync(store, request.PurchaseId, cancellationToken).ConfigureAwait(false);
        var relation = Relation(snapshot, request.Caller);
        var accountBlocks = snapshot.AccountId != request.AccountId;
        var reclaim = false;
        if (!accountBlocks && relation != HolderRelation.Self && request.AttachedNow && snapshot.AttachReclaimUsedAt is null
            && snapshot.BuyingInstall == request.Caller.Value)
        {
            reclaim = snapshot.Holder is not { } holder
                || !await store.IsLinkedToAccountAsync(holder, request.AccountId, cancellationToken).ConfigureAwait(false);
        }

        var match = !accountBlocks && !reclaim && await MatchAsync(snapshot, relation, request.Key, cancellationToken).ConfigureAwait(false);
        var facts = new SeatFacts(
            SeatChannel.SignIn,
            relation,
            Cooldown: SeatClock.CooldownRunning(snapshot.NextMoveAt, now),
            KeyMatch: match,
            CapReached: CapReached(snapshot, now),
            KeyTrusted: snapshot.DeviceKeyTrusted,
            AccountBlocks: accountBlocks,
            ReclaimEligible: reclaim);
        return await ApplyAsync(
            store, snapshot, SeatRules.Decide(facts), request.Caller, request.Key, holderHash, SeatProofKind.Account, now, cancellationToken)
            .ConfigureAwait(false);
    }

    /// <summary>
    /// The support-move primitive (backend-api §5.3, D-56, R5-4) for T-186, on the Admin login. T-186 runs its own checks first
    /// (role, dispute freeze, ownership, account rule, the move-back audit row); this enforces target eligibility, moves past the
    /// cooldown, restarts the window, removes the target's claimant entry and sets the seat key from the target only.
    /// </summary>
    public async Task<SeatResult> SupportMoveAsync(ISeatStore store, SupportSeatMoveRequest request, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(store);
        ArgumentNullException.ThrowIfNull(request);
        var now = Now();

        var snapshot = await LockAsync(store, request.PurchaseId, cancellationToken).ConfigureAwait(false);
        var target = request.Target.Value;
        var claimants = snapshot.SeatExists
            ? await store.ReadClaimantsAsync(request.PurchaseId, cancellationToken).ConfigureAwait(false)
            : [];
        var entry = claimants.FirstOrDefault(c => c.InstallId == target && Live(c, now));
        var facts = new SeatFacts(SeatChannel.Support, Relation(snapshot, request.Target), SupportEligible: entry is not null || request.MoveBack);
        var decision = SeatRules.Decide(facts);
        if (decision.Action != SeatAction.SupportMove)
        {
            return Result(decision, snapshot, snapshot.Holder == target, previousHolder: null, movedBy: null, snapshot.NextMoveAt, now);
        }

        // R5-4: the key comes only from the target's claimant entry (never on a move back), and the trust flag only from the target
        // install now; nothing is kept from the previous holder.
        var hash = request.MoveBack ? null : entry?.DeviceKeyHash;
        var trusted = false;
        if (hash is not null)
        {
            var install = await store.ReadInstallSeatKeyAsync(target, cancellationToken).ConfigureAwait(false)
                ?? throw new InvalidOperationException("The target install does not exist.");
            trusted = install.Trusted;
        }

        var next = SeatClock.NextMoveAfter(now);
        await store.SaveSeatAsync(
            new SeatRow(request.PurchaseId, target, SeatProofKind.Support, now, now, next, hash, trusted, snapshot.RecentRebinds),
            insert: false,
            writeRebinds: false,
            cancellationToken).ConfigureAwait(false);
        if (claimants.Any(c => c.InstallId == target))
        {
            await store.DeleteClaimantAsync(request.PurchaseId, target, cancellationToken).ConfigureAwait(false);
        }

        await store.WriteEventAsync(request.PurchaseId, snapshot.PurchaseState, SeatCauses.MoveSupport, now, cancellationToken).ConfigureAwait(false);
        telemetry.Changed("support", "move");
        return Result(decision, snapshot, callerHolds: true, previousHolder: snapshot.Holder, movedBy: SeatMovedBy.Support, next, now);
    }

    private async Task<SeatResult> ApplyAsync(
        ISeatStore store,
        SeatSnapshot snapshot,
        SeatDecision decision,
        InstallId caller,
        RegisteredSeatKey? key,
        SeatKeyHash? holderHash,
        SeatProofKind proof,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var purchaseId = snapshot.PurchaseId;
        var rebinds = SeatClock.PruneRebinds(snapshot.RecentRebinds, now);
        var keyTrusted = holderHash is not null && key!.Trusted;
        var takes = decision.Action is SeatAction.Bind or SeatAction.Move or SeatAction.Rebind or SeatAction.RebindOverCap or SeatAction.Reclaim;
        var next = snapshot.NextMoveAt;
        var channel = Wire(decision);

        switch (decision.Action)
        {
            case SeatAction.None:
                break;

            case SeatAction.Refresh:
                // Stays holder: write its registered key when this request carried one; otherwise keep what is stored.
                if (holderHash is not null)
                {
                    await store.SaveSeatAsync(
                        new SeatRow(purchaseId, snapshot.Holder, snapshot.Proof, snapshot.BoundAt, snapshot.LastMovedAt, next, holderHash, keyTrusted, rebinds),
                        insert: false,
                        writeRebinds: true,
                        cancellationToken).ConfigureAwait(false);
                }

                break;

            case SeatAction.Bind:
                await store.SaveSeatAsync(
                    new SeatRow(purchaseId, caller.Value, SeatProofKind.Binding, now, null, null, holderHash, keyTrusted, rebinds),
                    insert: !snapshot.SeatExists,
                    writeRebinds: true,
                    cancellationToken).ConfigureAwait(false);
                break;

            case SeatAction.Move:
            case SeatAction.Reclaim:
                next = SeatClock.NextMoveAfter(now);
                if (decision.Action == SeatAction.Reclaim
                    && !await store.MarkAttachReclaimUsedAsync(purchaseId, now, cancellationToken).ConfigureAwait(false))
                {
                    throw new InvalidOperationException("The account-attach reclaim was already used.");
                }

                await store.SaveSeatAsync(
                    new SeatRow(purchaseId, caller.Value, proof, now, now, next, holderHash, keyTrusted, rebinds),
                    insert: !snapshot.SeatExists,
                    writeRebinds: true,
                    cancellationToken).ConfigureAwait(false);
                break;

            case SeatAction.Rebind:
            case SeatAction.RebindOverCap:
                // Condition 1 holds by type (RegisteredSeatKey); the key left on the seat is the caller's own (R4-1(1)).
                var rebindProof = proof == SeatProofKind.Basic ? SeatProofKind.Basic : SeatProofKind.Device;
                var last = snapshot.LastMovedAt;
                if (decision.Action == SeatAction.RebindOverCap)
                {
                    last = now;
                    next = SeatClock.NextMoveAfter(now);
                }
                else
                {
                    rebinds = [.. rebinds, now];
                }

                await store.SaveSeatAsync(
                    new SeatRow(purchaseId, caller.Value, rebindProof, now, last, next, holderHash, keyTrusted, rebinds),
                    insert: false,
                    writeRebinds: true,
                    cancellationToken).ConfigureAwait(false);
                break;

            default:
                throw new InvalidOperationException("Unexpected seat action.");
        }

        if (decision.Claimant is { } claimantChannel)
        {
            await AddClaimantAsync(store, purchaseId, new SeatClaimantRow(caller.Value, now, claimantChannel, holderHash), now, cancellationToken)
                .ConfigureAwait(false);
        }
        else if (takes)
        {
            // The new holder is no longer waiting for the seat.
            await store.DeleteClaimantAsync(purchaseId, caller.Value, cancellationToken).ConfigureAwait(false);
        }

        if (decision.Cause is { } cause)
        {
            await store.WriteEventAsync(purchaseId, snapshot.PurchaseState, cause, now, cancellationToken).ConfigureAwait(false);
        }

        if (takes)
        {
            telemetry.Changed(channel, Kind(decision.Action));
        }

        if (decision.Alert)
        {
            telemetry.RebindOverCap(purchaseId);
        }

        var lost = takes && snapshot.Holder is { } previous && previous != caller.Value ? snapshot.Holder : null;
        return Result(decision, snapshot, takes || snapshot.Holder == caller.Value, lost, lost is null ? null : SeatMovedBy.User, next, now);
    }

    /// <summary>R3-4: a repeat refreshes; a fourth unexpired claimant replaces the oldest; expired rows don't count.</summary>
    private static async Task AddClaimantAsync(
        ISeatStore store, Guid purchaseId, SeatClaimantRow row, DateTimeOffset now, CancellationToken cancellationToken)
    {
        var existing = await store.ReadClaimantsAsync(purchaseId, cancellationToken).ConfigureAwait(false);
        var others = existing.Where(c => c.InstallId != row.InstallId && Live(c, now)).OrderBy(c => c.ClaimedAt).ToList();
        for (var i = 0; i <= others.Count - SeatClock.MaxClaimants; i++)
        {
            await store.DeleteClaimantAsync(purchaseId, others[i].InstallId, cancellationToken).ConfigureAwait(false);
        }

        await store.UpsertClaimantAsync(purchaseId, row, cancellationToken).ConfigureAwait(false);
    }

    private static bool Live(SeatClaimantRow claimant, DateTimeOffset now) => claimant.ClaimedAt > now - SeatClock.ClaimantLifetime;

    private static SeatResult Result(
        SeatDecision decision,
        SeatSnapshot snapshot,
        bool callerHolds,
        Guid? previousHolder,
        SeatMovedBy? movedBy,
        DateTimeOffset? next,
        DateTimeOffset now) =>
        new(
            decision.Outcome,
            callerHolds,
            SeatClock.CooldownRunning(next, now) ? next : null,
            previousHolder,
            movedBy,
            decision.RestoreSuggested,
            decision.Cause);

    private async Task<bool> MatchAsync(SeatSnapshot snapshot, HolderRelation relation, RegisteredSeatKey? key, CancellationToken cancellationToken)
    {
        if (key is null || snapshot.DeviceKeyHash is not { } stored || relation is HolderRelation.Self or HolderRelation.None)
        {
            return false;
        }

        // Positions ≥ 1 only (T-182): a match on the caller's own element 0 is never a rebind.
        var position = await hasher.MatchSeatAsync(snapshot.PurchaseId, stored, key.Keys, cancellationToken).ConfigureAwait(false);
        return position is >= 1;
    }

    private static bool CapReached(SeatSnapshot snapshot, DateTimeOffset now) =>
        SeatClock.PruneRebinds(snapshot.RecentRebinds, now).Length >= SeatClock.RebindCap;

    private async Task<SeatKeyHash?> HolderHashAsync(Guid purchaseId, RegisteredSeatKey? key, CancellationToken cancellationToken) =>
        key is null ? null : await hasher.SeatKeyHashForHolderAsync(purchaseId, key.Keys, cancellationToken).ConfigureAwait(false);

    private static async Task<SeatSnapshot> LockAsync(ISeatStore store, Guid purchaseId, CancellationToken cancellationToken) =>
        await store.LockAsync(purchaseId, cancellationToken).ConfigureAwait(false)
        ?? throw new InvalidOperationException("The purchase does not exist.");

    private static HolderRelation Relation(SeatSnapshot snapshot, InstallId caller) =>
        !snapshot.SeatExists ? HolderRelation.None
        : snapshot.Holder is not { } holder ? HolderRelation.Vacant
        : holder == caller.Value ? HolderRelation.Self
        : HolderRelation.Other;

    private static void CheckKey(RegisteredSeatKey? key, InstallId caller, SeatOp op)
    {
        if (key is not null && (key.InstallId != caller || key.Op != op))
        {
            throw new ArgumentException("The seat key was registered for another install or operation.", nameof(key));
        }
    }

    private static string Wire(SeatDecision decision) => decision.Cell[0] switch
    {
        'V' => "verify",
        'R' => "restore",
        'S' => "signin",
        _ => "support",
    };

    private static string Kind(SeatAction action) => action switch
    {
        SeatAction.Bind => "bind",
        SeatAction.Rebind => "rebind",
        SeatAction.RebindOverCap => "rebind_over_cap",
        _ => "move",
    };

    private DateTimeOffset Now() => SeatClock.ToDatabasePrecision(time.GetUtcNow());
}
