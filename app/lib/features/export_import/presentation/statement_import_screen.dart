// T-269 / US-P08: bank statement import, from a PDF (text or scanned) or
// photos of its pages.
//
// Steps: choose -> reading -> (column mapping, only when the layout is not
// recognised) -> review -> saving -> done screen. Nothing is written before
// the user taps the confirm button: the review runs on the parsed rows and a
// dry run (duplicate check); the account is created at the same moment as the
// rows.
//
// States: choose, reading, mapping, review (with year prompt, flagged rows,
// duplicates, no rows left), saving, failures (password, no table, no text,
// OCR not available, unreadable, save failed).
//
// Privacy: the file is read into memory, parsed on the phone and dropped (the
// use case zeroes the bytes); the PDF password lives in a local variable only.

import '../../mascot/presentation/working_bird.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart' show Currency, Money;
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/settings/settings_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../application/import_statement_pdf.dart';
import 'import_done_screen.dart';
import 'import_ports.dart';
import 'import_source_screen.dart' show ImportRoundButton;
import 'statement_import_ports.dart';
import 'statement_mapping_step.dart';
import 'statement_review_widgets.dart';

enum _Phase { choose, reading, mapping, review, saving }

enum _Failure {
  noRows,
  noText,
  noOcr,
  unreadable,
  password,
  wrongPassword,
  save,
}

/// Currencies offered next to the one the statement names.
const List<String> _commonCurrencies = [
  'EGP',
  'USD',
  'EUR',
  'GBP',
  'SAR',
  'AED',
  'KWD',
];

class StatementImportScreen extends ConsumerStatefulWidget {
  const StatementImportScreen({
    super.key,
    required this.bankKey,
    required this.bankName,
    this.onReview,
    this.onOpenCard,
  });

  /// Names the saved column layout and the institution of a new account.
  final String bankKey;
  final String bankName;
  final VoidCallback? onReview;
  final VoidCallback? onOpenCard;

  @override
  ConsumerState<StatementImportScreen> createState() => _State();
}

class _State extends ConsumerState<StatementImportScreen> {
  _Phase _phase = _Phase.choose;
  _Failure? _failure;

  StatementReading? _reading;
  StatementMapping? _mapping;
  StatementParseResult? _parsed;
  int? _year;
  final Map<int, StatementReviewChoice> _decisions = {};
  final Set<int> _keepDuplicates = {};
  List<int> _duplicateRows = const [];
  int _dupToken = 0;

  List<StatementAccountChoice> _accounts = const [];
  String? _accountId;
  bool _newAccount = false;
  final _nameCtl = TextEditingController();
  final _last4Ctl = TextEditingController();

  @override
  void dispose() {
    _nameCtl.dispose();
    _last4Ctl.dispose();
    super.dispose();
  }

  ImportStatementPdfUseCase? _uc;

  bool get _needsYear =>
      _reading != null && ImportStatementPdfUseCase.needsYear(_reading!);

  // ---------------------------------------------------------------- reading

  Future<void> _pick({required bool pdf}) async {
    if (_phase != _Phase.choose) return;
    final picker = ref.read(statementFilePickerProvider);
    final picked = await (pdf ? picker.pickPdf() : picker.pickImages());
    if (picked == null || !mounted) return;
    setState(() {
      _phase = _Phase.reading;
      _failure = null;
    });
    // The PDF password lives in this local only: asked for when the file is
    // protected, passed down per call, never put in state, logs or storage.
    String? password;
    // The use case zeroes the bytes it reads, so a retry with a password gets
    // a fresh copy. The copy is zeroed when this method ends.
    final original = picked.isPdf
        ? Uint8List.fromList(picked.files.first.bytes)
        : null;
    try {
      final uc = await ref.read(statementImportUseCaseProvider.future);
      _uc = uc;
      var wrong = false;
      StatementReading? reading;
      while (reading == null) {
        try {
          if (picked.isPdf) {
            reading = await uc.open(
              Uint8List.fromList(original!),
              bankKey: widget.bankKey,
              password: password,
            );
          } else {
            final fragments = await ref.read(statementImageReaderProvider).read(
              [for (final f in picked.files) f.bytes],
            );
            reading = await uc.openFragments(
              fragments,
              bankKey: widget.bankKey,
            );
          }
        } on StatementImportException catch (e) {
          final needs =
              e.kind == StatementImportFailure.passwordRequired ||
              e.kind == StatementImportFailure.wrongPassword;
          if (!needs) rethrow;
          if (!mounted) return;
          setState(() => _phase = _Phase.choose);
          final asked = await askStatementPassword(
            context,
            _passwordLabels(AppLocalizations.of(context)),
            wrong: wrong || e.kind == StatementImportFailure.wrongPassword,
          );
          if (asked == null || asked.isEmpty || !mounted) {
            if (mounted) setState(() => _failure = _Failure.password);
            return;
          }
          password = asked;
          wrong = true;
          setState(() => _phase = _Phase.reading);
        }
      }
      if (!mounted) return;
      await _afterReading(reading);
    } on Object catch (e) {
      await _fail(e);
    } finally {
      original?.fillRange(0, original.length, 0);
      for (final f in picked.files) {
        f.bytes.fillRange(0, f.bytes.length, 0);
      }
    }
  }

