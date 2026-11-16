// SMS-fuzzy: the live one-tap confirm of a generic suggestion, end to end on
// an encrypted test database. Synthetic data only.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/core/db/daos/review_items_dao.dart';
import 'package:zaghlol/features/ingestion/presentation/review/review_models.dart';
import 'package:zaghlol/features/ingestion/presentation/review/review_providers.dart';

import '../../../../core/db/financial_fixtures.dart';

void main() {
  late EncryptedDb edb;
  late AppDatabase db;
  late ProviderContainer c;

  Map<String, Object?> payload({
    bool complete = true,
    String currency = 'EGP',
    String direction = 'expense',
    String? last4 = '1234',
    int occurredAtMs = t0,
  }) => {
    'generic': true,
    'institutionCode': 'BNK',
    'institutionLabel': 'Synthetic Bank',
    'amount': {'minor': 84550, 'currency': currency},
    'direction': direction,
    'last4': ?last4,
    'merchant': 'Synth Market',
    'merchantKey': 'synth market',
    'occurredAtMs': occurredAtMs,
    'tzOffsetMin': 120,
    'source': 'sms',
    'prefillComplete': complete,
  };

  Future<void> seed(String id, Map<String, Object?> p) async {
    await ReviewItemsDao(db).insert(
      id: id,
      kind: 'unrecognized',
      rawMessageId: 'raw1',
      payload: p,
      createdAt: t0,
    );
  }

  MessageCardModel card(String id) => MessageCardModel(
    itemId: id,
    sender: 'SYNTH-BANK',
    isNewSender: false,
    rawMessageId: 'raw1',
    oneTap: true,
  );

  setUp(() async {
    edb = await EncryptedDb.open();
    db = edb.db;
    await db.into(db.accounts).insert(account('acc1'));
    await db.into(db.rawMessages).insert(rawMessage('raw1', hash: 1));
    await db.customStatement(
      "UPDATE raw_messages SET parse_status = 'review' WHERE id = 'raw1'",
    );
    c = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) async => db)],
    );
  });
  tearDown(() async {
    c.dispose();
    await edb.close();
  });

  test('one tap saves the suggestion as read under the bank card', () async {
    await seed('g1', payload());
    final ok = await c.read(reviewActionsProvider).confirmGeneric(card('g1'));
    expect(ok, isTrue);
    final rows = await db
        .customSelect(
          'SELECT account_id, source, direction, amount_minor, currency, '
          'merchant_raw, is_user_verified, raw_message_id FROM transactions',
        )
        .get();
    expect(rows, hasLength(1));
    final t = rows.single.data;
    expect(t['account_id'], 'acc1');
    expect(t['source'], 'sms');
    expect(t['direction'], 'expense');
    expect(t['amount_minor'], 84550);
    expect(t['currency'], 'EGP');
    expect(t['merchant_raw'], 'Synth Market');
    expect(t['is_user_verified'], 1);
    expect(t['raw_message_id'], 'raw1');
    final item = await ReviewItemsDao(db).byId('g1');
    expect(item!.resolvedAt, isNotNull);
    // A second tap does nothing.
    expect(
      await c.read(reviewActionsProvider).confirmGeneric(card('g1')),
      isFalse,
    );
  });

  test(
    'a foreign-currency purchase is stored as read, never converted',
    () async {
      await seed('g2', payload(currency: 'USD'));
      expect(
        await c.read(reviewActionsProvider).confirmGeneric(card('g2')),
        isTrue,
      );
      final t =
          (await db
                  .customSelect(
                    'SELECT amount_minor, currency FROM transactions',
                  )
                  .getSingle())
              .data;
      expect(t['currency'], 'USD');
      expect(t['amount_minor'], 84550);
    },
  );

  test('confirm saves exactly the account, date and kind the card shows '
      '(batch-27)', () async {
    // A message date before the receipt, and a transfer (not "spent at").
    const read = t0 - 3 * 86400000;
    await seed('g4', payload(direction: 'transfer_out', occurredAtMs: read));
    final shown = (await c.read(reviewQueueProvider.future))
        .whereType<MessageCardModel>()
        .single;
    expect(shown.oneTap, isTrue);
    expect(shown.direction?.code, 'transfer_out');
    expect(shown.occurredAt?.millisecondsSinceEpoch, read);
    expect(shown.last4, '1234');
    expect(shown.bankLabel, 'Synthetic Bank');
    expect(await c.read(reviewActionsProvider).confirmGeneric(shown), isTrue);
    final t =
        (await db
                .customSelect(
                  'SELECT t.direction, t.occurred_at, a.last4, '
                  'a.institution_code FROM transactions t '
                  'JOIN accounts a ON a.id = t.account_id',
                )
                .getSingle())
            .data;
    expect(t['direction'], shown.direction!.code);
    expect(t['occurred_at'], shown.occurredAt!.millisecondsSinceEpoch);
    expect(t['last4'], shown.last4);
    expect(t['institution_code'], 'BNK');
  });

  test('without a last-4 the new account carries the bank label the card '
      'showed', () async {
    await seed('g5', payload(last4: null));
    final shown = (await c.read(reviewQueueProvider.future))
        .whereType<MessageCardModel>()
        .single;
    expect(shown.last4, isNull);
    expect(await c.read(reviewActionsProvider).confirmGeneric(shown), isTrue);
    final a =
        (await db
                .customSelect(
                  'SELECT a.label, a.last4 FROM transactions t '
                  'JOIN accounts a ON a.id = t.account_id',
                )
                .getSingle())
            .data;
    expect(a['last4'], isNull);
    expect(a['label'], shown.bankLabel);
  });

  test(
    'SMS-AUTO: the card carries the stored message text for display',
    () async {
      await seed('g5', payload());
      final shown = (await c.read(reviewQueueProvider.future))
          .whereType<MessageCardModel>()
          .single;
      expect(shown.originalText, 'SYNTHETIC body raw1');
    },
  );

  test('an incomplete suggestion is never saved by confirm', () async {
    await seed('g3', payload(complete: false));
    expect(
      await c.read(reviewActionsProvider).confirmGeneric(card('g3')),
      isFalse,
    );
    final n = await db
        .customSelect('SELECT count(*) AS n FROM transactions')
        .getSingle();
    expect(n.read<int>('n'), 0);
    expect((await ReviewItemsDao(db).byId('g3'))!.resolvedAt, isNull);
  });

  test('the template sample is the stored message, read on request', () async {
    final s = await c.read(reviewActionsProvider).templateSample('raw1');
    expect(s, isNotNull);
    expect(s!.sender, 'SYNTH-BANK');
    expect(s.channel, 'sms');
    expect(s.toString(), isNot(contains('SYNTHETIC')));
  });
}
