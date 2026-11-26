// T-277: the tip catalog and rotation, plus the routes how-to tips open.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/routing/app_router.dart';
import 'package:zaghlol/core/routing/app_routes.dart';
import 'package:zaghlol/features/mascot/application/mascot_tips.dart';

const _paths = {
  MascotTipTarget.add: AppRoutes.add,
  MascotTipTarget.review: AppRoutes.review,
  MascotTipTarget.transactions: AppRoutes.transactions,
  MascotTipTarget.insights: AppRoutes.insights,
  MascotTipTarget.ask: AppRoutes.zaghlol,
};

void main() {
  test('at least 30 tips, in the three groups', () {
    expect(mascotTips.length, greaterThanOrEqualTo(30));
    expect(tipsOf(MascotTipGroup.usage).length, greaterThanOrEqualTo(12));
    expect(tipsOf(MascotTipGroup.smart).length, greaterThanOrEqualTo(10));
    expect(tipsOf(MascotTipGroup.habit).length, greaterThanOrEqualTo(8));
  });

  for (final locale in const ['ar', 'en']) {
    test('copy rules ($locale)', () async {
      final l = await AppLocalizations.delegate.load(Locale(locale));
      final texts = [for (final t in mascotTips) t.text(l)];
      expect(texts.toSet().length, texts.length, reason: 'no duplicates');
      for (final s in texts) {
        expect(s.trim(), isNotEmpty);
        expect(s, isNot(contains('دورة')));
        expect(s, isNot(contains('دوره')));
        expect(s, isNot(contains('AI')));
        expect(s.toLowerCase(), isNot(contains('no server')));
        expect(s.toLowerCase(), isNot(contains('cycle')));
      }
    });
  }

  test('rotation: no tip repeats before its group has been shown', () {
    for (final days in const [0, 30]) {
      var r = TipRotation.start;
      final seen = <MascotTipGroup, List<MascotTip>>{};
      for (var i = 0; i < 400; i++) {
        final p = pickTip(rotation: r, daysSinceInstall: days);
        final list = seen.putIfAbsent(p.tip.group, () => []);
        final size = tipsOf(p.tip.group).length;
        final window = list.length % size == 0
            ? <MascotTip>[]
            : list.sublist(list.length - list.length % size);
        expect(window, isNot(contains(p.tip)));
        list.add(p.tip);
        r = p.next;
      }
      for (final g in MascotTipGroup.values) {
        expect(seen[g], isNotNull);
        expect(seen[g]!.toSet().length, tipsOf(g).length);
      }
    }
  });

  test('usage tips lead in the first two weeks', () {
    int usageShare(int days) {
      var r = TipRotation.start;
      var usage = 0;
      for (var i = 0; i < 60; i++) {
        final p = pickTip(rotation: r, daysSinceInstall: days);
        if (p.tip.group == MascotTipGroup.usage) usage++;
        r = p.next;
      }
      return usage;
    }

    expect(usageShare(3), greaterThan(usageShare(30)));
    expect(usageShare(3), 40);
    expect(usageShare(kTipNewcomerDays), 20);
  });

  test('rotation text round-trips; bad text starts over', () {
    const r = TipRotation(usage: 3, smart: 1, habit: 2, shown: 6);
    expect(TipRotation.decode(r.encode()).encode(), r.encode());
    for (final bad in const ['', 'x', '1.2.3', '1.2.3.-4', 'a.b.c.d']) {
      expect(TipRotation.decode(bad).encode(), TipRotation.start.encode());
    }
  });

  testWidgets('every tab target is a real route', (t) async {
    final router = buildAppRouter(const TabRoots());
    addTearDown(router.dispose);
    for (final tip in mascotTips) {
      final path = _paths[tip.target];
      if (path == null) continue;
      final match = router.configuration.findMatch(Uri.parse(path));
      expect(match.isError, isFalse, reason: path);
    }
    // Targets without a path open through Home's actions.
    expect(
      MascotTipTarget.values.toSet().difference({
        ..._paths.keys,
        MascotTipTarget.none,
        MascotTipTarget.budget,
        MascotTipTarget.settings,
        MascotTipTarget.importStatement,
      }),
      isEmpty,
    );
  });
}
