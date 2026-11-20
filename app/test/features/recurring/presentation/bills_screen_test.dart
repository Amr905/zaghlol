// T-102: S-24 / S-25 widget tests, ar + en, RTL, text scale 1.3. Synthetic.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol/features/recurring/presentation/bill_edit_screen.dart';
import 'package:zaghlol/features/recurring/presentation/bills_providers.dart';
import 'package:zaghlol/features/recurring/presentation/bills_screen.dart';
import 'package:zaghlol/features/recurring/presentation/bills_view.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../budget/presentation/budget_test_support.dart';

class FakeActions implements BillsActions {
  final calls = <String>[];
  BillDraft? saved;

  @override
  Future<void> accept(String id) async => calls.add('accept:$id');
  @override
  Future<void> dismiss(String id) async => calls.add('dismiss:$id');
  @override
  Future<bool> notABill(String id) async {
    calls.add('notABill:$id');
    return true;
  }

  @override
  Future<bool> markPaid(String id, {String? expectedDue}) async {
    calls.add('paid:$id');
    return true;
  }

  @override
  Future<void> delete(String id) async => calls.add('delete:$id');
  @override
  Future<void> save(BillDraft d, {String? id, String? merchantNorm}) async {
    saved = d;
    calls.add('save:${id ?? 'new'}');
  }
}

BillRowView bill(
  String id,
  String kind,
  int minor,
  int days, {
  int paid = 0,
  int? total,
  bool autoAdded = false,
}) {
  final due = CivilDate(2026, 11, 13).plusDays(days);
  return BillRowView(
    id: id,
    name: id,
    kind: kind,
    amount: egpM(minor),
    due: due,
    daysUntil: days,
    timing: days < 0
        ? BillTiming.overdue
        : days == 0
        ? BillTiming.today
        : BillTiming.upcoming,
    paidCount: paid,
    totalCount: total,
    autoAdded: autoAdded,
  );
}

BillsViewData full() => BillsViewData(
  suggestions: [SuggestionView(id: 'sug', name: 'Netflix', amount: egpM(320))],
  upcoming: [
    bill('late', 'installment', 1000, -2, paid: 2, total: 6),
    bill('card', 'card_due', 1450, 2),
    bill('gym', 'subscription', 750, 7, autoAdded: true),
    bill('gam', 'gameya', 2000, 9, paid: 1, total: 10),
  ],
  subscriptions: [
    SubscriptionRowView(
      id: 'gym',
      name: 'Gym',
      monthly: egpM(750),
      yearly: egpM(9000),
    ),
  ],
  subTotals: [CurrencyTotal(monthly: egpM(750), yearly: egpM(9000))],
  dueThisMonth: [egpM(5200)],
);

const empty = BillsViewData(
  suggestions: [],
  upcoming: [],
  subscriptions: [],
  subTotals: [],
  dueThisMonth: [],
);

