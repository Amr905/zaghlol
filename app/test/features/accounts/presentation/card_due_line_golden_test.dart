@Tags(['golden'])
library;

// T-249 (FU-303): the card detail's due line in its three states (due,
// partial, paid) in ar/en, light/dark. PNGs come from the app-regen workflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/accounts/domain/card_due.dart';
import 'package:zaghlol/features/accounts/presentation/card_detail/card_detail.dart';
import 'package:zaghlol/features/recurring/data/card_dues_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../support/golden_matrix.dart';
import 'card_detail_test.dart' as base;

CardDue _due(int paid) => CardDue(
  currency: 'EGP',
  noticeAtMs: 1,
  amountDueMinor: 10000,
  minDueMinor: 3000,
  dueDate: CivilDate(2026, 11, 25),
  paidMinor: paid,
);

void main() {
  const states = {'due': 0, 'partial': 1000, 'paid': 3000};
  for (final v in goldenVariants) {
    for (final e in states.entries) {
      testWidgets('card detail due line ${e.key} ${v.name}', (t) async {
        await t.binding.setSurfaceSize(const Size(390, 1500));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(
          base.host(
            const CardDetailScreen(accountId: 'a1'),
            overrides: [
              ...base.detailOverrides(),
              cardDueProvider.overrideWith((ref, id) async => _due(e.value)),
            ],
            locale: v.locale,
            dark: v.dark,
          ),
        );
        await t.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../../../goldens/card_detail_due_${e.key}_${v.name}.png',
          ),
        );
      });
    }
  }
}