  Future<void> _fail(Object e) async {
    var f = _Failure.unreadable;
    if (e is StatementImportException) {
      f = switch (e.kind) {
        StatementImportFailure.noRows => _Failure.noRows,
        StatementImportFailure.noText => _Failure.noText,
        _ => _Failure.unreadable,
      };
    } else if (e is PdfExtractException) {
      f = switch (e.kind) {
        PdfExtractFailureKind.noText => _Failure.noText,
        PdfExtractFailureKind.passwordRequired => _Failure.password,
        PdfExtractFailureKind.wrongPassword => _Failure.wrongPassword,
        PdfExtractFailureKind.unreadable => _Failure.unreadable,
      };
    }
    if (f == _Failure.noText) {
      final ocr = await ref.read(statementOcrAvailableProvider.future);
      if (!ocr) f = _Failure.noOcr;
    }
    if (!mounted) return;
    setState(() {
      _phase = _Phase.choose;
      _failure = f;
    });
  }

  Future<void> _afterReading(StatementReading reading) async {
    _reading = reading;
    _decisions.clear();
    _keepDuplicates.clear();
    _duplicateRows = const [];
    _year = null;
    final table = reading.table;
    final base =
        reading.template?.mapping ??
        StatementMapping(
          roles: table.suggestedRoles,
          currency: table.suggestedCurrency ?? Currency.of('EGP'),
          dayFirst: table.dayFirst,
        );
    _mapping = base;
    if (reading.needsMapping) {
      setState(() => _phase = _Phase.mapping);
    } else {
      await _enterReview(base);
    }
  }

  Future<void> _enterReview(StatementMapping mapping) async {
    _mapping = mapping;
    try {
      _accounts = await ref.read(statementAccountsProvider).list();
    } on Object {
      _accounts = const [];
    }
    if (!mounted) return;
    _selectDefaultAccount();
    _reparse();
    setState(() => _phase = _Phase.review);
    unawaited(_refreshDuplicates());
  }

  List<StatementAccountChoice> get _matching => [
    for (final a in _accounts)
      if (a.currency == _mapping!.currency) a,
  ];

  void _selectDefaultAccount() {
    final m = _matching;
    _newAccount = m.isEmpty;
    _accountId = m.length == 1 ? m.first.id : null;
    if (_newAccount && _nameCtl.text.isEmpty) _nameCtl.text = widget.bankName;
  }

  void _reparse() {
    _parsed = _uc!.parse(_reading!, _mapping!, confirmedYear: _year);
  }

  Future<void> _refreshDuplicates() async {
    final id = _accountId;
    final token = ++_dupToken;
    if (id == null || _newAccount || (_needsYear && _year == null)) {
      if (mounted) setState(() => _duplicateRows = const []);
      return;
    }
    try {
      final s = await _uc!.run(
        _reading!,
        _mapping!,
        accountId: id,
        dryRun: true,
        saveTemplate: false,
        confirmedYear: _year,
        decisions: Map.of(_decisions),
      );
      if (mounted && token == _dupToken) {
        setState(() => _duplicateRows = s.duplicateRows);
      }
    } on Object {
      if (mounted && token == _dupToken) {
        setState(() => _duplicateRows = const []);
      }
    }
  }

  // ----------------------------------------------------------------- review

