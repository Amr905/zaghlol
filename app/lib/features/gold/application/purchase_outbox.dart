// T-145: the purchase outbox (BR-GOLD-06). A purchase the store reported but
// the backend has not verified yet lives here, in the encrypted
// `secure_state`, until it is verified. Entries carry the purchase token or
// signed transaction (needed to retry) and the `Idempotency-Key`, so a retry
// resends the same request (R3-6). Nothing is logged; [toString] shows no
// value.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;

import '../../../core/backend/backend_state.dart';

/// `secure_state` key of the outbox.
const String purchaseOutboxStateKey = 'purchase_outbox';

/// At most this many entries are kept (oldest finished ones go first).
const int maxOutboxEntries = 20;

enum OutboxStage {
  /// Waiting for a (re)try of `POST /v1/purchases/verify`.
  queued,

  /// The backend answered `pending` (cash payment): no Gold, poll later.
  pendingServer,

  /// Verified; only the store acknowledgement / finish is outstanding.
  verified,

  /// The backend refused for good. Kept so a store replay is not verified
  /// again in a loop.
  rejected,
}

final class OutboxEntry {
  OutboxEntry({
    required this.id,
    required this.productId,
    required this.reference,
    required this.purchaseId,
    required this.needsCompletion,
    required this.key,
    required this.firstAtMs,
    this.attempts = 0,
    this.nextAtMs = 0,
    this.stage = OutboxStage.queued,
    this.seatPublicKey,
    this.seatSignature,
    this.seatDone = false,
  });

  /// SHA-256 prefix of `productId|reference`; never the token itself.
  static String idFor(String productId, String reference) => c.sha256
      .convert(utf8.encode('$productId|$reference'))
      .toString()
      .substring(0, 32);

  final String id;
  final String productId;
  final String reference;
  final String? purchaseId;
  final bool needsCompletion;

  /// The ULID of this purchase's verify request.
  final String key;
  final int firstAtMs;
  int attempts;
  int nextAtMs;
  OutboxStage stage;

  /// iOS only: element 0 of `seatKeys`, signed once and then reused so the
  /// resent body is byte-identical (same `Idempotency-Key`).
  String? seatPublicKey;
  String? seatSignature;

  /// True once the seat proof was asked for (also when none was available).
  bool seatDone;

  Map<String, Object?> toJson() => {
    'id': id,
    'p': productId,
    'r': reference,
    'pid': purchaseId,
    'nc': needsCompletion,
    'k': key,
    'f': firstAtMs,
    'a': attempts,
    'n': nextAtMs,
    's': stage.name,
    'spk': seatPublicKey,
    'ssg': seatSignature,
    'sd': seatDone,
  };

  static OutboxEntry? fromJson(Object? j) {
    if (j is! Map<String, Object?>) return null;
    final stage = OutboxStage.values.where((s) => s.name == j['s']);
    if (j['id'] is! String ||
        j['p'] is! String ||
        j['r'] is! String ||
        j['k'] is! String ||
        j['f'] is! int ||
        j['a'] is! int ||
        j['n'] is! int ||
        stage.isEmpty) {
      return null;
    }
    return OutboxEntry(
      id: j['id']! as String,
      productId: j['p']! as String,
      reference: j['r']! as String,
      purchaseId: j['pid'] as String?,
      needsCompletion: j['nc'] != false,
      key: j['k']! as String,
      firstAtMs: j['f']! as int,
      attempts: j['a']! as int,
      nextAtMs: j['n']! as int,
      stage: stage.first,
      seatPublicKey: j['spk'] as String?,
      seatSignature: j['ssg'] as String?,
      seatDone: j['sd'] == true,
    );
  }

  @override
  String toString() => 'OutboxEntry(${stage.name})';
}

final class PurchaseOutbox {
  PurchaseOutbox(this._store);
  final BackendStateStore _store;

  Future<List<OutboxEntry>> load() async {
    final raw = await _store.read(purchaseOutboxStateKey);
    if (raw == null) return [];
    try {
      final j = jsonDecode(utf8.decode(raw));
      if (j is! List<Object?>) return [];
      return [for (final e in j) ?OutboxEntry.fromJson(e)];
    } on FormatException {
      return [];
    }
  }

  Future<void> save(List<OutboxEntry> entries) async {
    final kept = List<OutboxEntry>.of(entries);
    while (kept.length > maxOutboxEntries) {
      final i = kept.indexWhere((e) => e.stage == OutboxStage.rejected);
      kept.removeAt(i < 0 ? 0 : i);
    }
    if (kept.isEmpty) {
      await _store.delete(purchaseOutboxStateKey);
      return;
    }
    await _store.write(
      purchaseOutboxStateKey,
      Uint8List.fromList(
        utf8.encode(jsonEncode([for (final e in kept) e.toJson()])),
      ),
    );
  }
}
