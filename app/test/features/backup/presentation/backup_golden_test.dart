@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/backup/presentation/backup_screen.dart';
import 'package:zaghlol/features/backup/presentation/restore_flow.dart';
import 'package:zaghlol/features/backup/presentation/restore_screen.dart';

import '../../../support/golden_matrix.dart';
import 'backup_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14);
  for (final v in [...goldenVariants, ...goldenVariantsScaled]) {
    final lang = v.locale.languageCode;
    testWidgets('S-66 golden ${v.name}', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final gw = FakeGateway()
        ..entries = [entry(now), entry(now.subtract(const Duration(days: 7)))];
      await t.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(
            lang: lang,
            gateway: gw,
            actions: FakeActions(),
            last: now.subtract(const Duration(days: 2)),
          ),
          child: host(
            BackupScreen(onOpenRestore: () {}, now: () => now),
            lang: lang,
            scale: v.textScale,
            dark: v.dark,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('golden-root')),
        matchesGoldenFile('goldens/s66_${v.name}.png'),
      );
    });

    testWidgets('S-04 golden ${v.name}', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final gw = FakeGateway()
        ..entries = [entry(now), entry(now.subtract(const Duration(days: 7)))];
      await t.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(
            lang: lang,
            gateway: gw,
            effects: FakeEffects(),
          ),
          child: host(
            RestoreScreen(
              onRestored: ({required regrantDue}) {},
              onStartFresh: () {},
            ),
            lang: lang,
            scale: v.textScale,
            dark: v.dark,
          ),
        ),
      );
      await t.pumpAndSettle();
      final c = ProviderScope.containerOf(
        t.element(find.byType(RestoreScreen)),
      );
      await c.read(restoreFlowProvider.notifier).search();
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('golden-root')),
        matchesGoldenFile('goldens/s04_${v.name}.png'),
      );
    });
  }
}
