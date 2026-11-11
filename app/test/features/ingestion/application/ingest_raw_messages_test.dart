// T-046: IngestRawMessages on an encrypted database with fakes for the
// ports (design note §14). Acceptance criteria are named "AC1".."AC3" in
// the titles. All messages are synthetic.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/daos/capture_controls_dao.dart';
import 'package:zaghlol/core/db/daos/transactions_dao.dart';
import 'package:zaghlol/core/db/db_errors.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../support/ingest_harness.dart';

const String purchase = 'ZBANK: Purchase EGP 120.50 at Synth Shop card *4321';
const String purchaseNotif = 'Purchase EGP 120.50 at Synth Shop';

void main() {
  late IngestWorld w;

  setUp(() async => w = await IngestWorld.open());
  tearDown(() => w.close());

  Future<int> txnCount() => w.count('transactions');

  group('AC1: same SMS twice → one transaction (dedupe 1)', () {
    test('in one batch', () async {
      final r = await w.run([sms('d1', purchase), sms('d2', purchase)]);
      expect(r.outcomes['d1'], isA<IngestInserted>());
      expect(r.outcomes['d2'], isA<IngestDuplicate>());
      expect(r.ackable, ['d1', 'd2']);
      expect(await txnCount(), 1);
      expect(await w.count('raw_messages'), 1);
      expect(w.diag.counts['ING_DUP_HASH'], 1);
    });

    test('in two batches, also with Arabic-Indic digits and other '
        'whitespace in the copy', () async {
      await w.run([sms('d1', purchase)]);
      final r = await w.run([
        sms(
          'd2',
          'ZBANK:  Purchase EGP ١٢٠٫٥٠ at Synth\u00a0Shop card *٤٣٢١',
          rx: t0 + 3600000,
        ),
      ]);
      expect(r.outcomes['d2'], isA<IngestDuplicate>());
      expect(r.ackable, ['d2']);
      expect(await txnCount(), 1);
    });

    test('commit, then the ack is lost: the re-delivery is a duplicate and '
        'ackable', () async {
      final first = await w.run([sms('d1', purchase)]);
      expect(first.ackable, ['d1']);
      final again = await w.run([sms('d1', purchase)]);
      expect(again.outcomes['d1'], isA<IngestDuplicate>());
      expect(again.ackable, ['d1']);
      expect(await txnCount(), 1);
    });

    test(
      'a repeated delivery id in one batch keeps the first outcome',
      () async {
        final r = await w.run([sms('d1', purchase), sms('d1', purchase)]);
        expect(r.outcomes, hasLength(1));
        expect(r.ackable, ['d1']);
      },
    );
  });

  group('AC2: SMS + notification of one payment → one transaction', () {
    test('SMS first: the notification attaches, no new row', () async {
      final a = await w.run([sms('s', purchase)]);
      final txnId = (a.outcomes['s']! as IngestInserted).txnId;
      final b = await w.run([notif('n', purchaseNotif, rx: t0 + 40000)]);
      expect(b.outcomes['n'], isA<IngestMergedCrossChannel>());
      expect((b.outcomes['n']! as IngestMergedCrossChannel).txnId, txnId);
      expect(await txnCount(), 1);
      expect(await w.count('raw_messages', "parse_status = 'parsed'"), 2);
      final t = (await w.txns()).single;
      expect(t['source'], 'sms');
      expect(t['acc_last4'], '4321');
    });

    test('notification first (no last-4): the SMS attaches and moves the '
        'transaction to the card account (PO Q1, provisional)', () async {
      final a = await w.run([notif('n', purchaseNotif)]);
      expect(a.outcomes['n'], isA<IngestInserted>());
      expect((await w.txns()).single['acc_last4'], isNull);
      final b = await w.run([sms('s', purchase, rx: t0 + 30000)]);
      expect(b.outcomes['s'], isA<IngestMergedCrossChannel>());
      final t = (await w.txns()).single;
      expect(t['acc_last4'], '4321');
      expect(t['source'], 'notification');
      expect(b.changedAccountIds, hasLength(2), reason: 'old and new account');
    });

    test('both in one batch, either order', () async {
      final r = await w.run([
        sms('s1', purchase),
        notif('n1', purchaseNotif, rx: t0 + 5000),
        notif('n2', 'Purchase EGP 99.00 at Synth Shop', rx: t0 + 3600000),
        sms(
          's2',
          'ZBANK: Purchase EGP 99.00 at Synth Shop card *4321',
          rx: t0 + 3600000 + 1000,
        ),
      ]);
      expect(r.outcomes['n1'], isA<IngestMergedCrossChannel>());
      expect(r.outcomes['s2'], isA<IngestMergedCrossChannel>());
      expect(await txnCount(), 2);
      expect(
        [for (final t in await w.txns()) t['acc_last4']],
        ['4321', '4321'],
      );
    });

    test('phone clock 3 h off from the bank time: the raws\' receive times '
        'still pair them', () async {
      // The SMS carries the bank's time 09:00 local; the phone says 12:00
      // local at receipt (t0 = 10:00Z = 12:00 Cairo). The notification has
      // no time, so its occurred_at is the phone's.
      final a = await w.run([
        sms(
          's',
          'ZBANK: 09:00 Purchase EGP 120.50 at Synth Shop card *4321',
          rx: t0,
        ),
      ]);
      expect(a.outcomes['s'], isA<IngestInserted>());
      final b = await w.run([notif('n', purchaseNotif, rx: t0 + 60000)]);
      expect(b.outcomes['n'], isA<IngestMergedCrossChannel>());
      expect(await txnCount(), 1);
    });

    test('outside the window on both clocks → two transactions', () async {
      await w.run([sms('s', purchase)]);
      final b = await w.run([
        notif('n', purchaseNotif, rx: t0 + 3 * 60000 + 1),
      ]);
      expect(b.outcomes['n'], isA<IngestInserted>());
      expect(await txnCount(), 2);
    });

    test('same source, different body → never merged (EC-02)', () async {
      await w.run([sms('s1', purchase)]);
      await w.run([
        sms('s2', 'ZBANK: Purchase EGP 120.50 at Other Shop card *4321'),
      ]);
      expect(await txnCount(), 2);
    });

    test('different last-4 on both sides → not merged', () async {
      await w.run([sms('s1', purchase)]);
      // A notification can't carry a last-4 in this registry; use an SMS
      // from a second sender id of another channel: shortcut message.
      final r = await w.run([
        IncomingMessage(
          deliveryId: 'x',
          channel: 'shortcut_message',
          source: zbankSms,
          body: 'ZBANK: Purchase EGP 120.50 at Synth Shop card *9999',
          receivedAtMs: t0 + 1000,
          origin: MessageOrigin.spool,
        ),
      ]);
      expect(r.outcomes['x'], isA<IngestInserted>());
      expect(await txnCount(), 2);
    });

    test('declined and posted are never merged', () async {
      await w.run([
        sms('d', 'ZBANK: Declined EGP 120.50 at Synth Shop card *4321'),
      ]);
      final r = await w.run([notif('n', purchaseNotif, rx: t0 + 1000)]);
      expect(r.outcomes['n'], isA<IngestInserted>());
      final statuses = [for (final t in await w.txns()) t['status']]..sort();
      expect(statuses, ['declined', 'posted']);
    });

    test('a soft-deleted target absorbs its second copy and stays '
        'deleted', () async {
      final a = await w.run([sms('s', purchase)]);
      final id = (a.outcomes['s']! as IngestInserted).txnId;
      await TransactionsDao(w.db).softDelete(id, at: t0 + 2000);
      final before = (await w.txns()).single;
      final b = await w.run([notif('n', purchaseNotif, rx: t0 + 3000)]);
      expect(b.outcomes['n'], isA<IngestMergedCrossChannel>());
      expect(await txnCount(), 1);
      expect((await w.txns()).single['deleted_at'], isNotNull);
      expect((await w.txns()).single, before, reason: 'attach only');
    });

    test('a user-verified target is never modified', () async {
      await w.run([notif('n', purchaseNotif)]);
      final id = (await w.txns()).single['id']! as String;
      await w.db.customStatement(
        'UPDATE transactions SET is_user_verified = 1, merchant_raw = NULL, '
        'merchant_norm = NULL WHERE id = ?',
        [id],
      );
      final before = (await w.txns()).single;
      final r = await w.run([sms('s', purchase, rx: t0 + 1000)]);
      expect(r.outcomes['s'], isA<IngestMergedCrossChannel>());
      final after = (await w.txns()).single;
      expect(after, before);
    });

    test('several candidates → new transaction and a low_confidence item '
        '(possibleDuplicate, Lead L1)', () async {
      await w.run([sms('s1', purchase)]);
      await w.run([
        sms(
          's2',
          'ZBANK: Purchase EGP 120.50 at Synth Shop card *4321 bal egp 5.00',
          rx: t0 + 20000,
        ),
      ]);
      expect(await txnCount(), 2, reason: 'same source: kept (EC-02)');
      final r = await w.run([notif('n', purchaseNotif, rx: t0 + 10000)]);
      final txnId = (r.outcomes['n']! as IngestInserted).txnId;
      expect(await txnCount(), 3);
      final item = (await w.reviews()).single;
      expect(item['kind'], 'low_confidence');
      expect(item['txn_id'], txnId);
      final payload = jsonDecode(item['payload']! as String) as Map;
      expect(payload['reason'], 'possibleDuplicate');
      expect((payload['candidateTxnIds'] as List).toSet(), hasLength(2));
    });
  });

  group('AC3: crash before commit → no duplicate (NFR-REL-01)', () {
    test('a failure at every step of the batch rolls everything back; '
        're-delivery then stores exactly one transaction', () async {
      final batch = [
        sms('s', purchase),
        notif('n', purchaseNotif, rx: t0 + 1000),
        sms('u', 'ZBANK: something unknown'),
        sms('b', 'ZBANK: Balance EGP 50.00 acct *1111'),
      ];
      var step = 1;
      while (true) {
        FaultyStore? faulty;
        final useCase = w.useCase(
          wrap: (inner) => faulty = FaultyStore(inner, failAt: step),
        );
        Object? error;
        try {
          await useCase(batch);
        } on Object catch (e) {
          error = e;
        }
        if (!faulty!.fired) {
          expect(error, isNull);
          break;
        }
        expect(error, isA<IngestBatchFailed>(), reason: 'step $step');
        expect((error! as IngestBatchFailed).code, 'DB_WRITE_FAILED');
        expect(await w.count('raw_messages'), 0, reason: 'step $step');
        expect(await txnCount(), 0, reason: 'step $step');
        expect(await w.count('review_items'), 0, reason: 'step $step');
        expect(await w.count('accounts'), 0, reason: 'step $step');
        expect(await w.count('account_balances'), 0, reason: 'step $step');
        expect(w.events, isEmpty, reason: 'no event on failure');
        step++;
      }
      expect(step, greaterThan(10), reason: 'every step was exercised');
      // The last loop ran without a fault and committed; run once more as a
      // re-delivery.
      final again = await w.run(batch);
      expect(again.outcomes.values.whereType<IngestDuplicate>(), hasLength(4));
      expect(await txnCount(), 1);
      expect(await w.count('raw_messages'), 4);
    });

    test(
      'a busy database at BEGIN: IngestBatchFailed, nothing acked',
      () async {
        final useCase = w.useCase(
          wrap: (inner) => FaultyStore(inner, failAt: 1),
        );
        await expectLater(
          useCase([sms('s', purchase)]),
          throwsA(
            isA<IngestBatchFailed>().having(
              (e) => e.isTransient,
              'transient',
              true,
            ),
          ),
        );
      },
    );
  });

  group('event → transaction (parsing-engine §6 table)', () {
    final cases = <(String, String, String, String?)>[
      // body, direction, status, account kind (new account)
      (purchase, 'expense', 'posted', 'debit'),
      (
        'ZBANK: USD 10.00 charged EGP 500.00 card *4321',
        'expense',
        'posted',
        'debit',
      ),
      ('ZBANK: ATM EGP 1000.00 card *4321', 'expense', 'posted', 'debit'),
      ('ZBANK: Installment EGP 300.00 card *4321', 'expense', 'posted', 'bnpl'),
      (
        'ZBANK: Hold EGP 75.00 at Synth Shop card *4321',
        'expense',
        'pending',
        'debit',
      ),
      (
        'ZBANK: Settled EGP 75.00 at Synth Shop card *4321',
        'expense',
        'posted',
        'debit',
      ),
      (
        'ZBANK: Declined EGP 75.00 at Synth Shop card *4321',
        'expense',
        'declined',
        'account',
      ),
      (
        'ZBANK: Sent EGP 200.00 to Synth Person acct *5555',
        'transfer_out',
        'posted',
        'account',
      ),
      (
        'ZBANK: Received EGP 200.00 from Synth Person acct *5555',
        'transfer_in',
        'posted',
        'account',
      ),
      (
        'ZBANK: InstaPay EGP 150.00 to synth.user@zpay acct *5555',
        'transfer_out',
        'posted',
        'account',
      ),
      (
        'ZBANK: InstaPay in EGP 150.00 from synth.other@zpay acct *5555',
        'transfer_in',
        'posted',
        'account',
      ),
      (
        'ZBANK: Card payment EGP 2000.00 card *4321',
        'transfer_out',
        'posted',
        'credit',
      ),
      (
        'ZBANK: Wallet topup EGP 100.00 acct *5555',
        'transfer_out',
        'posted',
        'wallet',
      ),
      ('ZBANK: Salary EGP 15000.00 acct *5555', 'income', 'posted', 'account'),
      ('ZBANK: Refund EGP 75.00 card *4321', 'refund', 'posted', 'account'),
      ('ZBANK: Reversal EGP 75.00 card *4321', 'refund', 'posted', 'account'),
      ('ZBANK: Fee EGP 5.00 card *4321', 'fee', 'posted', 'account'),
    ];
    for (final (body, direction, status, kind) in cases) {
      test('${body.split(' ').skip(1).take(2).join(' ')} → $direction, '
          '$status', () async {
        final r = await w.run([sms('m', body)]);
        expect(r.outcomes['m'], isA<IngestInserted>());
        final t = (await w.txns()).single;
        expect(t['direction'], direction);
        expect(t['status'], status);
        expect(t['dedupe_key'], startsWith('d1|zbank|$direction|EGP|'));
        final acc = (await w.rows('SELECT kind FROM accounts')).single;
        expect(acc['kind'], kind);
      });
    }

    test('FX purchase keeps the original amount, never converted', () async {
      await w.run([sms('m', 'ZBANK: USD 10.00 charged EGP 500.00 card *4321')]);
      final t = (await w.txns()).single;
      expect(t['amount_minor'], 50000);
      expect(t['currency'], 'EGP');
      expect(t['original_amount_minor'], 1000);
      expect(t['original_currency'], 'USD');
    });

    test('IPA counterparty is stored as ipa', () async {
      await w.run([
        sms('m', 'ZBANK: InstaPay EGP 150.00 to synth.user@zpay acct *5555'),
      ]);
      final t = (await w.txns()).single;
      expect(t['counterparty_kind'], 'ipa');
      expect(t['counterparty_value'], 'synth.user@zpay');
    });

    test('balance_only → no transaction, raw parsed, balance recorded '
        '(FU-078: negative stored)', () async {
      final r = await w.run([
        sms('m', 'ZBANK: Balance EGP -500.25 acct *1111'),
      ]);
      expect(r.outcomes['m'], isA<IngestBalanceOnly>());
      expect(await txnCount(), 0);
      expect((await w.raws()).single['parse_status'], 'parsed');
      final b = (await w.rows('SELECT * FROM account_balances')).single;
      expect(b['balance_minor'], -50025);
      expect(b['currency'], 'EGP');
      expect(r.event, isNotNull, reason: 'a balance changed');
    });

    test('fx_conversion (no handler until T-089) → raw reparse_pending, '
        'outcome deferred, nothing else', () async {
      final r = await w.run([
        sms('m', 'ZBANK: Converted USD 10.00 to EGP 500.00 acct *5555'),
      ]);
      expect(r.outcomes['m'], isA<IngestDeferred>());
      expect((await w.raws()).single['parse_status'], 'reparse_pending');
      expect(await txnCount(), 0);
      expect(await w.count('review_items'), 0);
      expect(r.ackable, ['m']);
    });

    test('a transfer template without a direction → review', () async {
      final r = await w.run([sms('m', 'ZBANK: Move EGP 10.00 acct *5555')]);
      expect(r.outcomes['m'], isA<IngestReview>());
      expect(await txnCount(), 0);
    });

    test(
      'unrecognized → raw review + unrecognized item (codes only)',
      () async {
        final r = await w.run([sms('m', 'ZBANK: something new $canary')]);
        final o = r.outcomes['m']! as IngestReview;
        expect(o.reviewKind, 'unrecognized');
        final item = (await w.reviews()).single;
        expect(item['raw_message_id'], o.rawId);
        expect(jsonDecode(item['payload']! as String), {
          'reason': 'noTemplateMatched',
          'institutionCode': 'zbank',
        });
      },
    );

    test('low confidence → saved and a low_confidence item', () async {
      final r = await w.run([
        sms('m', 'ZBANK: Maybe EGP 10.00 at Synth Shop card *4321'),
      ]);
      final txnId = (r.outcomes['m']! as IngestInserted).txnId;
      final item = (await w.reviews()).single;
      expect(item['kind'], 'low_confidence');
      expect(item['txn_id'], txnId);
      final payload = jsonDecode(item['payload']! as String) as Map;
      expect(payload['reason'], 'lowConfidence');
      expect(payload['confidencePermille'], 800);
    });

    test('balance on a purchase: stored on the account and as '
        'balance_after', () async {
      await w.run([
        sms(
          'm',
          'ZBANK: Purchase EGP 10.00 at Synth Shop card *4321 bal egp 990.00',
        ),
      ]);
      final t = (await w.txns()).single;
      expect(t['balance_after_minor'], 99000);
      final b = (await w.rows('SELECT * FROM account_balances')).single;
      expect(b['balance_minor'], 99000);
      expect(b['source_txn_id'], t['id']);
    });
  });

  group('pending / settled (A-63, EC-54)', () {
    const hold = 'ZBANK: Hold EGP 100.00 at Synth Shop card *4321';
    String settled(String amount) =>
        'ZBANK: Settled EGP $amount at Synth Shop card *4321';

    test('pending → settled: one transaction, settled amount, posted, '
        'dedupe key updated', () async {
      await w.run([sms('p', hold)]);
      final r = await w.run([sms('s', settled('104.00'), rx: t0 + 86400000)]);
      expect(r.outcomes['s'], isA<IngestMergedPending>());
      final t = (await w.txns()).single;
      expect(t['status'], 'posted');
      expect(t['amount_minor'], 10400);
      expect(t['dedupe_key'], 'd1|zbank|expense|EGP|10400');
      expect(w.diag.counts['ING_MERGE_PENDING'], 1);
    });

    test('settled → pending (symmetric): one transaction, posted', () async {
      await w.run([sms('s', settled('104.00'), rx: t0 + 3600000)]);
      final r = await w.run([sms('p', hold)]);
      expect(r.outcomes['p'], isA<IngestMergedPending>());
      final t = (await w.txns()).single;
      expect(t['status'], 'posted');
      expect(t['amount_minor'], 10400);
    });

    test('±5 % boundary: 5 % merges, 5.01 % does not', () async {
      await w.run([sms('p', hold)]);
      final r = await w.run([sms('s', settled('105.00'), rx: t0 + 60000)]);
      expect(r.outcomes['s'], isA<IngestMergedPending>());

      await w.run([
        sms('p2', 'ZBANK: Hold EGP 100.00 at Other Shop card *4321'),
      ]);
      final r2 = await w.run([
        sms(
          's2',
          'ZBANK: Settled EGP 105.01 at Other Shop card *4321',
          rx: t0 + 60000,
        ),
      ]);
      expect(r2.outcomes['s2'], isA<IngestInserted>());
    });

    test('older than 7 days → not merged', () async {
      await w.run([sms('p', hold)]);
      final r = await w.run([
        sms('s', settled('100.00'), rx: t0 + 7 * 86400000 + 3 * 60000),
      ]);
      expect(r.outcomes['s'], isA<IngestInserted>());
    });

    test('a different merchant → not merged', () async {
      await w.run([sms('p', hold)]);
      final r = await w.run([
        sms(
          's',
          'ZBANK: Settled EGP 100.00 at Other Shop card *4321',
          rx: t0 + 60000,
        ),
      ]);
      expect(r.outcomes['s'], isA<IngestInserted>());
    });

    test('several pending → the closest amount, then the oldest', () async {
      await w.run([
        sms('p1', 'ZBANK: Hold EGP 100.00 at Synth Shop card *4321'),
        sms(
          'p2',
          'ZBANK: Hold EGP 102.00 at Synth Shop card *4321',
          rx: t0 + 1000,
        ),
      ]);
      final r = await w.run([sms('s', settled('102.50'), rx: t0 + 60000)]);
      final merged = (r.outcomes['s']! as IngestMergedPending).txnId;
      final t = (await w.rows(
        'SELECT amount_minor, status FROM transactions WHERE id = ?',
        [merged],
      )).single;
      expect(t['amount_minor'], 10250);
      final other = await w.rows(
        "SELECT amount_minor FROM transactions WHERE status = 'pending'",
      );
      expect(other.single['amount_minor'], 10000);
    });

    test('a user-verified pending only changes status, plus a '
        'settledAmountDiffers item', () async {
      await w.run([sms('p', hold)]);
      await w.db.customStatement(
        'UPDATE transactions SET is_user_verified = 1',
      );
      await w.run([sms('s', settled('103.00'), rx: t0 + 60000)]);
      final t = (await w.txns()).single;
      expect(t['status'], 'posted');
      expect(t['amount_minor'], 10000);
      final payload =
          jsonDecode((await w.reviews()).single['payload']! as String) as Map;
      expect(payload['reason'], 'settledAmountDiffers');
    });
  });

  group('generic results (FU-080, A-66)', () {
    const generic = 'You paid EGP 50.00 at Synth Cafe';

    test('an unknown financial sender → review new_sender, nothing '
        'saved', () async {
      final r = await w.run([sms('g', generic, source: 'MYBANK')]);
      expect((r.outcomes['g']! as IngestReview).reviewKind, 'new_sender');
      expect(await txnCount(), 0);
      final payload =
          jsonDecode((await w.reviews()).single['payload']! as String) as Map;
      expect(payload['generic'], isTrue);
      expect(payload['amount'], {'minor': 5000, 'currency': 'EGP'});
    });

    test('always capture with 2 confirmations → still review; with 3 → '
        'auto-saved with a low_confidence item; confirmed_count '
        'unchanged', () async {
      final dao = CaptureControlsDao(w.db);
      await dao.setAlwaysCapture(
        sender: 'mybank',
        channel: 'sms',
        always: true,
        at: t0,
      );
      for (var i = 0; i < 2; i++) {
        await dao.recordConfirmation(sender: 'mybank', channel: 'sms', at: t0);
      }
      final r1 = await w.run([sms('g1', generic, source: 'MYBANK')]);
      expect(r1.outcomes['g1'], isA<IngestReview>());
      await dao.recordConfirmation(sender: 'mybank', channel: 'sms', at: t0);
      final r2 = await w.run([
        sms('g2', 'You paid EGP 51.00 at Synth Cafe', source: 'MYBANK'),
      ]);
      expect(r2.outcomes['g2'], isA<IngestInserted>());
      final t = (await w.txns()).single;
      expect(t['direction'], 'expense');
      expect(t['dedupe_key'], isNull);
      expect(t['acc_inst'], startsWith('g_'));
      final items = await w.reviews();
      expect(items.last['kind'], 'low_confidence');
      expect((await dao.sender('mybank'))!.confirmedCount, 3);
    });
  });

  group('Guard re-check (BR-CAP-01, design note §9)', () {
    test(
      'an ignore rule added after spooling → nothing stored anywhere',
      () async {
        await CaptureControlsDao(w.db).addIgnoreRule(
          id: 'ig1',
          institutionCode: 'zbank',
          last4: '4321',
          channel: 'sms',
          createdAt: t0,
        );
        final r = await w.run([sms('s', purchase)]);
        expect(r.outcomes['s'], isA<IngestDropped>());
        expect((r.outcomes['s']! as IngestDropped).reason, 'ignored_card');
        expect(r.ackable, ['s']);
        for (final table in [
          'raw_messages',
          'review_items',
          'transactions',
          'transactions_fts_src',
          'accounts',
        ]) {
          expect(await w.count(table), 0, reason: table);
        }
        expect(w.diag.counts.keys, ['ING_DROP_IGNORED_CARD']);
        expect(r.event, isNull);
      },
    );

    test('a user part the Guard can not express → the bad row is left '
        'out; the valid rules still drop', () async {
      await CaptureControlsDao(w.db).addIgnoreRule(
        id: 'ig1',
        institutionCode: 'zbank',
        channel: 'sms',
        createdAt: t0,
      );
      // A 2-digit card rule: valid for the schema, refused by the Guard's
      // user-part builder (4 digits only), so the whole build fails.
      await CaptureControlsDao(w.db).addIgnoreRule(
        id: 'ig2',
        institutionCode: 'otherbank',
        last4: '12',
        channel: 'sms',
        createdAt: t0,
      );
      final r = await w.run([sms('s', purchase)]);
      expect((r.outcomes['s']! as IngestDropped).reason, 'ignored_institution');
      expect(await w.count('raw_messages'), 0);
    });

    group('F1: the fallback keeps the user\'s keeps', () {
      Future<void> badRule() => CaptureControlsDao(w.db).addIgnoreRule(
        id: 'bad',
        institutionCode: 'otherbank',
        last4: '12',
        channel: 'sms',
        createdAt: t0,
      );

      Future<void> alwaysCoop() async {
        final dao = CaptureControlsDao(w.db);
        await dao.setAlwaysCapture(
          sender: 'coopxyz',
          channel: 'sms',
          always: true,
          at: t0,
        );
        for (var i = 0; i < 3; i++) {
          await dao.recordConfirmation(
            sender: 'coopxyz',
            channel: 'sms',
            at: t0,
          );
        }
      }

      // The security reviewer's probe: always-capture COOPXYZ plus one
      // 2-digit rule for an unrelated bank.
      for (final bad in [false, true]) {
        test('always-capture sender, bad row: $bad → stored, not '
            'dropped', () async {
          await alwaysCoop();
          if (bad) await badRule();
          final r = await w.run([
            sms('c1', 'Coop: 50.00 deducted', source: 'COOPXYZ'),
            sms(
              'c2',
              'You paid EGP 50.00 at Synth Cafe',
              source: 'COOPXYZ',
              rx: t0 + 1000,
            ),
          ]);
          for (final id in ['c1', 'c2']) {
            expect(r.outcomes[id], isNot(isA<IngestDropped>()), reason: id);
          }
          expect(r.ackable, ['c1', 'c2']);
          expect(await w.count('raw_messages'), 2);
          expect(await w.count('review_items'), greaterThanOrEqualTo(2));
        });
      }

      test('a custom-template sender with a bad row → stored', () async {
        await badRule();
        await w.db.customStatement(
          'INSERT INTO custom_templates (id, sender, channel, template_json, '
          "sample_hash, created_at) VALUES ('ct1', 'COOPXYZ', 'sms', '{}', "
          "'${'a' * 64}', $t0)",
        );
        final r = await w.run([
          sms('c', 'Coop: 50.00 deducted', source: 'COOPXYZ'),
        ]);
        expect(r.outcomes['c'], isNot(isA<IngestDropped>()));
        expect(await w.count('raw_messages'), 1);
      });

      test('over the rule cap: every rule is checked in the database, '
          'keeps still kept', () async {
        await alwaysCoop();
        await CaptureControlsDao(w.db).addIgnoreRule(
          id: 'ig1',
          institutionCode: 'zbank',
          channel: 'sms',
          createdAt: t0,
        );
        // 1,000 more valid card rules: over maxGuardIgnoreRules.
        await w.db.transaction(() async {
          for (var i = 0; i < 1000; i++) {
            await w.db.customStatement(
              'INSERT INTO ignore_rules (id, institution_code, last4, '
              "channel, created_at) VALUES ('x$i', 'otherbank', "
              "'${i.toString().padLeft(4, '0')}', 'sms', $t0)",
            );
          }
        });
        final r = await w.run([
          sms('z', purchase),
          sms('c', 'Coop: 50.00 deducted', source: 'COOPXYZ'),
          sms('x', purchase, source: 'SPAMMER'),
        ]);
        expect((r.outcomes['z']! as IngestDropped).reason, 'ignored_rule');
        expect(r.outcomes['c'], isNot(isA<IngestDropped>()));
        expect((r.outcomes['x']! as IngestDropped).reason, 'not_financial');
      });
    });

    test('OTP → dropped before any write', () async {
      final r = await w.run([sms('o', 'ZBANK: your OTP is 482913 $canary')]);
      expect(r.outcomes['o'], isA<IngestDropped>());
      expect(await w.count('raw_messages'), 0);
      expect(await w.count('review_items'), 0);
    });

    test('an unknown sender → dropped not_financial', () async {
      final r = await w.run([sms('x', purchase, source: 'SPAMMER')]);
      expect((r.outcomes['x']! as IngestDropped).reason, 'not_financial');
    });

    test('an invalid Guard base: CONFIG_INVALID before the transaction, '
        'nothing stored', () async {
      final useCase = w.useCase(guardBase: BytesGuardBase(utf8.encode('{}')));
      await expectLater(
        useCase([sms('s', purchase)]),
        throwsA(
          isA<IngestBatchFailed>().having(
            (e) => e.code,
            'code',
            'CONFIG_INVALID',
          ),
        ),
      );
      expect(await w.count('raw_messages'), 0);
    });
  });

  group('per-message failures (design note §10)', () {
    test('a constraint failure stores that message alone for review; the '
        'batch continues', () async {
      final useCase = w.useCase(
        hooks: [
          ThrowingHook(DbWriteException(DbWriteException.constraintCheck)),
        ],
      );
      final r = await useCase([
        sms('a', purchase),
        sms('b', 'ZBANK: ATM EGP 100.00 card *4321'),
      ]);
      expect((r.outcomes['a']! as IngestReview).reviewKind, 'unrecognized');
      expect(r.outcomes['b'], isA<IngestInserted>());
      expect(await txnCount(), 1);
      final item = (await w.reviews()).single;
      expect(jsonDecode(item['payload']! as String), {
        'reason': 'ingestFailed',
        'code': 'DB_CONSTRAINT_CHECK',
      });
      expect(w.diag.counts['ING_MSG_FAILED'], 1);
    });

    test('an unexpected error (INGEST_INTERNAL) rolls the message back and '
        'stores it alone for review (CR-1/F2)', () async {
      final useCase = w.useCase(
        hooks: [ThrowingHook(StateError(canary), times: 1 << 30)],
      );
      final r = await useCase([sms('a', purchase)]);
      expect((r.outcomes['a']! as IngestReview).reviewKind, 'unrecognized');
      expect(r.ackable, ['a']);
      expect(await txnCount(), 0);
      expect(await w.count('accounts'), 0);
      expect(await w.count('raw_messages'), 1);
      expect(jsonDecode((await w.reviews()).single['payload']! as String), {
        'reason': 'ingestFailed',
        'code': 'INGEST_INTERNAL',
      });
    });
  });

  group('user-confirmed input (design note §11)', () {
    test('stored user-verified; never merged automatically', () async {
      final r = await w.run([
        IncomingMessage(
          deliveryId: 'u',
          channel: 'paste',
          source: 'clipboard',
          body: purchase,
          receivedAtMs: t0,
          origin: MessageOrigin.userConfirmed,
        ),
      ]);
      expect(
        r.outcomes['u'],
        isA<IngestReview>(),
        reason:
            'share has no '
            'template in the test registry: unrecognized for review',
      );
    });

    test('a share that looks like a stored payment → possibleDuplicate, '
        'nothing written', () async {
      await w.run([notif('n', purchaseNotif)]);
      final before = await w.count('raw_messages');
      final r = await w.run([
        IncomingMessage(
          deliveryId: 'u',
          channel: 'notification',
          source: zbankPackage,
          body: 'Purchase EGP 120.50 at Synth Shop ',
          receivedAtMs: t0 + 1000,
          origin: MessageOrigin.userConfirmed,
        ),
      ]);
      // Same normalised body and sender → dedupe 1 first.
      expect(r.outcomes['u'], isA<IngestDuplicate>());
      final r2 = await w.run([
        IncomingMessage(
          deliveryId: 'u2',
          channel: 'sms',
          source: zbankSms,
          body: purchase,
          receivedAtMs: t0 + 1000,
          origin: MessageOrigin.userConfirmed,
        ),
      ]);
      expect(r2.outcomes['u2'], isA<IngestPossibleDuplicate>());
      expect(await w.count('raw_messages'), before);
      expect(await txnCount(), 1);
    });

    test('a confirmed message with no candidate is stored verified', () async {
      await w.run([
        IncomingMessage(
          deliveryId: 'u',
          channel: 'sms',
          source: zbankSms,
          body: purchase,
          receivedAtMs: t0,
          origin: MessageOrigin.userConfirmed,
        ),
      ]);
      expect((await w.txns()).single['is_user_verified'], 1);
    });
  });

  group('events (design note §10, FU-037)', () {
    test('one TransactionsChanged per committed batch, after the commit, '
        'with account ids and cycle keys', () async {
      final r = await w.run([
        sms('a', purchase),
        sms('b', 'ZBANK: Salary EGP 15000.00 acct *5555'),
      ]);
      await pumpEventQueue();
      expect(w.events, hasLength(1));
      final e = w.events.single as TransactionsChanged;
      expect(e.accountIds, hasLength(2));
      expect(e.cycleKeys, {'2026-11-01'});
      expect(identical(r.event, e), isTrue);
      expect(() => e.accountIds.add('x'), throwsUnsupportedError);
    });

    test('the stored payday decides the cycle key (A-43)', () async {
      await w.db.customStatement(
        'INSERT INTO settings (key, value, updated_at) VALUES '
        "('payday_day', '25', 0)",
      );
      final r = await w.run([sms('a', purchase)]);
      expect(r.event!.cycleKeys, {'2026-10-25'});
    });

    test('payday_eras decide the key: the era in force at the txn date '
        '(T-051, EC-21)', () async {
      await w.db.customStatement(
        'INSERT INTO settings (key, value, updated_at) VALUES '
        "('payday_day', '1', 0), "
        "('payday_eras', '[{\"from\":null,\"day\":25},"
        "{\"from\":\"2026-11-02\",\"day\":1}]', 0)",
      );
      final r = await w.run([sms('a', purchase)]);
      expect(r.event!.cycleKeys, {'2026-10-25'});
    });

    test('nothing changed → no event', () async {
      await w.run([sms('a', purchase)]);
      await pumpEventQueue();
      w.events.clear();
      final r = await w.run([sms('a', purchase)]);
      await pumpEventQueue();
      expect(r.event, isNull);
      expect(w.events, isEmpty);
    });
  });

  group('categorize hook (design note §8)', () {
    test('a user rule committed before the batch applies', () async {
      await w.db.customStatement(
        'INSERT INTO categories (id, name_ar, name_en, icon, color, bucket, '
        "sort) VALUES ('c1', 'أكل', 'Food', 'i', '#000000', 'needs', 1)",
      );
      await w.db.customStatement(
        'INSERT INTO merchant_rules (id, match_kind, match_value, '
        "category_id, created_at) VALUES ('r1', 'merchant_norm', "
        "'synth shop', 'c1', 0)",
      );
      await w.run([sms('a', purchase)]);
      final t = (await w.txns()).single;
      expect(t['category_id'], 'c1');
      expect(t['category_source'], 'user_rule');
    });

    test('no rule → category_source none (no needs_category item)', () async {
      await w.run([sms('a', purchase)]);
      expect((await w.txns()).single['category_source'], 'none');
      expect(await w.count('review_items'), 0);
    });
  });

  group('privacy (design note §12)', () {
    test('a canary body through every outcome never reaches output, '
        'outcomes, results, exceptions, review payloads or diag', () async {
      final printed = <String>[];
      final texts = <String>[];
      await runZoned(
        () async {
          final r = await w.run([
            sms('u', 'ZBANK: unknown $canary text'),
            sms('o', 'ZBANK: your OTP is 123456 $canary'),
            sms('g', 'You paid EGP 5.00 $canary', source: 'MYBANK'),
            sms('x', 'ZBANK: $canary', source: 'SPAM$canary'),
            sms('p', purchase),
            notif('n', purchaseNotif, rx: t0 + 1000),
            sms('d', purchase),
          ]);
          texts
            ..add('$r')
            ..addAll([for (final o in r.outcomes.values) '$o'])
            ..addAll(r.ackable)
            ..add('${r.event}');
          final failing = w.useCase(hooks: [ThrowingHook(StateError(canary))]);
          try {
            await failing([sms('f', 'ZBANK: ATM EGP 1.00 card *4321')]);
          } on Object catch (e) {
            texts.add('$e');
          }
          final failing2 = w.useCase(
            hooks: [
              ThrowingHook(DbWriteException(DbWriteException.constraintCheck)),
            ],
          );
          final r2 = await failing2([
            sms('f2', 'ZBANK: ATM EGP 2.00 card *4321'),
          ]);
          texts.add('$r2');
        },
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => printed.add(line),
        ),
      );
      expect(printed, isEmpty);
      for (final t in texts) {
        expect(t, isNot(contains(canary)));
      }
      for (final item in await w.reviews()) {
        expect('${item['payload']}', isNot(contains(canary)));
      }
      for (final code in w.diag.counts.keys) {
        expect(code, matches(RegExp(r'^ING_[A-Z_]+$')));
      }
      // The body itself is only in raw_messages.body (encrypted DB).
      final bodies = await w.rows(
        'SELECT count(*) AS c FROM raw_messages WHERE body LIKE ?',
        ['%$canary%'],
      );
      expect(bodies.single['c'], 2, reason: 'unrecognized and generic rows');
      final fts = await w.rows(
        'SELECT count(*) AS c FROM transactions_fts_src WHERE '
        'coalesce(merchant, \'\') || coalesce(counterparty, \'\') LIKE ?',
        ['%$canary%'],
      );
      expect(fts.single['c'], 0);
    });
  });

  test('account labels use the registry name in the app language', () async {
    await w.run([sms('a', purchase)]);
    expect(
      (await w.rows('SELECT label FROM accounts')).single['label'],
      'بنك زد التجريبي',
    );
    await w.db.customStatement(
      "INSERT INTO settings (key, value, updated_at) VALUES ('language', 'en', 0)",
    );
    await w.run([sms('b', 'ZBANK: Salary EGP 1.00 acct *5555')]);
    final labels = [
      for (final r in await w.rows('SELECT label FROM accounts ORDER BY label'))
        r['label'],
    ];
    expect(labels, contains('Z Test Bank'));
  });

  test('stored times: occurred_at is UTC, the offset is the zone\'s', () async {
    await w.run([sms('a', purchase)]);
    final t = (await w.txns()).single;
    expect(t['occurred_at'], t0);
    expect(t['occurred_tz_offset_min'], 120);
  });

  test('money columns are integers of the right exponent', () async {
    await w.run([sms('a', purchase)]);
    final t = (await w.txns()).single;
    expect(t['amount_minor'], 12050);
    expect(Money.fromStorage(t['amount_minor']! as int, 'EGP').minor, 12050);
  });

  test('test-only SQL helpers bind values (sanity)', () async {
    expect(await w.count('raw_messages'), 0);
    expect(Variable.withInt(1).value, 1);
  });
}
