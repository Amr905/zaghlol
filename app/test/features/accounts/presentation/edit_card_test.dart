import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/features/accounts/data/accounts_providers.dart';
import 'package:zaghlol/features/accounts/domain/account.dart';
import 'package:zaghlol/features/accounts/domain/accounts_repository.dart';
import 'package:zaghlol/features/accounts/presentation/edit_card/add_card_steps.dart';
import 'package:zaghlol/features/accounts/presentation/edit_card/card_details_screen.dart';
import 'package:zaghlol/features/accounts/presentation/edit_card/card_form_logic.dart';
import 'package:zaghlol/features/accounts/presentation/edit_card/edit_card_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final _egp = Currency.of('EGP');
final _t = DateTime.utc(2026, 11, 1);

Account acc(
  String id,
  String label, {
  AccountKind kind = AccountKind.credit,
  String inst = 'cib',
  String? last4,
  bool hidden = false,
  int? due,
}) => Account(
  id: id,
  kind: kind,
  label: label,
  defaultCurrency: _egp,
  isHidden: hidden,
  isDefaultCash: false,
  createdAt: _t,
  updatedAt: _t,
  institutionCode: inst,
  last4: last4,
  statementDueDay: due,
);

class FakeRepo implements AccountsRepository {
  FakeRepo(this.items, {this.failUpdate = false});
  final List<Account> items;
  final bool failUpdate;
  final calls = <String>[];
  AccountEdit? lastEdit;
  AccountHint? lastHint;

  @override
  Future<List<Account>> list({bool includeHidden = false}) async => [
    for (final a in items)
      if (includeHidden || !a.isHidden) a,
  ];

  @override
  Future<ResolvedAccount> resolve(AccountHint hint) async {
    calls.add('resolve');
    lastHint = hint;
    final a = acc(
      'new',
      hint.label,
      kind: hint.kind ?? AccountKind.account,
      inst: hint.institutionCode,
      last4: hint.last4,
    );
    items.add(a);
    return ResolvedAccount(a, created: true);
  }

  @override
  Future<Account> update(String id, AccountEdit edit) async {
    if (failUpdate) throw StateError('x');
    calls.add('update');
    lastEdit = edit;
    return items.firstWhere((a) => a.id == id);
  }

  @override
  Future<Account> setHidden(String id, {required bool hidden}) async {
    calls.add('hide:$hidden');
    return items.firstWhere((a) => a.id == id);
  }

  @override
  Future<Account> merge({
    required String sourceId,
    required String targetId,
  }) async {
    calls.add('merge:$sourceId>$targetId');
    return items.firstWhere((a) => a.id == targetId);
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

final banks = [
  InstitutionOption(
    code: 'cib',
    nameAr: 'البنك التجاري الدولي',
    nameEn: 'CIB',
    defaultCurrency: _egp,
    isEgypt: true,
  ),
  InstitutionOption(
    code: 'wise',
    nameAr: 'وايز',
    nameEn: 'Wise',
    defaultCurrency: Currency.of('USD'),
    isEgypt: false,
  ),
];

Widget host(
  Widget child, {
  required FakeRepo repo,
  Locale locale = const Locale('en'),
  double scale = 1.0,
  CardCapturePort? port,
  int txnCount = 214,
  bool dark = false,
}) {
  return ProviderScope(
    overrides: [
      accountsRepositoryProvider.overrideWith((ref) async => repo),
      institutionOptionsProvider.overrideWithValue(banks),
      cardCapturePortProvider.overrideWithValue(port),
      accountTxnCountProvider.overrideWith((ref, id) async => txnCount),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ZaghlolTheme.light,
      darkTheme: ZaghlolTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: app!,
      ),
      home: child,
    ),
  );
}

AppLocalizations l10nOf(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(Scaffold).first));

Widget createScreen(
  AccountKind kind, {
  void Function(Account)? onSaved,
  void Function(Account)? onOpenExisting,
}) => CardDetailsScreen.create(
  kind: kind,
  institution: banks.first,
  onSaved: onSaved,
  onOpenExisting: onOpenExisting,
);