  void _decide(int number, StatementReviewChoice? choice) {
    setState(() {
      if (choice == null) {
        _decisions.remove(number);
      } else {
        _decisions[number] = choice;
      }
      _keepDuplicates.remove(number);
    });
    _refreshDuplicates();
  }

  void _setCurrency(Currency c) {
    setState(() {
      _mapping = _mapping!.copyWith(currency: c);
      _decisions.clear();
      _keepDuplicates.clear();
      _selectDefaultAccount();
      _reparse();
    });
    _refreshDuplicates();
  }

  void _setYear(int y) {
    setState(() {
      _year = y;
      _reparse();
    });
    _refreshDuplicates();
  }

  List<StatementRow> get _allRows {
    final p = _parsed!;
    return [...p.rows, ...p.review]
      ..sort((a, b) => a.number.compareTo(b.number));
  }

  Set<int> get _flaggedNumbers => {for (final r in _parsed!.review) r.number};

  int get _undecided => [
    for (final n in _flaggedNumbers)
      if (_decisions[n] == null) n,
  ].length;

  /// Rows that would be saved, by the same rules as the use case.
  int get _toAdd {
    var n = 0;
    final flagged = _flaggedNumbers;
    for (final r in _allRows) {
      final d = _decisions[r.number];
      if (d == StatementReviewChoice.skip) continue;
      if (flagged.contains(r.number) && d == null) continue;
      if (_duplicateRows.contains(r.number) &&
          !_keepDuplicates.contains(r.number)) {
        continue;
      }
      n++;
    }
    return n;
  }

  bool get _accountReady {
    if (!_newAccount) return _accountId != null;
    final last4 = _last4Ctl.text.trim();
    return _nameCtl.text.trim().isNotEmpty &&
        (last4.isEmpty || RegExp(r'^\d{2,4}$').hasMatch(last4));
  }

  String? _blocked(AppLocalizations l) {
    if (_needsYear && _year == null) return l.stmtImportBlockedYear;
    if (_undecided > 0) return l.stmtImportBlockedAnswers;
    if (!_accountReady) return l.stmtImportBlockedAccount;
    if (_toAdd == 0) return l.stmtImportNothingToAdd;
    return null;
  }

