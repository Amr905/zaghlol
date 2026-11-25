// Fix 70 (M-1, M-2, FU-315): a masked account number never makes a row
// internal on its own; only a template that says so does. Synthetic data.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/accounts_dao.dart';
import 'package:zaghlol/features/accounts/domain/card_due.dart';
import 'package:zaghlol/features/ingestion/data/device_local_zone.dart';
import 'package:zaghlol/features/ingestion/data/drift_ingest_store.dart';
import 'package:zaghlol/features/ingestion/data/ingest_factory.dart';
import 'package:zaghlol/features/ingestion/domain/body_hash.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_records.dart';
import 'package:zaghlol/features/ingestion/application/reparse.dart';
import 'package:zaghlol/ingestion/bundled_registry.dart';
import 'package:zaghlol/ingestion/spike_registry.dart' show RegistryGuardBase;
import 'package:zaghlol/features/ingestion/application/ingest_raw_messages.dart'
    show RawStatus;
import 'package:zaghlol_parsing/zaghlol_parsing.dart' hide CategorySource;

import '../features/ingestion/support/ingest_harness.dart';

final int _rx = DateTime.utc(2026, 11, 25, 8).millisecondsSinceEpoch;

String _arabBank(String to) =>
    'تم تنفيذ تحويل لحظي بمبلغ EGP 5000.00 بتاريخ 24/11/2026 18:10. من حسابك '
    '419*5044 الى $to  . رقم مرجعي77700668421. الرصيد المتوفر EGP 12320.23 '
    'للمزيد 19100.';

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

  ParsingPipeline pipeline() => ParsingPipeline(registry);

  Future<void> ingest(
    String sender,
    String body, {
    String channel = 'sms',
    int? rx,
    int? nowMs,
  }) async {
    final at = rx ?? _rx;
    final use = buildIngestRawMessages(
      w.db,
      pipeline: pipeline(),
      guardBase: BytesGuardBase(base),
      newId: w.newId,
      clock: () =>
          DateTime.fromMillisecondsSinceEpoch(nowMs ?? at, isUtc: true),
      zone: const FixedLocalZone(zoneOffsetMin),
      diag: w.diag,
      events: w.bus,
    );
    final id = 'm${seq++}';
    await use([
      channel == 'sms'
          ? sms(id, body, source: sender, rx: at)
          : notif(id, body, source: sender, rx: at),
    ]);
  }

  Future<Map<String, Object?>> only() async => (await w.txns()).single;

  group('M-1: a masked account is not "own"', () {
    test('an Arab Bank InstaPay out to a masked number stays external and '
        'counts in spending', () async {
      await ingest('ArabBank', _arabBank('0021234***5678'));
      final t = await only();
      expect(t['direction'], 'transfer_out');
      expect(t['counterparty_kind'], isNot('own_account'));
      expect(t['is_internal'], 0);
      expect(t['transfer_pair_id'], isNull);
      expect(await w.count('transfer_pairs'), 0);
    });

    test('a salary from a masked employer account stays income', () async {
      await ingest(
        'de.number26.android',
        'N26\nMoney received: €2,000.00 from 0021234***5678',
        channel: 'notification',
      );
      final t = await only();
      expect(t['counterparty_kind'], isNot('own_account'));
      expect(t['is_internal'], 0);
    });

    test('"Exxon 24" is a name, not an account', () async {
      await ingest(
        'de.number26.android',
        'N26\nMoney received: €10.00 from Exxon 24',
        channel: 'notification',
      );
      final t = await only();
      expect(t['counterparty_kind'], 'person');
      expect(t['is_internal'], 0);
    });

    test('the HSBC card payment (case 10) is a transfer_in on the card with '
        'own_account', () async {
      await AccountsDao(w.db).insert(
        AccountsCompanion.insert(
          id: 'acc_2859',
          kind: 'credit',
          label: 'Card',
          institutionCode: const Value('hsbc'),
          last4: const Value('2859'),
          defaultCurrency: 'EGP',
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      await ingest(
        'HSBC',
        'From HSBC: 28OCT26 Transfer from 002-388***-001 EGP 47.82- to your '
            'Credit Card ending with 2859 as per your instruction. '
            'Your available balance is EGP 0.00',
      );
      final t = await only();
      expect(t['direction'], 'transfer_in');
      expect(t['account_id'], 'acc_2859');
      expect(t['counterparty_kind'], 'own_account');
    });
  });

  group('FU-315: an explicit 0.00 statement', () {
    String stmt(String amt) =>
        'كشف حساب شهر أكتوبر 2026  لبطاقتك الائتمانية المنتهية بـ 1234 هو '
        '$amt جم ، الحد الأدنى للسداد قبل  25/12 هو $amt جم .يمكنك الاطلاع '
        'على تفاصيل كشف الحساب من خلال الرابط التالي: https://example.invalid/x1';

    test(
      'reaches "nothing due" from a real message and is no transaction',
      () async {
        await AccountsDao(w.db).insert(
          AccountsCompanion.insert(
            id: 'acc_1234',
            kind: 'credit',
            label: 'Card',
            institutionCode: const Value('cib'),
            last4: const Value('1234'),
            defaultCurrency: 'EGP',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
        await ingest('CIB', stmt('0.00'));
        expect(await w.txns(), isEmpty);
        final r = await w.rows('SELECT value FROM settings WHERE key = ?1', [
          cardDueKey('cib', '1234'),
        ]);
        final d = CardDue.decode(r.single['value']! as String)!;
        expect(d.nothingDue, isTrue);
        expect(d.isPaid, isTrue);
      },
    );
  });

  group('M-2: re-parse skips a past due date', () {
    Future<void> oldRaw(String body, String id) async {
      await DriftIngestStore(w.db).insertRaw(
        RawInsert(
          id: id,
          channel: 'sms',
          sender: 'CIB',
          body: body,
          bodyHash: bodyHashV1(
            senderKey: senderKeyOf('sms', 'CIB'),
            body: body,
          ),
          receivedAtMs: _rx - 120 * Duration.millisecondsPerDay,
          parseStatus: RawStatus.parsed,
          registryVersion: 1,
          createdAtMs: _rx,
        ),
      );
    }

    Future<void> reparse() => ReparseJob(
      store: DriftIngestStore(w.db),
      ingest: buildIngestRawMessages(
        w.db,
        pipeline: pipeline(),
        guardBase: RegistryGuardBase(registry),
        newId: w.newId,
        clock: () => DateTime.fromMillisecondsSinceEpoch(_rx, isUtc: true),
        zone: const FixedLocalZone(zoneOffsetMin),
        diag: w.diag,
        events: w.bus,
      ),
      registryVersion: registry.registryVersion,
      diag: w.diag,
    ).run();

    Future<void> card() => AccountsDao(w.db).insert(
      AccountsCompanion.insert(
        id: 'acc_5490',
        kind: 'credit',
        label: 'Card',
        institutionCode: const Value('cib'),
        last4: const Value('5490'),
        defaultCurrency: 'EGP',
        createdAt: 1,
        updatedAt: 1,
      ),
    );

    String due(String d) =>
        'عميلنا العزيز، سيتم خصم 51.77 جم من حسابكم لسداد بطاقتك المنتهية بـ '
        '5490  في $d, في حالة أن يوم السداد يزامن عطلة رسمية سوف يتم الخصم '
        'قبل العطلات الرسمية. يمكنك الاطلاع على تفاصيل كشف الحساب من خلال '
        'الرابط التالي: https://example.invalid/x1';

    Future<int> dueSettings() async =>
        (await w.rows('SELECT count(*) AS c FROM settings WHERE key = ?1', [
              cardDueKey('cib', '5490'),
            ])).single['c']!
            as int;

    test(
      'a notice with a past due date changes no due and no reminder',
      () async {
        await card();
        await oldRaw(due('25/07/2026'), 'raw_old');
        await reparse();
        expect(await dueSettings(), 0);
        expect(await w.count('recurring_items'), 0);
      },
    );

    test('a notice with a future due date still applies', () async {
      await card();
      await oldRaw(due('25/12/2026'), 'raw_new');
      await reparse();
      expect(await dueSettings(), 1);
      final it = (await w.rows('SELECT * FROM recurring_items')).single;
      expect(it['next_due_date'], '2026-12-25');
    });
  });
}