bool saveEnabled(WidgetTester t) =>
    t.widget<TextButton>(find.byKey(const Key('card-save'))).onPressed != null;

class _Port implements CardCapturePort {
  Set<String>? off;
  @override
  Future<void> turnOff({
    required String institutionCode,
    required String? last4,
    required Set<String> offChannels,
  }) async => off = offChannels;
}

Future<void> pumpTall(WidgetTester t, Widget w) async {
  await t.binding.setSurfaceSize(const Size(360, 1800));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(w);
}

void main() {
  group('validation', () {
    CardFormErrors v({
      String name = 'Main',
      String last4 = '1234',
      String limit = '',
      String due = '',
      AccountKind kind = AccountKind.credit,
      List<String> taken = const [],
    }) => validateCardForm(
      name: name,
      last4: last4,
      limit: limit,
      dueDay: due,
      kind: kind,
      currency: _egp,
      takenNames: taken,
    );

    test('name 1..30 and unique', () {
      expect(v(name: ' ').name, NameError.empty);
      expect(v(name: 'x' * 31).name, NameError.tooLong);
      expect(v(name: 'x' * 30).name, isNull);
      expect(v(name: 'main', taken: ['Main']).name, NameError.taken);
    });
    test('last4 exactly 4 digits, Arabic-Indic accepted', () {
      expect(v(last4: '123').last4, Last4Error.invalid);
      expect(v(last4: '12345').last4, Last4Error.invalid);
      expect(v(last4: '١٢٣٤').last4, isNull);
      expect(v(last4: '', kind: AccountKind.wallet).last4, isNull);
      expect(v(last4: '').last4, Last4Error.invalid);
    });
    test('limit >= 0 and due day 1..31, credit only', () {
      expect(v(limit: '-1').limit, LimitError.negative);
      expect(v(limit: '0').limit, isNull);
      expect(v(limit: '24000').limit, isNull);
      expect(v(limit: '٢٤٠٠٠').limit, isNull);
      expect(v(due: '0').dueDay, DueDayError.outOfRange);
      expect(v(due: '32').dueDay, DueDayError.outOfRange);
      expect(v(due: '31').dueDay, isNull);
      expect(v(due: '99', kind: AccountKind.debit).dueDay, isNull);
    });
    test('merge checks', () {
      final a = acc('a', 'A');
      expect(checkMerge(a, a), MergeCheck.self);
      expect(checkMerge(a, acc('b', 'B')), MergeCheck.ok);
      expect(
        checkMerge(a, acc('b', 'B', inst: 'nbe')),
        MergeCheck.differentInstitution,
      );
    });
    test(
      'createCard returns the existing card for the same bank + last4',
      () async {
        final repo = FakeRepo([acc('x', 'Old', last4: '1234', hidden: true)]);
        final r = await createCard(
          repo,
          institutionCode: 'cib',
          name: 'New',
          last4: '١٢٣٤',
          kind: AccountKind.credit,
          currency: _egp,
          limit: '',
          dueDay: '',
        );
        expect(r.duplicateOf?.id, 'x');
        expect(repo.calls, isEmpty);
      },
    );
  });

  group('type sheet and bank picker', () {
    testWidgets('type sheet lists the five types', (t) async {
      AccountKind? picked;
      await pumpTall(
        t,
        host(
          Builder(
            builder: (c) => TextButton(
              onPressed: () async => picked = await showAddCardTypeSheet(c),
              child: const Text('go'),
            ),
          ),
          repo: FakeRepo([]),
        ),
      );
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      for (final k in ['credit', 'debit', 'wallet', 'multi_currency', 'bnpl']) {
        expect(find.byKey(Key('add-type-$k')), findsOneWidget);
      }
      await t.tap(find.byKey(const Key('add-type-wallet')));
      await t.pumpAndSettle();
      expect(picked, AccountKind.wallet);
    });

    testWidgets('bank picker: search, empty result, not listed', (t) async {
      InstitutionOption? picked;
      await pumpTall(
        t,
        host(
          Builder(
            builder: (c) => TextButton(
              onPressed: () async => picked = await pushBankPicker(c),
              child: const Text('go'),
            ),
          ),
          repo: FakeRepo([]),
        ),
      );
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bank-cib')), findsOneWidget);
      expect(find.byKey(const Key('bank-wise')), findsOneWidget);
      await t.enterText(find.byKey(const Key('bank-search')), 'wis');
      await t.pump();
      expect(find.byKey(const Key('bank-cib')), findsNothing);
      await t.enterText(find.byKey(const Key('bank-search')), 'zzz');
      await t.pump();
      expect(find.byKey(const Key('bank-no-results')), findsOneWidget);
      await t.tap(find.byKey(const Key('bank-not-listed')));
      await t.pumpAndSettle();
      expect(picked?.code, genericInstitutionCode);
    });
  });

  for (final locale in const [Locale('en'), Locale('ar', 'EG')]) {
    final tag = locale.languageCode;

    group('details create ($tag)', () {
      testWidgets('save disabled until valid; Arabic digits normalized', (
        t,
      ) async {
        final repo = FakeRepo([]);
        Account? saved;
        await pumpTall(
          t,
          host(
            createScreen(AccountKind.credit, onSaved: (a) => saved = a),
            repo: repo,
            locale: locale,
          ),
        );
        await t.pumpAndSettle();
        expect(saveEnabled(t), isFalse);
        await t.enterText(find.byKey(const Key('card-name')), 'Main');
        await t.enterText(find.byKey(const Key('card-last4')), '١٢٣٤');
        await t.enterText(find.byKey(const Key('card-limit')), '٢٤٠٠٠');
        await t.enterText(find.byKey(const Key('card-dueday')), '١٥');
        await t.pump();
        expect(
          t
              .widget<TextField>(find.byKey(const Key('card-last4')))
              .controller!
              .text,
          '1234',
        );
        expect(saveEnabled(t), isTrue);
        await t.tap(find.byKey(const Key('card-save')));
        await t.pumpAndSettle();
        expect(repo.calls, ['resolve', 'update']);
        expect(repo.lastHint!.last4, '1234');
        expect(repo.lastHint!.kind, AccountKind.credit);
        expect(repo.lastEdit!.statementDueDay, 15);
        expect(repo.lastEdit!.creditLimit!.minor, 2400000);
        expect(saved?.label, 'Main');
      });

      testWidgets('due day 32 and short last4 show errors', (t) async {
        await pumpTall(
          t,
          host(
            createScreen(AccountKind.credit),
            repo: FakeRepo([]),
            locale: locale,
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('card-name')), 'A');
        await t.enterText(find.byKey(const Key('card-last4')), '12');
        await t.enterText(find.byKey(const Key('card-dueday')), '32');
        await t.pump();
        final s = l10nOf(t);
        expect(find.text(s.commonValidationLast4), findsOneWidget);
        expect(find.textContaining(RegExp('31|٣١')), findsWidgets);
        expect(saveEnabled(t), isFalse);
      });

      testWidgets('debit hides limit and due day', (t) async {
        await pumpTall(
          t,
          host(
            createScreen(AccountKind.debit),
            repo: FakeRepo([]),
            locale: locale,
          ),
        );
        await t.pumpAndSettle();
        expect(find.byKey(const Key('card-limit')), findsNothing);
        expect(find.byKey(const Key('card-dueday')), findsNothing);
      });

      testWidgets('duplicate bank + last4 offers to open the existing card', (
        t,
      ) async {
        final existing = acc('x', 'Old', last4: '1234');
        final repo = FakeRepo([existing]);
        Account? opened;
        await pumpTall(
          t,
          host(
            createScreen(AccountKind.credit, onOpenExisting: (a) => opened = a),
            repo: repo,
            locale: locale,
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('card-name')), 'New');
        await t.enterText(find.byKey(const Key('card-last4')), '1234');
        await t.pump();
        await t.tap(find.byKey(const Key('card-save')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('card-duplicate')), findsOneWidget);
        expect(repo.calls, isEmpty);
        await t.tap(find.text(l10nOf(t).accountsEditOpenExisting));
        expect(opened?.id, 'x');
      });

      testWidgets('save failure keeps input and shows the error', (t) async {
        await pumpTall(
          t,
          host(
            createScreen(AccountKind.credit),
            repo: FakeRepo([], failUpdate: true),
            locale: locale,
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('card-name')), 'Main');
        await t.enterText(find.byKey(const Key('card-last4')), '1234');
        await t.enterText(find.byKey(const Key('card-dueday')), '5');
        await t.pump();
        await t.tap(find.byKey(const Key('card-save')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('card-save-error')), findsOneWidget);
        expect(find.text('Main'), findsWidgets);
      });

      testWidgets('capture toggles go through the port', (t) async {
        final port = _Port();
        await pumpTall(
          t,
          host(
            createScreen(AccountKind.debit),
            repo: FakeRepo([]),
            locale: locale,
            port: port,
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('card-name')), 'Main');
        await t.enterText(find.byKey(const Key('card-last4')), '1234');
        await t.ensureVisible(find.byKey(const Key('capture-notification')));
        await t.tap(find.byKey(const Key('capture-notification')));
        await t.pump();
        await t.tap(find.byKey(const Key('card-save')));
        await t.pumpAndSettle();
        expect(port.off, {'notification'});
      });
    });

    group('details edit and merge ($tag)', () {
      testWidgets('hide toggle calls setHidden', (t) async {
        final a = acc('a', 'Main', last4: '1111');
        final repo = FakeRepo([a]);
        await pumpTall(
          t,
          host(
            CardDetailsScreen.edit(account: a),
            repo: repo,
            locale: locale,
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const Key('card-hide')));
        await t.tap(find.byKey(const Key('card-hide')));
        await t.pumpAndSettle();
        expect(repo.calls, ['hide:true']);
      });

      testWidgets('rename does not flag its own name as taken', (t) async {
        final a = acc('a', 'Main', last4: '1111');
        await pumpTall(
          t,
          host(
            CardDetailsScreen.edit(account: a),
            repo: FakeRepo([a, acc('b', 'Other', last4: '2222')]),
            locale: locale,
          ),
        );
        await t.pumpAndSettle();
        expect(saveEnabled(t), isTrue);
        await t.enterText(find.byKey(const Key('card-name')), 'other');
        await t.pump();
        expect(saveEnabled(t), isFalse);
      });

      testWidgets('merge: pick, confirm with count, then merge', (t) async {
        final a = acc('a', 'Old', last4: '1234');
        final b = acc('b', 'New', last4: '5678');
        final repo = FakeRepo([a, b]);
        await pumpTall(
          t,
          host(
            CardDetailsScreen.edit(account: a),
            repo: repo,
            locale: locale,
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const Key('card-merge')));
        await t.tap(find.byKey(const Key('card-merge')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('merge-target-a')), findsNothing);
        await t.tap(find.byKey(const Key('merge-target-b')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('merge-confirm')), findsOneWidget);
        expect(find.textContaining(RegExp('214|٢١٤')), findsOneWidget);
        expect(find.byKey(const Key('merge-different-bank')), findsNothing);
        await t.tap(find.byKey(const Key('merge-confirm-yes')));
        await t.pumpAndSettle();
        expect(repo.calls, ['merge:a>b']);
      });

      testWidgets('merge across banks warns first', (t) async {
        final a = acc('a', 'Old', last4: '1234');
        final b = acc('b', 'Other', last4: '5678', inst: 'nbe');
        final repo = FakeRepo([a, b]);
        await pumpTall(
          t,
          host(
            CardDetailsScreen.edit(account: a),
            repo: repo,
            locale: locale,
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const Key('card-merge')));
        await t.tap(find.byKey(const Key('card-merge')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('merge-target-b')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('merge-different-bank')), findsOneWidget);
        await t.tap(
          find.text(
            AppLocalizations.of(
              t.element(find.byKey(const Key('merge-confirm'))),
            ).commonActionCancel,
          ),
        );
        await t.pumpAndSettle();
        expect(repo.calls, isEmpty);
      });
    });

    testWidgets('text scale 1.3 does not overflow ($tag)', (t) async {
      await pumpTall(
        t,
        host(
          createScreen(AccountKind.credit),
          repo: FakeRepo([]),
          locale: locale,
          scale: 1.3,
          port: _Port(),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
