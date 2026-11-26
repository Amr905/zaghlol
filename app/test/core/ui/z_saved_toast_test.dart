import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/ui/z_saved_toast.dart';

import '../../support/golden_matrix.dart';

Widget _host(
  GoldenVariant v, {
  String? line,
  VoidCallback? onUndo,
  String? extra,
  VoidCallback? onExtra,
}) {
  return ProviderScope(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: v.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ZaghlolTheme.light,
      darkTheme: ZaghlolTheme.dark,
      themeMode: v.dark ? ThemeMode.dark : ThemeMode.light,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showSavedToast(
                ScaffoldMessenger.of(ctx),
                AppLocalizations.of(ctx),
                budgetLine: line,
                onUndo: onUndo,
                extraLabel: extra,
                onExtra: onExtra,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final v in goldenVariants.where((v) => !v.dark)) {
    final title = v.isRtl ? 'اتسجلت!' : 'Saved!';
    final undo = v.isRtl ? 'تراجع' : 'Undo';

    testWidgets('title only, no undo ${v.name}', (t) async {
      await t.pumpWidget(_host(v));
      await t.tap(find.text('go'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(title), findsOneWidget);
      expect(find.text(undo), findsNothing);
      expect(find.textContaining('left in'), findsNothing);
    });

    testWidgets('budget line and Undo ${v.name}', (t) async {
      var undone = 0;
      await t.pumpWidget(_host(v, line: 'LINE-X', onUndo: () => undone++));
      await t.tap(find.text('go'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('LINE-X'), findsOneWidget);
      await t.tap(find.text(undo));
      expect(undone, 1);
    });

    testWidgets('auto-hides after about 2.5 s ${v.name}', (t) async {
      await t.pumpWidget(_host(v, onUndo: () {}));
      await t.tap(find.text('go'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(title), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      expect(find.text(title), findsNothing);
    });
  }

  testWidgets('extra action replaces Undo', (t) async {
    var hit = 0;
    await t.pumpWidget(
      _host(goldenVariants.first, extra: 'TEACH', onExtra: () => hit++),
    );
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('TEACH'));
    expect(hit, 1);
  });

  test('only the single-save paths show the toast (no bulk/background)', () {
    final users = [
      for (final e in Directory('lib').listSync(recursive: true))
        if (e is File &&
            e.path.endsWith('.dart') &&
            e.readAsStringSync().contains('showSavedToast('))
          e.path,
    ]..sort();
    expect(users, [
      'lib/core/ui/z_saved_toast.dart',
      'lib/features/ingestion/presentation/review/review_screen.dart',
      'lib/features/transactions/presentation/edit/transaction_edit_screen.dart',
      'lib/features/voice/presentation/voice_logger_screen.dart',
    ]);
  });

  for (final v in goldenVariants) {
    testWidgets('golden ${v.name}', (t) async {
      await t.pumpWidget(
        _host(v, line: v.isRtl ? 'فاضلك' : 'left', onUndo: () {}),
      );
      await t.tap(find.text('go'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../goldens/saved_toast_${v.name}.png'),
      );
    }, tags: ['golden']);
  }
}
