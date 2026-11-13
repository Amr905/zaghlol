// T-145: the purchase flow (FR-GOLD-02, BR-GOLD-05/06, backend-api §4.3).
//
// Rules this file enforces:
// - Gold comes only from a backend-signed entitlement. A store `purchased`
//   event alone never changes the tier; the verify answer goes through
//   `EntitlementService.anchored`, which applies Gold only after signature,
//   install-binding and trusted-time checks (CLAUDE.md §2a).
// - The store purchase is completed (Play acknowledge / StoreKit finish) only
//   after the backend verified it. Pending, failed and unreachable purchases
//   stay in the outbox and are retried with the same `Idempotency-Key`.
// - iOS: `seatKeys` carries element 0 only, signed over `op = verify`,
//   `challenge = SHA-256(signedTransaction)`, once per purchase; omitted when
//   T-179 has no usable own key (including the R5-6 flag).
//
// Nothing here logs; no token, transaction or key reaches an error or event.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show PlatformException;

import '../../../core/backend/backend_client.dart';
import '../domain/binding/request_binding.dart';
import '../domain/purchase_outcome.dart';
import '../domain/store_binding.dart';
import 'entitlement.dart';
import 'gating.dart';
import 'gold_ports.dart';
import 'gold_store.dart';
import 'purchase_outbox.dart';

/// Waits between verify attempts (then the last value repeats).
const List<Duration> verifyBackoff = [
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 15),
  Duration(hours: 1),
  Duration(hours: 3),
  Duration(hours: 6),
];

/// A server `pending` purchase (cash payment) is polled this often.
const Duration pendingPoll = Duration(minutes: 15);

/// An outbox entry still unverified after this long is dropped (the store has
/// long since refunded or finished it).
const Duration outboxMaxAge = Duration(days: 14);

String _b64u(List<int> b) => base64Url.encode(b).replaceAll('=', '');

