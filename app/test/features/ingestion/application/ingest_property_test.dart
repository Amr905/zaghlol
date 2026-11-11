// T-046 §14 property test: 200 fixed seeds. Each seed builds synthetic
// payments (SMS only, notification only, SMS + notification, pending +
// settled), randomly duplicates their messages, shuffles them, splits them
// into random batches and fails random batches before the commit (a fault
// at a random step, then the batch is re-delivered like the spool would).
// The stored projection (account last-4, direction, status, amount,
// currency, count) must equal the expected one. Synthetic data only.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/ingestion/domain/ingest_types.dart';

import '../support/ingest_harness.dart';

const int _day = 86400000;
const int _seedSpan = 30 * _day;

enum _Kind { smsOnly, notifOnly, both, pendingSettled }

String _money(int minor) =>
    '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';

/// Letters only (the merchant group is `[a-z ]`).
String _letters(int n) {
  final out = StringBuffer();
  var x = n;
  do {
    out.writeCharCode(0x61 + x % 26);
    x ~/= 26;
  } while (x > 0);
  return out.toString();
}

void main() {
  late IngestWorld w;

  setUpAll(() async => w = await IngestWorld.open());
  tearDownAll(() => w.close());

  test('200 seeds: shuffled, duplicated, re-batched, randomly failing '
      'deliveries give exactly the expected transactions', () async {
    var failedBatches = 0;
    for (var seed = 0; seed < 200; seed++) {
      final random = Random(seed);
      final base = t0 + seed * _seedSpan;
      final merchant = 'Shop ${_letters(seed)}';
      final payments = 1 + random.nextInt(5);
      final messages = <IncomingMessage>[];
      final expected = <String>[];
      var n = 0;
      String id() => 's$seed-${n++}';
      for (var i = 0; i < payments; i++) {
        final kind = _Kind.values[random.nextInt(_Kind.values.length)];
        // Doubling amounts: no two payments within 5 % of each other.
        final amount = 10000 << i;
        final rx = base + i * 20 * 60000;
        var stored = amount;
        String? last4 = '4321';
        switch (kind) {
          case _Kind.smsOnly:
            messages.add(
              sms(
                id(),
                'ZBANK: Purchase EGP ${_money(amount)} at $merchant card *4321',
                rx: rx,
              ),
            );
          case _Kind.notifOnly:
            last4 = null;
            messages.add(
              notif(
                id(),
                'Purchase EGP ${_money(amount)} at $merchant',
                rx: rx,
              ),
            );
          case _Kind.both:
            messages
              ..add(
                sms(
                  id(),
                  'ZBANK: Purchase EGP ${_money(amount)} at $merchant '
                  'card *4321',
                  rx: rx,
                ),
              )
              ..add(
                notif(
                  id(),
                  'Purchase EGP ${_money(amount)} at $merchant',
                  rx: rx + random.nextInt(90000),
                ),
              );
          case _Kind.pendingSettled:
            stored = amount + amount * random.nextInt(6) ~/ 100;
            messages
              ..add(
                sms(
                  id(),
                  'ZBANK: Hold EGP ${_money(amount)} at $merchant card *4321',
                  rx: rx,
                ),
              )
              ..add(
                sms(
                  id(),
                  'ZBANK: Settled EGP ${_money(stored)} at $merchant '
                  'card *4321',
                  rx: rx + (1 + random.nextInt(3)) * _day,
                ),
              );
        }
        expected.add('${last4 ?? '-'}|expense|posted|$stored|EGP');
      }
      // Exact duplicates (re-delivery, inbox copy) under new delivery ids.
      // An inbox copy carries the provider's receive date, so its time is
      // the original's give or take a few seconds.
      final copies = [
        for (final m in messages)
          if (random.nextInt(10) < 3)
            IncomingMessage(
              deliveryId: id(),
              channel: m.channel,
              source: m.source,
              body: m.body,
              receivedAtMs: m.receivedAtMs + random.nextInt(5000),
              origin: MessageOrigin.inboxScan,
            ),
      ];
      final all = [...messages, ...copies]..shuffle(random);

      var at = 0;
      while (at < all.length) {
        final size = 1 + random.nextInt(4);
        final batch = all.sublist(at, min(at + size, all.length));
        at += batch.length;
        if (random.nextInt(4) == 0) {
          FaultyStore? faulty;
          final failing = w.useCase(
            wrap: (inner) =>
                faulty = FaultyStore(inner, failAt: 1 + random.nextInt(20)),
          );
          try {
            await failing(batch);
          } on IngestBatchFailed {
            failedBatches++;
          }
          if (faulty!.fired) {
            // Re-delivered after the failure.
            await w.run(batch);
          }
        } else {
          await w.run(batch);
        }
      }

      final rows = await w.rows(
        'SELECT a.last4, t.direction, t.status, t.amount_minor, t.currency '
        'FROM transactions t JOIN accounts a ON a.id = t.account_id '
        'WHERE t.occurred_at >= ? AND t.occurred_at < ?',
        [base, base + _seedSpan],
      );
      final got = [
        for (final r in rows)
          '${r['last4'] ?? '-'}|${r['direction']}|${r['status']}|'
              '${r['amount_minor']}|${r['currency']}',
      ]..sort();
      expect(got, expected..sort(), reason: 'seed $seed');
    }
    expect(failedBatches, greaterThan(20), reason: 'faults were exercised');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
