// T-017: shared helpers for the batch-A schema tests. An encrypted database
// on a temp file (sqlite3mc, synthetic key; sqlite3mc does not encrypt
// in-memory databases), plus synthetic rows. Every text here is invented;
// no real message, merchant record or account number.

import 'package:drift/drift.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_opener.dart'
    show defaultDbExecutor;
import 'package:zaghlol/core/db/daos/write_errors.dart';
import 'package:zaghlol/core/db/db_errors.dart';

import '../../support/fake_secret_store.dart';
import 'db_open_harness.dart';

/// 2^53 − 1, the money bound (T-012).
const int maxMinor = 9007199254740991;

/// A fixed epoch-ms time (2026-11-01T10:00Z) for synthetic rows.
const int t0 = 1793527200000;

/// An open encrypted database in its own temp world.
final class EncryptedDb {
  EncryptedDb._(this.world, this.db);

  final DbWorld world;
  final AppDatabase db;

  /// [background]: drift's isolate (the app's executor) or this isolate.
  static Future<EncryptedDb> open({bool background = true}) async {
    final world = await DbWorld.create(FakeSecretStore(), tag: 't017');
    final db = openedDb(
      await world.open(
        executor: background ? defaultDbExecutor : foregroundExecutor,
      ),
    );
    return EncryptedDb._(world, db);
  }

  Future<void> close() async {
    await db.close();
    await world.dispose();
  }
}

/// Runs raw [sql] and returns the [DbWriteException] code it fails with,
/// or null when it succeeds.
Future<String?> failureOf(
  AppDatabase db,
  String sql, [
  List<Object?> args = const [],
]) async {
  try {
    await guardWrite(() => db.customStatement(sql, args));
    return null;
  } on DbWriteException catch (e) {
    return e.code;
  }
}

AccountsCompanion account(
  String id, {
  String kind = 'debit',
  String? institution = 'BNK',
  String? last4 = '1234',
  String currency = 'EGP',
  bool defaultCash = false,
}) => AccountsCompanion.insert(
  id: id,
  institutionCode: Value(institution),
  kind: kind,
  label: 'Synthetic $id',
  last4: Value(last4),
  defaultCurrency: currency,
  isDefaultCash: Value(defaultCash ? 1 : 0),
  createdAt: t0,
  updatedAt: t0,
);

TransactionsCompanion txn(
  String id, {
  String accountId = 'acc1',
  String direction = 'expense',
  int amountMinor = 10000,
  String currency = 'EGP',
  String? merchant,
  String? merchantNorm,
  String? counterparty,
  String? note,
  int occurredAt = t0,
}) => TransactionsCompanion.insert(
  id: id,
  accountId: accountId,
  source: 'manual',
  direction: direction,
  amountMinor: amountMinor,
  currency: currency,
  occurredAt: occurredAt,
  occurredTzOffsetMin: 120,
  merchantRaw: Value(merchant),
  merchantNorm: Value(merchantNorm),
  counterpartyValue: Value(counterparty),
  note: Value(note),
  categorySource: 'none',
  createdAt: t0,
  updatedAt: t0,
);

/// A synthetic 64-hex-char body hash from [n].
String hashOf(int n) => n.toRadixString(16).padLeft(64, '0');

RawMessagesCompanion rawMessage(String id, {required int hash}) =>
    RawMessagesCompanion.insert(
      id: id,
      channel: 'sms',
      sender: const Value('SYNTH-BANK'),
      body: 'SYNTHETIC body $id',
      bodyHash: hashOf(hash),
      receivedAt: t0,
      parseStatus: 'parsed',
      registryVersion: 1,
      createdAt: t0,
    );

OffsetLinksCompanion link(
  String id, {
  required String expense,
  required String source,
  required int amountMinor,
  String kind = 'reimbursement',
  String? participant,
}) => OffsetLinksCompanion.insert(
  id: id,
  kind: kind,
  expenseTxnId: expense,
  sourceTxnId: source,
  amountMinor: amountMinor,
  participantId: Value(participant),
  createdAt: t0,
);
