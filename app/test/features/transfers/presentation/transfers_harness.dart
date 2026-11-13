// T-093: fake port and pump helpers for the S-15 / S-16 sheet tests.
// Synthetic data only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/l10n/locale_providers.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/transactions/application/reimbursements.dart';
import 'package:zaghlol/features/transfers/presentation/transfers_port.dart';
import 'package:zaghlol/features/transfers/presentation/transfers_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final egp = Currency.of('EGP');
final usd = Currency.of('USD');
Money e(int minor) => Money(egp, minor);
Money u(int minor) => Money(usd, minor);

class FakePort implements TransfersSheetPort {
  FakePort({this.split, this.assignData, this.linkData, this.markable = false});

  SplitData? split;
  AssignData? assignData;
  LinkData? linkData;
  bool markable;
  Object? failWith;
  bool loadFails = false;

  final List<(String, List<SplitEdit>, Set<String>)> saved = [];
  final List<(String, List<AssignLine>, String?)> assigned = [];
  final List<String> unassigned = [];
  final List<(String, String)> linked = [];
  final List<String> unlinked = [];
  final List<bool> searchAllCalls = [];

  void _maybeFail() {
    if (failWith != null) throw failWith!;
  }

  @override
  Future<SplitData?> loadSplit(String expenseId) async {
    if (loadFails) throw StateError('x');
    return split;
  }

  @override
  Future<void> saveSplit(
    String expenseId,
    List<SplitEdit> edits,
    Set<String> removedIds,
  ) async {
    _maybeFail();
    saved.add((expenseId, edits, removedIds));
  }

  @override
  Future<AssignData?> loadAssign(
    String sourceId, {
    bool searchAll = false,
  }) async {
    searchAllCalls.add(searchAll);
    if (loadFails) throw StateError('x');
    return assignData;
  }

  @override
  Future<Money> assign(
    String sourceId,
    List<AssignLine> lines, {
    String? participantId,
  }) async {
    _maybeFail();
    assigned.add((sourceId, lines, participantId));
    return Money(egp, lines.fold<int>(0, (s, l) => s + l.amountMinor));
  }

  @override
  Future<void> unassign(String linkId) async {
    _maybeFail();
    unassigned.add(linkId);
  }

  @override
  Future<LinkData?> loadLink(String txnId) async {
    if (loadFails) throw StateError('x');
    return linkData;
  }

  @override
  Future<void> link(String outId, String inId) async {
    _maybeFail();
    linked.add((outId, inId));
  }

  @override
  Future<void> unlink(String txnId) async => unlinked.add(txnId);

  @override
  bool get supportsMarkAnyway => markable;

  @override
  Future<void> markAnyway(String txnId) async {}
}

SplitData sampleSplit({bool withRepayment = true}) => SplitData(
  expenseId: 'x1',
  merchant: 'Cilantro',
  amount: e(120000),
  people: [
    SplitPerson(
      id: 'p1',
      name: 'Ahmed',
      share: e(40000),
      repayments: withRepayment
          ? [
              SplitRepayment(
                linkId: 'l1',
                sourceId: 's1',
                amount: e(40000),
                sourceLabel: 'InstaPay',
                date: DateTime.utc(2026, 10, 24),
              ),
            ]
          : const [],
    ),
    SplitPerson(id: 'p2', name: 'Karim', share: e(40000)),
  ],
  suggestions: [
    SplitSuggestion(
      sourceId: 's2',
      person: 'KARIM M',
      amount: e(40000),
      date: DateTime.utc(2026, 10, 25),
      participantId: 'p2',
    ),
  ],
);

AssignData sampleAssign({
  List<AssignCandidate>? candidates,
  bool searchedAll = false,
}) => AssignData(
  sourceId: 'in1',
  person: 'AHMED',
  amount: e(80000),
  left: e(80000),
  windowDays: 60,
  searchedAll: searchedAll,
  candidates:
      candidates ??
      [
        AssignCandidate(
          expenseId: 'x1',
          merchant: 'Cilantro',
          date: DateTime.utc(2026, 10, 23),
          amount: e(120000),
          room: e(120000),
        ),
        AssignCandidate(
          expenseId: 'x2',
          merchant: 'Uber',
          date: DateTime.utc(2026, 10, 23),
          amount: e(18000),
          room: e(18000),
        ),
      ],
);

LinkData sampleLink({bool empty = false}) => LinkData(
  id: 'out1',
  amount: e(100000),
  accountLabel: 'NBE •4567',
  when: DateTime.utc(2026, 10, 23, 14),
  isOut: true,
  candidates: empty
      ? const []
      : [
          LinkCandidate(
            id: 'in1',
            amount: e(100000),
            accountLabel: 'CIB •1234',
            when: DateTime.utc(2026, 10, 23, 14, 2),
            gapMinutes: 2,
          ),
          LinkCandidate(
            id: 'in2',
            amount: u(2005),
            accountLabel: 'Wise',
            when: DateTime.utc(2026, 10, 24, 14),
            gapMinutes: 1440,
          ),
        ],
);

/// Pumps a page with an "open" button; tapping it shows [open]'s sheet.
Future<void> pumpSheet(
  WidgetTester tester, {
  required FakePort port,
  required Future<Object?> Function(BuildContext) open,
  Locale locale = const Locale('en'),
  double textScale = 1.0,
  bool dark = false,
  List<Override> overrides = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transfersSheetPortProvider.overrideWith((ref) async => port),
        digitsModeProvider.overrideWith(
          (ref, lang) => DigitsMode.resolve(DigitsPref.auto, lang),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ZaghlolTheme.light,
        darkTheme: ZaghlolTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

ReimbursementException reimb(String code) => ReimbursementException(code);

/// Finds a Text whose content, without bidi isolation marks, contains [s].
Finder textHas(String s) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data ?? '').replaceAll(RegExp(r'[\u2066-\u2069]'), '').contains(s),
);
