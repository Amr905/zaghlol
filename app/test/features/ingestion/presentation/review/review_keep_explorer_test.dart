// Batch 32 explorer bug: Keep on a doubtful generic card saved nothing.
// The bodies are the synthetic ones the device explorer sends (known bank,
// unfamiliar wording), through the real ingest -> review item -> keep path.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/db/app_database_providers.dart';
import 'package:zaghlol/features/ingestion/presentation/review/review_models.dart';
import 'package:zaghlol/features/ingestion/presentation/review/review_providers.dart';
import 'package:zaghlol/ingestion/bundled_registry.dart';

import 'package:zaghlol_parsing/zaghlol_parsing.dart' show Registry;

import '../../support/ingest_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bodies = <(String, String)>[
    (
      'NBE',
      'Dear customer, EGP 311.00 was debited from your account at CARREFOUR '
          'MAADI on 12/11/2026',
    ),
    (
      'NBE',
      'Dear customer, EGP 322.00 was debited from your account at SPINNEYS '
          'ZAMALEK on 13/11/2026',
    ),
    (
      'NBE',
      'Dear customer, EGP 333.00 was credited to your account on 14/11/2026',
    ),
    (
      'NBE',
      'Dear customer, EGP 344.00 on your account *4567 at SOME SHOP 15/11/2026',
    ),
    (
      'HSBC',
      'Dear customer, EGP 355.00 was debited from your card at KOSHARY '
          'TAHRIR on 16/11/2026',
    ),
  ];

  test(
    'every doubtful card that offers Keep saves exactly what it shows',
    () async {
      final dir = Directory('assets/registry');
      expect(dir.existsSync(), isTrue);
      final registry = await _bundled();
      final w = await IngestWorld.open();
      final c = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWith((ref) async => w.db)],
      );
      addTearDown(() async {
        c.dispose();
        await w.close();
      });
      final uc = w.useCase(registry: registry);
      var i = 0;
      for (final (sender, body) in bodies) {
        await uc([sms('m${i++}', body, source: sender)]);
      }
      final cards = (await c.read(reviewQueueProvider.future))
          .whereType<MessageCardModel>()
          .toList();
      final keepable = cards.where((m) => m.txnId == null && m.offersKeep);
      expect(keepable, isNotEmpty, reason: 'the explorer saw one enabled Keep');
      for (final card in keepable) {
        final before = await w.count('transactions');
        final saved = await c
            .read(reviewActionsProvider)
            .confirmGeneric(card, keep: true);
        expect(saved, isTrue, reason: 'Keep on ${card.amount}');
        expect(await w.count('transactions'), before + 1);
        final t = (await w.txns()).singleWhere(
          (r) => r['amount_minor'] == card.amount!.minor,
        );
        expect(t['amount_minor'], card.amount!.minor);
        expect(t['currency'], card.amount!.currency.code);
      }
    },
  );
}

Future<Registry> _bundled() => preloadBundledRegistry();
