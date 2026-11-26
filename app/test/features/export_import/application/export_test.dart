import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:zaghlol/core/db/app_database.dart';
import 'package:zaghlol/core/db/daos/ai_merchant_suggestions_dao.dart';
import 'package:zaghlol/features/categorization/data/drift_ai_suggestion_states.dart';
import 'package:zaghlol/features/categorization/domain/ai_suggestion.dart';
import 'package:zaghlol/features/export_import/application/export.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/transactions/domain/transaction.dart';
import 'package:zaghlol/features/transactions/domain/transaction_repository.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

class _Repo implements TransactionRepository {
  _Repo(this.rows);
  final List<TransactionRecord> rows;
  @override
  Future<List<TransactionRecord>> query({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
    PageRequest page = const PageRequest(),
  }) async {
    // List order: newest first, then id (as the DAO).
    final sorted = [...rows]
      ..sort((a, b) {
        final c = b.occurredAt.compareTo(a.occurredAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    final after = page.after;
    final live = after == null
        ? sorted
        : sorted.where(
            (r) =>
                r.occurredAt.isBefore(after.occurredAt) ||
                (r.occurredAt == after.occurredAt &&
                    r.id.compareTo(after.id) > 0),
          );
    return live.skip(page.offset).take(page.limit).toList();
  }

  @override
  Future<int> count({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
  }) async => rows.length;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

/// Inserts a row at the front after the first page, as a capture running
/// during the export would.
class _ShiftingRepo extends _Repo {
  _ShiftingRepo(super.rows);
  int calls = 0;
  @override
  Future<List<TransactionRecord>> query({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
    PageRequest page = const PageRequest(),
  }) async {
    final r = await super.query(filter: filter, text: text, page: page);
    if (++calls == 1) rows.insert(0, _t(9999, at: DateTime.utc(2027)));
    return r;
  }
}

/// Deletes a row of the first page after it was read, as a delete running
/// during the export would.
class _DeletingRepo extends _Repo {
  _DeletingRepo(super.rows);
  int calls = 0;
  @override
  Future<List<TransactionRecord>> query({
    TransactionFilter filter = const TransactionFilter(),
    String? text,
    PageRequest page = const PageRequest(),
  }) async {
    final r = await super.query(filter: filter, text: text, page: page);
    if (++calls == 1) rows.removeWhere((x) => x.id == r.first.id);
    return r;
  }
}

class _States implements AiSuggestionStates {
  _States(this.states);
  final Map<String, AiSuggestionState> states;
  final List<Set<String>> asked = [];
  @override
  Future<Map<String, AiSuggestionState>> statesOf(
    Iterable<String> merchantNorms,
  ) async {
    asked.add(merchantNorms.toSet());
    return {
      for (final m in merchantNorms)
        if (states.containsKey(m)) m: states[m]!,
    };
  }
}

class _Dest implements ExportDestination {
  String? name;
  Uint8List? bytes;
  @override
  Future<void> write(String n, Uint8List b) async {
    name = n;
    bytes = b;
  }
}

TransactionRecord _t(
  int i, {
  String? merchant,
  String? note,
  String cur = 'EGP',
  int minor = 12345,
  DateTime? at,
  CategorySource categorySource = CategorySource.none,
  String? merchantNorm,
  String? pairId,
}) {
  final c = Currency.of(cur);
  return TransactionRecord(
    id: 't$i',
    accountId: 'a1',
    source: TxnSource.manual,
    direction: TxnDirection.expense,
    status: TxnStatus.posted,
    amount: Money(c, minor),
    occurredAt: at ?? DateTime.utc(2026, 1, 31, 23, 59),
    occurredTzOffsetMin: 120,
    merchantRaw: merchant,
    transferPairId: pairId,
    note: note,
    merchantNorm: merchantNorm,
    categorySource: categorySource,
    isUserVerified: true,
    isInternal: false,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

EntitlementState goldForTest() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  c
      .read(entitlementStateProvider.notifier)
      .applyVerified(verified: true, status: 'active');
  return c.read(entitlementStateProvider);
}

void main() {
  exportColumnConstantsTest();
  test('CSV has BOM, ISO dates, dot decimals, currency per row, Arabic', () {
    final bytes = encodeCsv([
      exportHeader,
      exportRow(_t(1, merchant: 'مطعم، "الشاطر"', cur: 'KWD', minor: 1250)),
    ]);
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    final s = utf8.decode(bytes.sublist(3));
    expect(s, contains('2026-01-31T23:59:00.000Z'));
    expect(s, contains(',1.250,KWD,'));
    expect(s, contains('"مطعم، ""الشاطر"""'));
    expect(s.endsWith('\r\n'), isTrue);
  });

  test('amounts are exact and never converted (JPY, KWD, negative)', () {
    expect(exportRow(_t(1, cur: 'JPY', minor: 1500))[6], '1500');
    expect(exportRow(_t(1, cur: 'EGP', minor: -5))[6], '-0.05');
    expect(exportRow(_t(1, cur: 'USD', minor: 100))[7], 'USD');
  });

  test(
    'T-285 pair/kind: both legs share a pair id, ordinary rows empty',
    () async {
      final rows = [
        _t(1, pairId: 'px', cur: 'EGP'),
        _t(2, pairId: 'px', cur: 'USD'),
        _t(3, pairId: 'py'),
        _t(4, pairId: 'py'),
        _t(5),
      ];
      final svc = ExportService(
        _Repo(rows),
        pairKinds: (ids) async => {'px': 'fx_conversion', 'py': 'auto'},
      );
      final d = _Dest();
      await svc.export(
        entitlement: goldForTest(),
        filter: const TransactionFilter(),
        format: ExportFormat.csv,
        destination: d,
        warningAcknowledged: true,
      );
      final lines = utf8
          .decode(d.bytes!.sublist(3))
          .trim()
          .split('\r\n')
          .map((l) => l.split(','))
          .toList();
      expect(lines.first.sublist(14), ['pair', 'kind', 'category_source']);
      final byId = {for (final l in lines.skip(1)) l[0]: l};
      expect(byId['t1']![14], byId['t2']![14]);
      expect(byId['t1']![14], isNotEmpty);
      expect(byId['t1']![15], 'exchange');
      expect(byId['t2']![15], 'exchange');
      expect(byId['t3']![14], byId['t4']![14]);
      expect(byId['t3']![15], 'transfer');
      expect(byId['t3']![14], isNot(byId['t1']![14]));
      expect(byId['t5']![14], '');
      expect(byId['t5']![15], '');
    },
  );

  test('formula injection is neutralised in free text', () {
    for (final p in ['=1+1', '+1', '-1', '@x', '\t=x']) {
      final r = exportRow(_t(1, merchant: p, note: p));
      expect(r[10], "'$p");
      expect(r[13], "'$p");
    }
    expect(exportRow(_t(1, merchant: 'Safe'))[10], 'Safe');
    // Negative amounts stay numeric, not apostrophe-prefixed.
    expect(exportRow(_t(1, minor: -5))[6], '-0.05');
  });

  test('xlsx is a valid zip with escaped Arabic and numeric amount', () {
    final bytes = encodeXlsx([
      exportHeader,
      exportRow(_t(1, merchant: 'قهوة <&>')),
    ]);
    expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
    final s = utf8.decode(bytes, allowMalformed: true);
    expect(s, contains('xl/worksheets/sheet1.xml'));
    expect(s, contains('قهوة &lt;&amp;&gt;'));
    expect(s, contains('<c r="G2"><v>123.45</v></c>'));
  });

  test('Free gets preview only and nothing is written', () async {
    final repo = _Repo([for (var i = 0; i < 30; i++) _t(i)]);
    final d = _Dest();
    final out = await ExportService(repo).export(
      entitlement: EntitlementState.free,
      filter: const TransactionFilter(),
      format: ExportFormat.csv,
      destination: d,
      warningAcknowledged: true,
    );
    expect(out, isA<ExportPreview>());
    final p = out as ExportPreview;
    expect(p.rows.length, exportPreviewRows);
    expect(p.totalRows, 30);
    expect(d.bytes, isNull);
  });

  test('Gold needs warning ack, then writes via destination', () async {
    final repo = _Repo([for (var i = 0; i < 600; i++) _t(i)]);
    final d = _Dest();
    final svc = ExportService(repo);
    final gold = goldForTest();
    expect(
      await svc.export(
        entitlement: gold,
        filter: const TransactionFilter(),
        format: ExportFormat.csv,
        destination: d,
        warningAcknowledged: false,
      ),
      isA<ExportNeedsWarningAck>(),
    );
    expect(d.bytes, isNull);
    final out = await svc.export(
      entitlement: gold,
      filter: const TransactionFilter(),
      format: ExportFormat.xlsx,
      destination: d,
      warningAcknowledged: true,
      now: DateTime.utc(2026, 3, 4),
    );
    expect((out as ExportWritten).rowCount, 600);
    expect(d.name, 'zaghlol-export-20260304.xlsx');
  });

  test('FU-131: a row inserted mid-export never makes a duplicate', () async {
    final repo = _ShiftingRepo([for (var i = 0; i < 600; i++) _t(i)]);
    final d = _Dest();
    final out = await ExportService(repo).export(
      entitlement: goldForTest(),
      filter: const TransactionFilter(),
      format: ExportFormat.csv,
      destination: d,
      warningAcknowledged: true,
    );
    expect((out as ExportWritten).rowCount, 600);
    final text = utf8.decode(d.bytes!);
    expect(RegExp('t499,').allMatches(text).length, 1);
  });

  test(
    'FU-131: a row deleted mid-export never makes another one skipped',
    () async {
      final rows = [for (var i = 0; i < 600; i++) _t(i)];
      final ids = rows.map((r) => r.id).toList()..sort();
      final repo = _DeletingRepo(rows);
      final d = _Dest();
      final out = await ExportService(repo).export(
        entitlement: goldForTest(),
        filter: const TransactionFilter(),
        format: ExportFormat.csv,
        destination: d,
        warningAcknowledged: true,
      );
      // Offset paging would lose the first row of page two.
      expect((out as ExportWritten).rowCount, 600);
      final text = utf8.decode(d.bytes!);
      expect(text, contains('\r\n${ids[500]},'));
    },
  );

  test('FU-131: ids are neutralised like free text', () {
    final r = exportRow(
      TransactionRecord(
        id: '=HYPERLINK("x")',
        accountId: '+a1',
        categoryId: '@c',
        source: TxnSource.manual,
        direction: TxnDirection.expense,
        status: TxnStatus.posted,
        amount: Money(Currency.of('EGP'), 1),
        occurredAt: DateTime.utc(2026),
        occurredTzOffsetMin: 0,
        categorySource: CategorySource.user,
        isUserVerified: true,
        isInternal: false,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );
    expect(r[0], "'=HYPERLINK(\"x\")");
    expect(r[3], "'+a1");
    expect(r[11], "'@c");
  });
}

void exportColumnConstantsTest() {
  test('preview column constants match the header', () {
    expect(exportHeader[exportColDate], 'date_utc');
    expect(exportHeader[exportColAmount], 'amount');
    expect(exportHeader[exportColCurrency], 'currency');
    expect(exportHeader[exportColMerchant], 'merchant');
  });

  group('T-356 AC4: category_source (FR-LCAT-25)', () {
    test('the column is appended last; earlier positions unchanged', () {
      expect(exportHeader.last, 'category_source');
      expect(exportHeader, hasLength(17));
      expect(exportHeader.sublist(13), [
        'note',
        'pair',
        'kind',
        'category_source',
      ]);
      expect(exportRow(_t(1)), hasLength(17));
    });

    test('mapping: ai + unconfirmed (or no row, corrected, no_answer) is '
        'ai_unconfirmed; ai + confirmed is user_rule; others as stored', () {
      for (final s in [
        null,
        AiSuggestionState.unconfirmed,
        AiSuggestionState.corrected,
        AiSuggestionState.noAnswer,
      ]) {
        expect(
          exportCategorySource(CategorySource.ai, s),
          'ai_unconfirmed',
          reason: '$s',
        );
      }
      expect(
        exportCategorySource(CategorySource.ai, AiSuggestionState.confirmed),
        'user_rule',
      );
      for (final c in CategorySource.values) {
        if (c == CategorySource.ai) continue;
        for (final s in [null, ...AiSuggestionState.values]) {
          expect(exportCategorySource(c, s), c.code);
        }
      }
    });

    test('a Gold export: the unconfirmed AI row exports ai_unconfirmed, the '
        'confirmed one user_rule, a user rule as today; states are read once '
        'for the ai rows only', () async {
      final repo = _Repo([
        _t(1, categorySource: CategorySource.ai, merchantNorm: 'zawya coffee'),
        _t(2, categorySource: CategorySource.ai, merchantNorm: 'book corner'),
        _t(3, categorySource: CategorySource.userRule, merchantNorm: 'x shop'),
        _t(4, categorySource: CategorySource.catalog, merchantNorm: 'y shop'),
      ]);
      final states = _States({
        'zawya coffee': AiSuggestionState.unconfirmed,
        'book corner': AiSuggestionState.confirmed,
      });
      final d = _Dest();
      await ExportService(repo, aiStates: states).export(
        entitlement: goldForTest(),
        filter: const TransactionFilter(),
        format: ExportFormat.csv,
        destination: d,
        warningAcknowledged: true,
      );
      final lines = utf8.decode(d.bytes!.sublist(3)).split('\r\n');
      expect(lines.first, endsWith(',note,pair,kind,category_source'));
      final bySource = {
        for (final l in lines.skip(1).where((l) => l.isNotEmpty))
          l.split(',').first: l.split(',').last,
      };
      expect(bySource, {
        't1': 'ai_unconfirmed',
        't2': 'user_rule',
        't3': 'user_rule',
        't4': 'catalog',
      });
      expect(states.asked, [
        {'zawya coffee', 'book corner'},
      ]);
    });

    test('the Free preview carries the same column', () async {
      final out =
          await ExportService(
            _Repo([
              _t(1, categorySource: CategorySource.ai, merchantNorm: 'm m'),
            ]),
            aiStates: _States({}),
          ).export(
            entitlement: EntitlementState.free,
            filter: const TransactionFilter(),
            format: ExportFormat.csv,
            destination: _Dest(),
            warningAcknowledged: false,
          );
      expect((out as ExportPreview).rows.single.last, 'ai_unconfirmed');
    });

    test('DriftAiSuggestionStates reads the stored states', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customStatement(
        'INSERT INTO categories (id, system_code, name_ar, name_en, icon, '
        "color, bucket, sort) VALUES ('sys:dining', 'dining', 'x', 'x', 'i', "
        "'#000000', 'wants', 1)",
      );
      final dao = AiMerchantSuggestionsDao(db);
      for (final m in ['aa shop', 'bb shop']) {
        await dao.putAnswer(
          merchantNorm: m,
          categoryId: 'sys:dining',
          confidence: 90,
          source: AiSuggestionSourceCode.cache,
          at: 1,
        );
      }
      await dao.decide('bb shop', state: 'confirmed', at: 2);
      expect(
        await DriftAiSuggestionStates(db)
            .statesOf(['aa shop', 'bb shop', 'cc shop']),
        {
          'aa shop': AiSuggestionState.unconfirmed,
          'bb shop': AiSuggestionState.confirmed,
        },
      );
    });
  });
}
