@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/export_import/presentation/import_done_screen.dart';
import 'package:zaghlol/features/export_import/presentation/import_ports.dart';
import 'package:zaghlol/features/export_import/presentation/import_source_screen.dart';
import 'package:zaghlol/features/export_import/presentation/import_summary_sheet.dart';
import 'package:zaghlol/features/gold/application/gating.dart';

import '../../../support/golden_matrix.dart';
import 'import_flow_support.dart';

void main() {
  for (final v in [...goldenVariants, ...goldenVariantsScaled]) {
    final lang = v.locale.languageCode;
    final screens = <String, Widget>{
      's67_source': const ImportSourceScreen(),
      's67_summary': Scaffold(
        body: ImportSummarySheet(preview: samplePreview(card: 'CIB')),
      ),
      's67_done': const ImportDoneScreen(
        outcome: ImportOutcome(
          imported: 143,
          autoCategorised: 131,
          needReview: 11,
        ),
        cardName: 'CIB',
      ),
    };
    for (final e in screens.entries) {
      testWidgets('${e.key} golden ${v.name}', (t) async {
        await t.binding.setSurfaceSize(const Size(390, 1100));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final container = ProviderContainer(
          overrides: importOverrides(
            lang,
            picker: FakePicker(null),
            runner: FakeRunner(),
          ),
        );
        addTearDown(container.dispose);
        container
            .read(entitlementStateProvider.notifier)
            .applyVerified(verified: true, status: 'active');
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: host(e.value, lang: lang, scale: v.textScale, dark: v.dark),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('golden-root')),
          matchesGoldenFile('goldens/${e.key}_${v.name}.png'),
        );
      });
    }
  }
}