void main() {
  setUpAll(initDateFormatting);

  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    final lang = locale.languageCode;
    for (final scale in [1.0, 1.3]) {
      testWidgets('timeline renders without overflow $lang x$scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(390, 2600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          harness(
            const BillsScreen(),
            locale: locale,
            scale: scale,
            overrides: [billsDataProvider.overrideWith((ref) async => full())],
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('Payment 3 of 6'),
          lang == 'en' ? findsOneWidget : findsNothing,
        );
        // Card due: no Mark paid; the other three have it.
        expect(
          find.text(lang == 'en' ? 'Mark paid' : 'اتدفع'),
          findsNWidgets(3),
        );
        final dir = Directionality.of(tester.element(find.byType(BillsScreen)));
        expect(dir, lang == 'ar' ? TextDirection.rtl : TextDirection.ltr);
      });
    }
  }

  testWidgets('suggestion actions and mark paid route to the actions', (
    tester,
  ) async {
    final fake = FakeActions();
    await tester.binding.setSurfaceSize(const Size(390, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(
        const BillsScreen(),
        locale: const Locale('en'),
        overrides: [
          billsDataProvider.overrideWith((ref) async => full()),
          billsActionsProvider.overrideWithValue(fake),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Track it'));
    await tester.tap(find.text('Not a subscription'));
    await tester.tap(find.text('Mark paid').first);
    await tester.pumpAndSettle();
    expect(fake.calls, ['accept:sug', 'dismiss:sug', 'paid:late']);
    expect(find.text('Marked late as paid ✓'), findsOneWidget);
  });

  for (final locale in const [Locale('ar', 'EG'), Locale('en')]) {
    final en = locale.languageCode == 'en';
    testWidgets('T-196: an auto-added bill shows the badge and one-tap '
        'Not a bill (${locale.languageCode})', (tester) async {
      final fake = FakeActions();
      await tester.binding.setSurfaceSize(const Size(390, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        harness(
          const BillsScreen(),
          locale: locale,
          overrides: [
            billsDataProvider.overrideWith((ref) async => full()),
            billsActionsProvider.overrideWithValue(fake),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final badge = en ? 'Added automatically' : 'اتضافت لوحدها';
      final undo = en ? 'Not a bill' : 'مش فاتورة';
      // Only the auto-added row (gym) has them.
      expect(find.text(badge), findsOneWidget);
      expect(find.text(undo), findsOneWidget);
      await tester.tap(find.text(undo));
      await tester.pumpAndSettle();
      expect(fake.calls, ['notABill:gym']);
      expect(
        find.text(
          en ? "Got it, I won't add gym again" : 'تمام، مش هضيف gym تاني',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('FU-217a: a bill row reads once, the pill stays a button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(390, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(
        const BillsScreen(),
        locale: const Locale('en'),
        overrides: [billsDataProvider.overrideWith((ref) async => full())],
      ),
    );
    await tester.pumpAndSettle();
    final labels = <String>[];
    void walk(SemanticsNode n) {
      if (n.label.isNotEmpty) labels.add(n.label);
      n.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    walk(tester.getSemantics(find.byType(BillsScreen)));
    // The row's own sentence names the bill; no separate node repeats the
    // bill name, the amount or the due month as a bare text node.
    expect(
      labels.where((l) => l.contains('gym')),
      hasLength(1),
      reason: '$labels',
    );
    expect(
      labels.firstWhere((l) => l.contains('gym')).split('gym'),
      hasLength(2),
      reason: 'the name is read once in the row label',
    );
    // The visual day/month column would be appended to the row's label.
    expect(labels.where((l) => l.contains('November')), isEmpty);
    expect(labels.where((l) => l.contains('Mark paid')), isNotEmpty);
    handle.dispose();
  });

  testWidgets('overdue row says so in words', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(
        const BillsScreen(),
        locale: const Locale('en'),
        overrides: [billsDataProvider.overrideWith((ref) async => full())],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('2 days overdue'), findsOneWidget);
    expect(find.text('Last payment'), findsNothing);
  });

  for (final lang in ['ar', 'en']) {
    testWidgets('empty state $lang', (tester) async {
      await tester.pumpWidget(
        harness(
          const BillsScreen(),
          locale: Locale(lang),
          overrides: [billsDataProvider.overrideWith((ref) async => empty)],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          lang == 'en'
              ? 'No bills or installments yet'
              : 'لسه مفيش فواتير ولا أقساط',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets('loading shows a spinner; error shows retry', (tester) async {
    await tester.pumpWidget(
      harness(
        const BillsScreen(),
        locale: const Locale('en'),
        overrides: [billsDataProvider.overrideWith((ref) => Future.error('x'))],
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('FU-219: a new bill starts from the due-days setting', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(
        const BillEditScreen(),
        locale: const Locale('en'),
        overrides: [
          notifDueDaysBeforeProvider.overrideWith((ref) => Stream.value(10)),
          billsActionsProvider.overrideWithValue(FakeActions()),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Remind me 10 days before'), findsOneWidget);
  });

  testWidgets('editor: save disabled until valid, then saves a draft', (
    tester,
  ) async {
    final fake = FakeActions();
    await tester.binding.setSurfaceSize(const Size(390, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      harness(
        const BillEditScreen(),
        locale: const Locale('en'),
        scale: 1.3,
        overrides: [billsActionsProvider.overrideWithValue(fake)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Installment'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(fake.calls, isEmpty);
    expect(find.text('Pick the next payment date'), findsOneWidget);
    expect(
      find.text('The number of payments must be from 1 to 120'),
      findsOneWidget,
    );
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Fridge');
    await tester.enterText(fields.at(1), '١٬٠٠٠'.replaceAll('٬', ''));
    await tester.enterText(fields.at(3), '6');
    await tester.enterText(fields.at(2), '9');
    await tester.pump();
    expect(find.text("Paid can't be more than the total"), findsOneWidget);
    await tester.enterText(fields.at(2), '3');
    // Pick a date.
    await tester.tap(find.byIcon(Icons.event));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['save:new']);
    expect(fake.saved!.kind, 'installment');
    expect(fake.saved!.amount.minor, 100000);
    expect(fake.saved!.totalCount, 6);
    expect(fake.saved!.paidCount, 3);
  });
}
