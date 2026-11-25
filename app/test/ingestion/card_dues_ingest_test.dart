// T-245 (D-83): card dues from notices. Real bundled registry, real hooks and
// an encrypted in-memory-style DB; synthetic messages (PO suite cases 7, 8
// and 12 with other digits).

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/features/accounts/domain/card_due.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/ingestion/data/ingest_factory.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol/features/recurring/data/recurring_repository.dart';
import 'package:zaghlol/ingestion/bundled_registry.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show CivilDate;
import 'package:zaghlol_parsing/zaghlol_parsing.dart' hide CategorySource;

import '../features/ingestion/support/ingest_harness.dart';

const String _case7 =
    'عميلنا العزيز، سيتم خصم 51.77 جم من حسابكم لسداد بطاقتك المنتهية بـ 5490  '
    'في 25/11, في حالة أن يوم السداد يزامن عطلة رسمية سوف يتم الخصم قبل '
    'العطلات الرسمية. يمكنك الاطلاع على تفاصيل كشف الحساب من خلال الرابط '
    'التالي: https://example.invalid/x1';
String _statement(String last4, String total, String min, String due) =>
    'كشف حساب شهر أكتوبر 2026  لبطاقتك الائتمانية المنتهية بـ $last4 هو '
    '$total جم ، الحد الأدنى للسداد قبل  $due هو $min جم .يمكنك الاطلاع على '
    'تفاصيل كشف الحساب من خلال الرابط التالي: https://example.invalid/x1';
const String _case12 =
    'HSBC Credit Card ending *** 2859 Statement Date 03/10/2026. Total Amt Due '
    'EGP 47.82, Due Date 28/10/2026. Min. Amt Due EGP 47.82. Please ignore if '
    'paid.';
String _payment(String amount) =>
    'البنك التجاري الدولي: تم استلام سداد بمبلغ $amount جم على بطاقة '
    'الائتمان المنتهية بـ 1234. الحد المتاح 110095.29 جم';

