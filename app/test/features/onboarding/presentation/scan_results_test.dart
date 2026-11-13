import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/capture/application/ignore_rules.dart';
import 'package:zaghlol/features/capture/presentation/capture_controls.dart';
import 'package:zaghlol/features/onboarding/presentation/scan_results.dart';

class FakeControls implements CaptureControls {
  final added = <IgnoreTarget>[];
  @override
  Future<AddIgnoreResult> add(
    IgnoreTarget target, {
    ExistingAction existing = const KeepExisting(),
  }) async {
    added.add(target);
    return const AddIgnoreResult(
      ruleId: 'r',
      created: true,
      guard: null,
      deleted: 0,
      undoBatchIds: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

const sample = ScanResultsData(
  found: 120,
  review: 7,
  cards: [
    ScanCardItem(
      accountId: 'a1',
      label: 'CIB ••1234',
      kind: AccountKind.debit,
      txnCount: 80,
      institutionCode: 'cib',
      last4: '1234',
    ),
    ScanCardItem(
      accountId: 'a2',
      label: 'NBE ••9876',
      kind: AccountKind.credit,
      txnCount: 40,
      institutionCode: 'nbe',
      last4: '9876',
      looksCredit: true,
    ),
  ],
);

Widget host(
  AsyncValue<ScanResultsData> data,
  String lang, {
  double scale = 1,
  bool dark = false,
  FakeControls? controls,
  VoidCallback? onDone,
  void Function(String)? onEdit,
  void Function(String)? onCredit,
}) => ProviderScope(
  overrides: [
    scanResultsProvider.overrideWith(
      (ref) => data.when(
        data: (d) => d,
        loading: () => Future<ScanResultsData>.delayed(
          const Duration(days: 1),
          () => sample,
        ),
        error: (e, s) => Future<ScanResultsData>.error(e, s),
      ),
    ),
    if (controls != null)
      captureControlsProvider.overrideWith((ref) async => controls),
    languageProvider.overrideWith(
      (ref) => Stream.value(lang == 'ar' ? LanguagePref.ar : LanguagePref.en),
    ),
    digitsProvider.overrideWith((ref) => Stream.value(DigitsPref.auto)),
  ],
  child: MaterialApp(
    theme: dark ? ZaghlolTheme.dark : ZaghlolTheme.light,
    locale: Locale(lang),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: ScanResultsScreen(
      onDone: onDone ?? () {},
      onEditCard: onEdit,
      onSetupCredit: onCredit,
    ),
  ),
);

void main() {
  for (final lang in ['ar', 'en']) {
    group(lang, () {
      testWidgets('populated at 1.3x: stats, cards, credit prompt', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 1500));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          host(const AsyncData(sample), lang, scale: 1.3),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('stat-review')), findsOneWidget);
        expect(find.text('CIB ••1234'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('scan-credit-prompt')),
          findsOneWidget,
        );
        final dir = Directionality.of(
          tester.element(find.byKey(const ValueKey('scan-show-me'))),
        );
        expect(dir, lang == 'ar' ? TextDirection.rtl : TextDirection.ltr);
      });

      testWidgets('credit prompt opens S-43 and can be dismissed', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 1500));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        String? opened;
        await tester.pumpWidget(
          host(const AsyncData(sample), lang, onCredit: (id) => opened = id),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('scan-credit-yes')));
        expect(opened, 'a2');
        await tester.tap(find.byKey(const ValueKey('scan-credit-later')));
        await tester.pump();
        expect(find.byKey(const ValueKey('scan-credit-prompt')), findsNothing);
      });

      testWidgets('stop tracking adds ignore rules and removes the card', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 1500));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final ctl = FakeControls();
        await tester.pumpWidget(
          host(const AsyncData(sample), lang, controls: ctl),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('CIB ••1234'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('scan-card-ignore')));
        await tester.pumpAndSettle();
        expect(ctl.added.map((t) => t.channel), ['sms', 'notification']);
        expect(ctl.added.first.institutionCode, 'cib');
        expect(ctl.added.first.last4, '1234');
        expect(find.text('CIB ••1234'), findsNothing);
      });

      testWidgets('edit opens the card; confirm marks it', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 1500));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        String? edited;
        await tester.pumpWidget(
          host(const AsyncData(sample), lang, onEdit: (id) => edited = id),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('CIB ••1234'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('scan-card-confirm')));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.check_circle), findsOneWidget);
        await tester.tap(find.text('CIB ••1234'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('scan-card-edit')));
        await tester.pumpAndSettle();
        expect(edited, 'a1');
      });

      testWidgets('0 found skips straight to Home', (tester) async {
        var done = 0;
        await tester.pumpWidget(
          host(
            const AsyncData(ScanResultsData(found: 0, review: 0, cards: [])),
            lang,
            onDone: () => done++,
          ),
        );
        await tester.pumpAndSettle();
        expect(done, 1);
        expect(find.byKey(const ValueKey('scan-show-me')), findsNothing);
      });

      testWidgets('error shows retry', (tester) async {
        await tester.pumpWidget(
          host(AsyncError(StateError('x'), StackTrace.empty), lang),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('scan-results-retry')),
          findsOneWidget,
        );
      });

      testWidgets('loading shows a spinner', (tester) async {
        await tester.pumpWidget(host(const AsyncLoading(), lang));
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(days: 2));
      });
    });
  }
}