  Future<void> _confirm() async {
    final uc = _uc;
    if (uc == null || _phase != _Phase.review) return;
    setState(() {
      _phase = _Phase.saving;
      _failure = null;
    });
    try {
      var id = _accountId;
      var name = _accounts.where((a) => a.id == id).firstOrNull?.name;
      if (_newAccount) {
        final last4 = _last4Ctl.text.trim();
        final made = await ref
            .read(statementAccountsProvider)
            .create(
              institutionCode: widget.bankKey,
              name: _nameCtl.text.trim(),
              currency: _mapping!.currency,
              last4: last4.isEmpty ? null : last4,
            );
        id = made.id;
        name = made.name;
      }
      final summary = await uc.run(
        _reading!,
        _mapping!,
        accountId: id!,
        confirmedYear: _year,
        decisions: Map.of(_decisions),
        keepDuplicates: Set.of(_keepDuplicates),
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => ImportDoneScreen(
            outcome: ImportOutcome(
              imported: summary.imported,
              earliest: summary.earliest,
              latest: summary.latest,
              cardName: name,
            ),
            cardName: name,
            onReview: widget.onReview,
            onOpenCard: widget.onOpenCard,
          ),
          fullscreenDialog: true,
        ),
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.review;
        _failure = _Failure.save;
      });
    }
  }

  void _back() {
    if (_phase == _Phase.review || _phase == _Phase.mapping) {
      setState(() {
        _phase = _Phase.choose;
        _reading = null;
        _parsed = null;
        _failure = null;
      });
      return;
    }
    Navigator.of(context).maybePop();
  }

  // ------------------------------------------------------------------ build

  StatementPasswordLabels _passwordLabels(AppLocalizations l) =>
      StatementPasswordLabels(
        title: l.exportsImportPasswordTitle,
        body: l.exportsImportPasswordBody,
        fieldLabel: l.exportsImportPasswordLabel,
        wrongHint: l.exportsImportPasswordWrong,
        confirm: l.commonActionContinue,
        cancel: l.commonActionCancel,
      );

  StatementMappingLabels _mappingLabels(AppLocalizations l) =>
      StatementMappingLabels(
        title: l.stmtMapTitle,
        hint: l.stmtMapHint,
        columnTitle: (n) => l.stmtMapColumn('$n'),
        roleName: (r) => switch (r) {
          StatementColumnRole.date => l.stmtMapRoleDate,
          StatementColumnRole.description => l.stmtMapRoleDescription,
          StatementColumnRole.debit => l.stmtMapRoleDebit,
          StatementColumnRole.credit => l.stmtMapRoleCredit,
          StatementColumnRole.amount => l.stmtMapRoleAmount,
          StatementColumnRole.balance => l.stmtMapRoleBalance,
          StatementColumnRole.ignore => l.stmtMapRoleIgnore,
        },
        dayFirstLabel: l.stmtMapDayFirst,
        currencyLabel: l.stmtMapCurrency,
        confirm: l.commonActionContinue,
        invalidHint: l.stmtMapInvalid,
      );

  String _failureText(AppLocalizations l, _Failure f) => switch (f) {
    _Failure.noRows => l.stmtImportErrNoRows,
    _Failure.noText => l.stmtImportErrNoText,
    _Failure.noOcr => l.stmtImportErrNoOcr,
    _Failure.unreadable => l.exportsImportFailed,
    _Failure.password => l.stmtImportErrPassword,
    _Failure.wrongPassword => l.exportsImportPasswordWrong,
    _Failure.save => l.stmtImportErrSave,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final review = _phase == _Phase.review || _phase == _Phase.saving;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    ZSpacing.screen,
                    ZSpacing.sm,
                    ZSpacing.screen,
                    ZSpacing.sm,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ImportRoundButton(
                      icon: Icons.chevron_left,
                      label: l.commonActionBackA11y,
                      onTap: _back,
                    ),
                  ),
                ),
                Expanded(
                  child: switch (_phase) {
                    _Phase.mapping => StatementMappingStep(
                      table: _reading!.table,
                      labels: _mappingLabels(l),
                      currency: _mapping!.currency,
                      currencies: _currencyChoices(),
                      onConfirm: _enterReview,
                    ),
                    _Phase.review || _Phase.saving => _reviewList(l, c),
                    _ => _chooseList(l, c),
                  },
                ),
                if (review) _confirmBar(l, c),
              ],
            ),
            if (_phase == _Phase.reading || _phase == _Phase.saving)
              Positioned.fill(
                child: ColoredBox(
                  color: c.bg.withValues(alpha: 0.85),
                  child: Center(
                    child: Semantics(
                      liveRegion: true,
                      label: l.exportsImportParsing,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WorkingBird(
                            busy: true,
                            moment: _phase == _Phase.saving
                                ? ZaghlolMoment.counting
                                : ZaghlolMoment.scanning,
                            size: 72,
                          ),
                          const SizedBox(height: ZSpacing.md),
                          Text(
                            _phase == _Phase.saving
                                ? l.exportsImportImporting
                                : l.exportsImportParsing,
                            style: ZType.body.copyWith(color: c.text),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Currency> _currencyChoices() {
    final cur = _mapping?.currency;
    return [
      for (final code in _commonCurrencies) Currency.of(code),
      if (cur != null && !_commonCurrencies.contains(cur.code)) cur,
    ];
  }

  Widget _chooseList(AppLocalizations l, ZColors c) => ListView(
    padding: const EdgeInsetsDirectional.fromSTEB(
      ZSpacing.screen,
      ZSpacing.sm,
      ZSpacing.screen,
      ZSpacing.xl,
    ),
    children: [
      Semantics(
        header: true,
        child: Text(
          l.stmtImportTitle(widget.bankName),
          style: ZType.display.copyWith(color: c.text),
        ),
      ),
      const SizedBox(height: ZSpacing.sm),
      Text(l.stmtImportSub, style: ZType.body.copyWith(color: c.textMuted)),
      const SizedBox(height: ZSpacing.lg),
      if (_failure != null) ...[
        ZBanner(tone: ZBannerTone.error, message: _failureText(l, _failure!)),
        const SizedBox(height: ZSpacing.lg),
      ],
      ZButton(
        key: const ValueKey('pickPdf'),
        label: l.stmtImportPickPdf,
        icon: Icons.picture_as_pdf_outlined,
        expand: true,
        onPressed: () => _pick(pdf: true),
      ),
      const SizedBox(height: ZSpacing.md),
      ZButton(
        key: const ValueKey('pickImages'),
        label: l.stmtImportPickImages,
        icon: Icons.photo_library_outlined,
        variant: ZButtonVariant.secondary,
        expand: true,
        onPressed: () => _pick(pdf: false),
      ),
    ],
  );

  Widget _reviewList(AppLocalizations l, ZColors c) {
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final hidden = ref.watch(hideAmountsProvider);
    String money(Money m) => MoneyFormat.format(
      m,
      languageCode: lang,
      digits: digits,
      hidden: hidden,
    );
    String count(int n) => digits.render('$n');

    final flagged = _flaggedNumbers;
    final answer = <StatementRowView>[];
    final rows = <StatementRowView>[];
    final dups = <StatementRowView>[];
    for (final r in _allRows) {
      final d = _decisions[r.number];
      final isFlagged = flagged.contains(r.number);
      final skipped = d == StatementReviewChoice.skip;
      final isExpense = switch (d) {
        StatementReviewChoice.asExpense => true,
        StatementReviewChoice.asIncome => false,
        _ => r.isExpense,
      };
      final known = r.directionKnown || d != null && !skipped;
      final undecided = isFlagged && d == null;
      final dup =
          !undecided &&
          !skipped &&
          _duplicateRows.contains(r.number) &&
          !_keepDuplicates.contains(r.number);
      final view = StatementRowView(
        number: r.number,
        date: ZDateFormat.date(
          DateTime(r.date.year, r.date.month, r.date.day),
          lang,
          digits,
        ),
        description: r.description,
        amount: money(known && isExpense ? -r.amount : r.amount),
        isExpense: isExpense,
        directionKnown: known,
        need: !undecided
            ? StatementRowNeed.none
            : (r.review == StatementReviewReason.directionUnknown
                  ? StatementRowNeed.direction
                  : StatementRowNeed.balance),
        skipped: skipped,
        duplicate: dup,
      );
      (undecided ? answer : (dup ? dups : rows)).add(view);
    }

    final accounts = _matching;
    final cur = _mapping!.currency;
    final items = <Widget>[
      Semantics(
        header: true,
        child: Text(
          l.stmtImportReviewTitle,
          style: ZType.display.copyWith(color: c.text),
        ),
      ),
      const SizedBox(height: ZSpacing.xs),
      Text(
        l.stmtImportNothingSaved,
        style: ZType.body.copyWith(color: c.textMuted),
      ),
      const SizedBox(height: ZSpacing.md),
      if (_failure == _Failure.save) ...[
        ZBanner(
          tone: ZBannerTone.error,
          message: _failureText(l, _Failure.save),
        ),
        const SizedBox(height: ZSpacing.md),
      ],
      if (_needsYear) ...[
        StatementYearPrompt(
          years: _yearChoices(),
          selected: _year,
          label: (y) => digits.render('$y'),
          onSelected: _setYear,
        ),
        const SizedBox(height: ZSpacing.md),
      ],
      _accountCard(l, c, accounts, cur),
      if (answer.isNotEmpty) ...[
        StatementSectionHeader(l.stmtImportSectionAnswer(count(answer.length))),
        for (final v in answer) _tile(l, v),
      ],
      if (rows.isNotEmpty) ...[
        StatementSectionHeader(l.stmtImportSectionRows(count(rows.length))),
        for (final v in rows) _tile(l, v),
      ],
      if (dups.isNotEmpty) ...[
        StatementSectionHeader(l.stmtImportSectionDup(count(dups.length))),
        for (final v in dups) _tile(l, v),
      ],
    ];
    return ListView.builder(
      padding: const EdgeInsetsDirectional.fromSTEB(
        ZSpacing.screen,
        ZSpacing.sm,
        ZSpacing.screen,
        ZSpacing.xl,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
    );
  }

  List<int> _yearChoices() {
    final anchor = _reading!.table.anchorYear ?? DateTime.now().year;
    return [anchor, anchor - 1, anchor - 2];
  }

  Widget _tile(AppLocalizations l, StatementRowView v) => StatementRowTile(
    key: ValueKey('row_${v.number}'),
    row: v,
    actions: StatementRowActions(
      onKeep: () => _decide(v.number, StatementReviewChoice.keep),
      onOut: () => _decide(v.number, StatementReviewChoice.asExpense),
      onIn: () => _decide(v.number, StatementReviewChoice.asIncome),
      onSkip: () => _decide(v.number, StatementReviewChoice.skip),
      onUndo: () => _decide(v.number, null),
      onAddAnyway: () {
        setState(() => _keepDuplicates.add(v.number));
      },
      onMenu: () => _menu(l, v),
    ),
  );

  void _menu(AppLocalizations l, StatementRowView v) {
    showZSheet<void>(
      context: context,
      title: l.stmtImportRowEdit,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZListRow(
            title: l.stmtImportChoiceOut,
            enabled: !(v.directionKnown && v.isExpense),
            onTap: () {
              Navigator.of(ctx).pop();
              _decide(v.number, StatementReviewChoice.asExpense);
            },
          ),
          ZListRow(
            title: l.stmtImportChoiceIn,
            enabled: !(v.directionKnown && !v.isExpense),
            onTap: () {
              Navigator.of(ctx).pop();
              _decide(v.number, StatementReviewChoice.asIncome);
            },
          ),
          ZListRow(
            title: l.stmtImportChoiceSkip,
            onTap: () {
              Navigator.of(ctx).pop();
              _decide(v.number, StatementReviewChoice.skip);
            },
          ),
        ],
      ),
    );
  }

  Widget _accountCard(
    AppLocalizations l,
    ZColors c,
    List<StatementAccountChoice> accounts,
    Currency cur,
  ) {
    return ZCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              l.stmtImportAccountTitle,
              style: ZType.titleSmall.copyWith(color: c.text),
            ),
          ),
          const SizedBox(height: ZSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.stmtImportCurrencyLabel,
                  style: ZType.bodySmall.copyWith(color: c.textMuted),
                ),
              ),
              DropdownButton<Currency>(
                key: const ValueKey('stmtCurrency'),
                value: cur,
                items: [
                  for (final x in _currencyChoices())
                    DropdownMenuItem(value: x, child: Text(x.code)),
                ],
                onChanged: (v) {
                  if (v != null && v != cur) _setCurrency(v);
                },
              ),
            ],
          ),
          if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
              child: Text(
                l.stmtImportAccountNoneYet(cur.code),
                style: ZType.bodySmall.copyWith(color: c.textMuted),
              ),
            ),
          Wrap(
            spacing: ZSpacing.sm,
            runSpacing: ZSpacing.sm,
            children: [
              for (final a in accounts)
                ZChip(
                  key: ValueKey('acct_${a.id}'),
                  label: a.name,
                  selected: !_newAccount && _accountId == a.id,
                  onTap: () {
                    setState(() {
                      _newAccount = false;
                      _accountId = a.id;
                    });
                    _refreshDuplicates();
                  },
                ),
              ZChip(
                key: const ValueKey('acct_new'),
                label: l.stmtImportAccountNew,
                icon: Icons.add,
                selected: _newAccount,
                onTap: () {
                  setState(() {
                    _newAccount = true;
                    if (_nameCtl.text.isEmpty) _nameCtl.text = widget.bankName;
                  });
                  _refreshDuplicates();
                },
              ),
            ],
          ),
          if (_newAccount) ...[
            const SizedBox(height: ZSpacing.md),
            TextField(
              key: const ValueKey('acctName'),
              controller: _nameCtl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: l.stmtImportAccountName),
            ),
            const SizedBox(height: ZSpacing.sm),
            TextField(
              key: const ValueKey('acctLast4'),
              controller: _last4Ctl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l.stmtImportAccountLast4,
                counterText: '',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _confirmBar(AppLocalizations l, ZColors c) {
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final blocked = _blocked(l);
    final n = _toAdd;
    return Material(
      color: c.surface,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (blocked != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
                child: Text(
                  blocked,
                  textAlign: TextAlign.center,
                  style: ZType.bodySmall.copyWith(color: c.textMuted),
                ),
              ),
            ZButton(
              key: const ValueKey('stmtConfirm'),
              label: l.importFlowConfirm(n, digits.render('$n')),
              expand: true,
              onPressed: blocked == null && _phase == _Phase.review
                  ? _confirm
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