final class PurchaseService {
  PurchaseService({
    required this._store,
    required this._backend,
    required this._entitlement,
    required this._seats,
    required this._outbox,
    required this._platform,
    this._scheduler,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final GoldStore _store;
  final GoldBackend _backend;
  final EntitlementService _entitlement;
  final SeatProver _seats;
  final PurchaseOutbox _outbox;
  final ClientPlatform _platform;
  final PurchaseRetryScheduler? _scheduler;
  final DateTime Function() _now;

  final StreamController<PurchaseOutcome> _outcomes =
      StreamController<PurchaseOutcome>.broadcast();
  StreamSubscription<List<StorePurchase>>? _sub;
  Future<void> _tail = Future<void>.value();

  /// Results for T-146. Broadcast; late listeners miss earlier events.
  Stream<PurchaseOutcome> get outcomes => _outcomes.stream;

  /// Listens to the store (must run at app start) and retries what is due.
  Future<void> start() async {
    if (_sub != null) return;
    _sub = _store.updates.listen(
      (list) => unawaited(_serial(() => _onUpdates(list))),
    );
    await _store.start();
    await retryDue();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _scheduler?.cancel();
  }

  /// Starts the store sheet for [productId]. The outcome arrives on
  /// [outcomes]. False when the flow could not start.
  Future<bool> buy(String productId) async {
    try {
      final id = await _backend.ensureInstalled();
      return await _store.buy(productId, bindingRef: storeBindingRef(id));
    } on PlatformException {
      return false;
    } on BackendFailure {
      return false;
    }
  }

  /// Retries every outbox entry that is due (app start, resume, timer).
  Future<void> retryDue() => _serial(() async {
    final entries = await _outbox.load();
    final nowMs = _now().millisecondsSinceEpoch;
    for (final e in entries) {
      if ((e.stage == OutboxStage.queued ||
              e.stage == OutboxStage.pendingServer) &&
          e.nextAtMs <= nowMs) {
        await _attempt(e);
      }
    }
    await _reschedule();
  });

  // ---- internals ----

  Future<void> _onUpdates(List<StorePurchase> list) async {
    for (final p in list) {
      switch (p.state) {
        case StorePurchaseState.pending:
          _emit(const PurchasePending());
        case StorePurchaseState.error || StorePurchaseState.canceled:
          _emit(const PurchaseCancelled());
        case StorePurchaseState.purchased || StorePurchaseState.restored:
          await _onPaid(p);
      }
    }
    await _reschedule();
  }

  Future<void> _onPaid(StorePurchase p) async {
    if (p.reference.isEmpty || !GoldProducts.all.contains(p.productId)) return;
    final entries = await _outbox.load();
    final id = OutboxEntry.idFor(p.productId, p.reference);
    final existing = entries.where((e) => e.id == id).firstOrNull;
    if (existing == null) {
      final e = OutboxEntry(
        id: id,
        productId: p.productId,
        reference: p.reference,
        purchaseId: p.purchaseId,
        needsCompletion: p.needsCompletion,
        key: _backend.newKey().value,
        firstAtMs: _now().millisecondsSinceEpoch,
      );
      await _outbox.save([...entries, e]);
      await _attempt(e, live: p);
      return;
    }
    switch (existing.stage) {
      case OutboxStage.rejected:
        return;
      case OutboxStage.verified:
        // Verified earlier; only the store completion was missing.
        if (await _store.complete(p)) await _remove(existing);
      case OutboxStage.queued || OutboxStage.pendingServer:
        if (existing.nextAtMs <= _now().millisecondsSinceEpoch) {
          await _attempt(existing, live: p);
        }
    }
  }

  Future<void> _attempt(OutboxEntry e, {StorePurchase? live}) async {
    final nowMs = _now().millisecondsSinceEpoch;
    if (nowMs - e.firstAtMs > outboxMaxAge.inMilliseconds) {
      await _reject(e);
      return;
    }
    e.attempts++;
    final PurchaseVerifyRequest request;
    try {
      request = await _requestFor(e);
    } on ApiModelException {
      await _reject(e);
      _emit(const PurchaseInvalid());
      return;
    }

    final PurchaseVerifyResponse resp;
    try {
      resp = await _entitlement.anchored(
        (nonce) =>
            _backend.verify(request, IdempotencyKey.restore(e.key), nonce),
        SignedBody.fromVerify,
      );
    } on BackendFailure catch (f) {
      await _onFailure(e, f);
      return;
    }
    await _onResponse(e, resp, live);
  }

  Future<PurchaseVerifyRequest> _requestFor(OutboxEntry e) async {
    if (_platform != ClientPlatform.ios) {
      return PurchaseVerifyAndroidRequest(
        productId: e.productId,
        purchaseToken: e.reference,
      );
    }
    if (!e.seatDone) {
      final sigs = await _seats.prove(
        SeatOp.verify,
        verifySeatChallenge(e.reference),
      );
      if (sigs.isNotEmpty) {
        e.seatPublicKey = _b64u(sigs.first.publicKey);
        e.seatSignature = _b64u(sigs.first.signature);
      }
      e.seatDone = true;
      await _save(e);
    }
    final pk = e.seatPublicKey;
    final sg = e.seatSignature;
    return PurchaseVerifyIosRequest(
      signedTransaction: e.reference,
      seatKeys: pk == null || sg == null
          ? null
          : [SeatKeyProof(publicKey: pk, signature: sg)],
    );
  }

  Future<void> _onResponse(
    OutboxEntry e,
    PurchaseVerifyResponse r,
    StorePurchase? live,
  ) async {
    switch (r.status) {
      case PurchaseStatus.active:
        final phase = await _entitlement.evaluate();
        final gold =
            phase == EntitlementPhase.active || phase == EntitlementPhase.grace;
        if (r.seatHeldElsewhere == true) {
          await _verified(e, live);
          _emit(
            PurchaseSeatHeldElsewhere(
              accountRequired: r.accountRequired == true,
              nextMoveAt: r.nextMoveAt == null
                  ? null
                  : DateTime.tryParse(r.nextMoveAt!)?.toUtc(),
            ),
          );
        } else if (gold && r.entitlement != null) {
          await _verified(e, live);
          _emit(const PurchaseGold());
        } else {
          // "active" without an entitlement this app could verify: fail
          // closed. No Gold, no acknowledgement; try again later.
          await _retryLater(e, null);
        }
      case PurchaseStatus.pending:
        e.stage = OutboxStage.pendingServer;
        e.nextAtMs = _now().add(pendingPoll).millisecondsSinceEpoch;
        await _save(e);
        _emit(const PurchasePending());
      case PurchaseStatus.expired ||
          PurchaseStatus.refunded ||
          PurchaseStatus.invalid:
        await _reject(e);
        _emit(const PurchaseInvalid());
      case PurchaseStatus.accountRequired || PurchaseStatus.unknown:
        await _retryLater(e, null);
    }
  }

  Future<void> _verified(OutboxEntry e, StorePurchase? live) async {
    e.stage = OutboxStage.verified;
    await _save(e);
    final p =
        live ??
        StorePurchase(
          productId: e.productId,
          state: StorePurchaseState.purchased,
          reference: e.reference,
          purchaseId: e.purchaseId,
          needsCompletion: e.needsCompletion,
        );
    try {
      if (await _store.complete(p)) await _remove(e);
    } on PlatformException {
      // Stays `verified`; the store replays the purchase at the next start
      // and it is completed then, without a second verify.
    }
  }

  Future<void> _onFailure(OutboxEntry e, BackendFailure f) async {
    if (f.kind == BackendFailureKind.problem) {
      switch (f.problem) {
        case ProblemCode.purchaseNotOwned:
          await _reject(e);
          _emit(const PurchaseNotOwned());
          return;
        case ProblemCode.purchaseTokenInvalid ||
            ProblemCode.purchaseWrongApp ||
            ProblemCode.validationFailed:
          await _reject(e);
          _emit(const PurchaseInvalid());
          return;
        default:
          break;
      }
      final s = f.httpStatus ?? 0;
      final transient = s == 408 || s == 429 || s >= 500;
      if (!transient) {
        await _reject(e);
        _emit(const PurchaseInvalid());
        return;
      }
    } else if (f.kind == BackendFailureKind.clientBug) {
      await _reject(e);
      _emit(const PurchaseInvalid());
      return;
    }
    await _retryLater(e, f.retryAfter);
  }

  Future<void> _retryLater(OutboxEntry e, Duration? retryAfter) async {
    final i = (e.attempts - 1).clamp(0, verifyBackoff.length - 1);
    var wait = verifyBackoff[i];
    if (retryAfter != null && retryAfter > wait) wait = retryAfter;
    e.stage = OutboxStage.queued;
    e.nextAtMs = _now().add(wait).millisecondsSinceEpoch;
    await _save(e);
    _emit(PurchaseQueued(retryAt: _now().add(wait).toUtc()));
  }

  Future<void> _reject(OutboxEntry e) async {
    e.stage = OutboxStage.rejected;
    await _save(e);
  }

  Future<void> _save(OutboxEntry e) async {
    final all = await _outbox.load();
    final i = all.indexWhere((x) => x.id == e.id);
    if (i < 0) {
      all.add(e);
    } else {
      all[i] = e;
    }
    await _outbox.save(all);
  }

  Future<void> _remove(OutboxEntry e) async {
    final all = await _outbox.load();
    all.removeWhere((x) => x.id == e.id);
    await _outbox.save(all);
  }

  Future<void> _reschedule() async {
    final s = _scheduler;
    if (s == null) return;
    final due = (await _outbox.load())
        .where(
          (e) =>
              e.stage == OutboxStage.queued ||
              e.stage == OutboxStage.pendingServer,
        )
        .map((e) => e.nextAtMs);
    if (due.isEmpty) {
      s.cancel();
      return;
    }
    final next = due.reduce((a, b) => a < b ? a : b);
    s.scheduleAt(DateTime.fromMillisecondsSinceEpoch(next));
  }

  void _emit(PurchaseOutcome o) {
    if (!_outcomes.isClosed) _outcomes.add(o);
  }

  Future<void> _serial(Future<void> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  @override
  String toString() => 'PurchaseService';
}