const int _day = Duration.millisecondsPerDay;
final int _rx = DateTime.utc(2026, 11, 25, 8).millisecondsSinceEpoch;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final base = File('assets/guard/guard_base.json').readAsBytesSync();
  late IngestWorld w;
  late Registry registry;
  var seq = 0;

  setUp(() async {
    registry = await preloadBundledRegistry();
    w = await IngestWorld.open();
    addTearDown(w.close);
  });

  Future<IngestOutcome?> ingest(String sender, String body, int rx) async {
    final use = buildIngestRawMessages(
      w.db,
      pipeline: ParsingPipeline(registry),
      guardBase: BytesGuardBase(base),
      newId: w.newId,
      clock: () => DateTime.fromMillisecondsSinceEpoch(rx, isUtc: true),
      zone: const FixedLocalZone(zoneOffsetMin),
      diag: w.diag,
      events: w.bus,
    );
    final id = 'm${seq++}';
    return (await use([sms(id, body, source: sender, rx: rx)])).outcomes[id];
  }

  Future<void> card(
    String inst,
    String last4, {
    int? dueDay,
    int updatedAt = 1,
  }) => AccountsDao(w.db).insert(
    AccountsCompanion.insert(
      id: 'acc_$last4',
      kind: 'credit',
      label: 'Card $last4',
      institutionCode: Value(inst),
      last4: Value(last4),
      defaultCurrency: 'EGP',
      statementDueDay: Value(dueDay),
      createdAt: 1,
      updatedAt: updatedAt,
    ),
  );

  Future<CardDue?> stored(String inst, String last4) async {
    final r = await w.rows('SELECT value FROM settings WHERE key = ?1', [
      cardDueKey(inst, last4),
    ]);
    return r.isEmpty ? null : CardDue.decode(r.single['value']! as String);
  }

  Future<Map<String, Object?>?> item(String accountId) async {
    final r = await w.rows(
      "SELECT * FROM recurring_items WHERE kind = 'card_due' AND account_id = "
      '?1',
      [accountId],
    );
    return r.isEmpty ? null : r.single;
  }

  RecurringRepository repo() => RecurringRepository(
    w.db,
    clock: () => DateTime.utc(2026, 11, 26),
    newId: w.newId,
  );

  test('case 7: the reminder sets the due date and amount on the card and '
      'writes no transaction', () async {
    await card('cib', '5490');
    expect(await ingest('CIB', _case7, _rx), isA<IngestNotice>());
    expect(await w.txns(), isEmpty);
    final it = (await item('acc_5490'))!;
    expect(it['next_due_date'], '2026-11-25');
    expect(it['amount_minor'], 5177);
    expect(it['due_day'], 25);
    final d = (await stored('cib', '5490'))!;
    expect(d.amountDueMinor, 5177);
    expect(d.applied, isTrue);
    final acc = await w.rows(
      "SELECT statement_due_day FROM accounts WHERE id = 'acc_5490'",
    );
    expect(acc.single['statement_due_day'], 25);
  });

  test('case 8: the statement stores total and minimum', () async {
    await card('cib', '6603');
    await ingest('CIB', _statement('6603', '120.50', '30.00', '25/11'), _rx);
    final d = (await stored('cib', '6603'))!;
    expect(d.amountDueMinor, 12050);
    expect(d.minDueMinor, 3000);
    expect(d.dueDate, CivilDate(2026, 11, 25));
    expect(await w.txns(), isEmpty);
  });

  test('case 12: the HSBC statement carries total, minimum, due and '
      'statement dates', () async {
    await card('hsbc', '2859');
    await ingest('HSBC', _case12, _rx);
    final d = (await stored('hsbc', '2859'))!;
    expect(d.amountDueMinor, 4782);
    expect(d.minDueMinor, 4782);
    expect(d.dueDate, CivilDate(2026, 10, 28));
    expect(d.statementDate, CivilDate(2026, 10, 3));
    expect(await w.txns(), isEmpty);
    expect((await item('acc_2859'))!['next_due_date'], '2026-10-28');
  });

  test('a later notice replaces an older one; an older never replaces a '
      'newer', () async {
    await card('cib', '6603');
    await ingest('CIB', _statement('6603', '100.00', '30.00', '25/11'), _rx);
    await ingest(
      'CIB',
      _statement('6603', '200.00', '50.00', '25/12'),
      _rx + 30 * _day,
    );
    expect((await stored('cib', '6603'))!.amountDueMinor, 20000);
    // An older message arrives late (a re-scan): nothing changes.
    await ingest(
      'CIB',
      _statement('6603', '999.00', '99.00', '25/10'),
      _rx - 30 * _day,
    );
    final d = (await stored('cib', '6603'))!;
    expect(d.amountDueMinor, 20000);
    expect(d.dueDate, CivilDate(2026, 12, 25));
    final it = (await item('acc_6603'))!;
    expect(it['next_due_date'], '2026-12-25');
    expect(it['amount_minor'], 20000);
  });

  test('a notice with no card is kept and applied when the card is created '
      'later', () async {
    await ingest('CIB', _statement('7777', '80.00', '20.00', '25/11'), _rx);
    expect((await stored('cib', '7777'))!.applied, isFalse);
    expect(await w.count('recurring_items'), 0);
    await card('cib', '7777');
    expect(await repo().syncCardDues(), greaterThan(0));
    final it = (await item('acc_7777'))!;
    expect(it['next_due_date'], '2026-11-25');
    expect(it['amount_minor'], 8000);
    expect((await stored('cib', '7777'))!.applied, isTrue);
    // Idempotent.
    expect(await repo().syncCardDues(), 0);
  });

  test('the typed due day is kept when the notice is older than the edit; '
      'this cycle still gets the notice date', () async {
    await card('cib', '6603', dueDay: 10, updatedAt: _rx + 5 * _day);
    await ingest('CIB', _statement('6603', '100.00', '30.00', '25/11'), _rx);
    final acc = await w.rows(
      "SELECT statement_due_day FROM accounts WHERE id = 'acc_6603'",
    );
    expect(acc.single['statement_due_day'], 10);
    final it = (await item('acc_6603'))!;
    expect(it['due_day'], 10);
    expect(it['next_due_date'], '2026-11-25');
    // The daily sync does not undo it.
    await repo().syncCardDues();
    expect((await item('acc_6603'))!['next_due_date'], '2026-11-25');
  });

  test('a newer notice moves the typed due day', () async {
    await card('cib', '6603', dueDay: 10, updatedAt: _rx - 5 * _day);
    await ingest('CIB', _statement('6603', '100.00', '30.00', '25/11'), _rx);
    final acc = await w.rows(
      "SELECT statement_due_day FROM accounts WHERE id = 'acc_6603'",
    );
    expect(acc.single['statement_due_day'], 25);
  });

  group('payments', () {
    Future<void> seed() async {
      await card('cib', '1234');
      await ingest('CIB', _statement('1234', '100.00', '30.00', '25/11'), _rx);
    }

    test('a payment covering the minimum marks the due paid and moves the '
        'reminder on', () async {
      await seed();
      await ingest('CIB', _payment('50.00'), _rx + 1000);
      expect(await w.count('transactions'), 1);
      expect((await stored('cib', '1234'))!.isPaid, isTrue);
      final it = (await item('acc_1234'))!;
      expect(it['next_due_date'], '2026-12-25');
      expect(it['paid_count'], 1);
      expect(await w.count('recurring_occurrences'), 1);
    });

    test('a partial payment is recorded and the reminder shows the rest of '
        'the minimum', () async {
      await seed();
      await ingest('CIB', _payment('10.00'), _rx + 1000);
      final d = (await stored('cib', '1234'))!;
      expect(d.paidMinor, 1000);
      expect(d.isPaid, isFalse);
      final it = (await item('acc_1234'))!;
      expect(it['next_due_date'], '2026-11-25');
      expect(it['amount_minor'], 2000);
      expect(await w.count('recurring_occurrences'), 0);
      await ingest('CIB', _payment('25.00'), _rx + 2000);
      expect((await stored('cib', '1234'))!.isPaid, isTrue);
      expect((await item('acc_1234'))!['next_due_date'], '2026-12-25');
    });

    test('a payment before the statement does not count', () async {
      await seed();
      await ingest('CIB', _payment('50.00'), _rx - 10 * _day);
      expect((await stored('cib', '1234'))!.paidMinor, 0);
      expect((await item('acc_1234'))!['next_due_date'], '2026-11-25');
    });

    // Batch 68 T-242 M-1: the HSBC transfer SMS (PO case 10) pays the card:
    // a transfer into it, no balance from the source account, due paid.
    test('an HSBC transfer to the card is a transfer_in that pays the due '
        'and writes no card balance', () async {
      await card('hsbc', '2859');
      await ingest('HSBC', _case12, _rx);
      await ingest(
        'HSBC',
        'From HSBC: 28OCT26 Transfer from 002-388***-001 EGP 47.82- to your '
            'Credit Card ending with 2859 as per your instruction. '
            'Your available balance is EGP 0.00',
        _rx + 1000,
      );
      final t = await w.txns();
      expect(t, hasLength(1));
      expect(t.single['direction'], 'transfer_in');
      expect(t.single['account_id'], 'acc_2859');
      expect(t.single['amount_minor'], 4782);
      // T-248 (FU-298): the masked source account is not a person.
      expect(t.single['counterparty_kind'], 'own_account');
      expect(t.single['balance_after_minor'], isNull);
      expect(await w.count('account_balances'), 0);
      expect((await stored('hsbc', '2859'))!.isPaid, isTrue);
    });
  });
}
