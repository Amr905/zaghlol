// T-331: phone PlanValidator, template grammar, number words and the
// generated constants. The vectors are the same file the .NET tests use.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../tool/gen_plan_schema.dart';

const _schemaPath = '../../backend/contracts/ask-plan-v1.schema.json';
const _vectorsPath =
    '../../backend/tests/Zaghlol.Contract.Tests/vectors/ask-plan-v1.json';

Map<String, Object?> _load(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

String _spend(String filter, {String period = 'month'}) => jsonEncode({
  'v': 1,
  'plan': 'PL-SPEND',
  'p': {
    'period': {'k': period, 'o': 0, 'n': null, 'm': null, 'y': null},
    'filter': jsonDecode(filter),
  },
  't': null,
});

void main() {
  final vectors = _load(_vectorsPath);
  final schema = _load(_schemaPath);
  final aliases = [
    for (final a in (vectors['registryAliases']! as Map)['aliases'] as List)
      a as String,
  ];
  final validator = PlanValidator(extraAliases: aliases);

  group('shared vectors (same outcome as the .NET validator)', () {
    final plans = (vectors['plans']! as List).cast<Map<String, Object?>>();
    test('vector count sanity', () => expect(plans.length, greaterThan(60)));
    for (final v in plans) {
      test(v['id']! as String, () {
        final expect_ = v['expect']! as Map<String, Object?>;
        final r = validator.validate(
          v['plan'],
          sent: v['sent']! as String,
          lang: v['lang']! as String,
        );
        if (expect_['outcome'] == 'accept') {
          expect(r.rejected, isFalse, reason: '${r.failedStep} ${r.reason}');
        } else {
          expect(r.rejected, isTrue);
          expect(r.failedStep, expect_['step']);
          expect(r.reason, expect_['reason']);
          expect(r.plan, isA<PlanFallback>());
        }
      });
    }
  });

  group('normalisation vectors (mention substring, step 3)', () {
    final cases = ((vectors['normalisation']! as Map)['cases']! as List)
        .cast<Map<String, Object?>>();
    for (final c in cases) {
      test(c['id']! as String, () {
        final m = foldKey(c['mention']! as String);
        final got = m.isNotEmpty && foldKey(c['sent']! as String).contains(m);
        expect(got, c['expect']);
      });
    }
  });

  group('template vectors (step 6, grammar)', () {
    final ts = (vectors['templates']! as List).cast<Map<String, Object?>>();
    for (final t in ts) {
      test(t['id']! as String, () {
        final tt = t['t']! as Map<String, Object?>;
        final got = TemplateGrammar.check(
          plan: t['plan']! as String,
          requestLang: t['requestLang']! as String,
          templateLang: tt['lang']! as String,
          text: tt['text']! as String,
        );
        expect(got, t['expect'] == 'ok' ? isNull : t['expect']);
      });
    }

    test('every rule of the vectors has at least one rejecting vector', () {
      final rules = ((vectors['templateRules']! as Map)['order']! as List)
          .map((r) => 'TEMPLATE_$r')
          .toSet();
      final covered = ts.map((t) => t['expect']).toSet();
      expect(rules.difference(covered.cast<String>()), isEmpty);
    });

    test('drops only the template, keeps the plan (no throw)', () {
      final r = validator.validate(
        jsonDecode(
          jsonEncode({
            'v': 1,
            'plan': 'PL-SAVED',
            'p': {
              'period': {'k': 'month', 'o': 0, 'n': null, 'm': null, 'y': null},
            },
            't': {'lang': 'en', 'text': 'See https://x.example {amount}'},
          }),
        ),
        sent: 'how much did I save?',
        lang: 'en',
      );
      expect(r.rejected, isFalse);
      expect(r.plan, isA<PlanSaved>());
      expect(r.template, isNull);
      expect(r.templateReason, 'TEMPLATE_LINK');
    });

    test(
      'digits, URLs, markup, unknown blanks, placeholders: both languages',
      () {
        const bad = [
          'spent 500 {amount}',
          'spent ٥٠٠ {amount}',
          'see x.com {amount}',
          '[link] {amount}',
          '**bold** {amount}',
          'hi {unknown}',
          'hi {amount} {amount}',
          'hi ⟦CARD_1⟧ {amount}',
          'mail a@b {amount}',
        ];
        for (final lang in ['en', 'ar']) {
          for (final b in bad) {
            expect(
              TemplateGrammar.check(
                plan: 'PL-SAVED',
                requestLang: lang,
                templateLang: lang,
                text: lang == 'ar' ? b.replaceFirst('spent', 'صرفت') : b,
              ),
              isNotNull,
              reason: '$lang: $b',
            );
          }
        }
      },
    );
  });

  group('phone-only checks (AC2)', () {
    test('account:"CIB" in plain text is a schema failure', () {
      final r = validator.validate(
        jsonDecode(
          _spend(
            '{"slug":null,"ref":null,"mention":null,"currency":null,"account":"CIB"}',
          ),
        ),
        sent: 'how much from my CIB account?',
        lang: 'en',
      );
      expect(r.reason, 'SCHEMA_INVALID');
      expect(r.plan, isA<PlanFallback>());
    });

    test('mention naming a bank is PLAIN_NAME even if in the text', () {
      final r = validator.validate(
        jsonDecode(
          _spend('{"slug":null,"ref":null,"mention":"CIB","currency":null}'),
        ),
        sent: 'how much on CIB?',
        lang: 'en',
      );
      expect(r.reason, 'PLAIN_NAME');
    });

    test("mention naming the user's own account or merchant is refused", () {
      final v = PlanValidator(
        sources: const StaticMaskSources(
          accounts: [MaskAccount(id: 'a', label: 'Rent Wallet')],
          merchants: [
            MaskMerchant('m', ['Zawya Coffee']),
          ],
        ),
      );
      for (final name in ['Rent Wallet', 'zawya coffee']) {
        final r = v.validate(
          jsonDecode(
            _spend(
              '{"slug":null,"ref":null,"mention":"$name","currency":null}',
            ),
          ),
          sent: 'how much on $name?',
          lang: 'en',
        );
        expect(r.reason, 'PLAIN_NAME', reason: name);
      }
    });

    test('ref not in the sent text', () {
      final r = validator.validate(
        jsonDecode(
          _spend(
            '{"slug":null,"ref":"⟦CARD_2⟧","mention":null,"currency":null}',
          ),
        ),
        sent: 'spent on ⟦CARD_1⟧?',
        lang: 'en',
      );
      expect(r.reason, 'REF_NOT_IN_TEXT');
    });

    test('ref in the text but not in the request map', () {
      const map = MaskMap({'⟦CARD_1⟧': MaskTarget(kind: MaskKind.card)});
      Map<String, Object?> plan(String ref) => jsonDecode(
        _spend('{"slug":null,"ref":"$ref","mention":null,"currency":null}'),
      ) as Map<String, Object?>;
      final ok = validator.validate(
        plan('⟦CARD_1⟧'),
        sent: 'spent on ⟦CARD_1⟧ and ⟦CARD_2⟧?',
        lang: 'en',
        map: map,
      );
      expect(ok.rejected, isFalse);
      final bad = validator.validate(
        plan('⟦CARD_2⟧'),
        sent: 'spent on ⟦CARD_1⟧ and ⟦CARD_2⟧?',
        lang: 'en',
        map: map,
      );
      expect(bad.reason, 'REF_NOT_IN_MAP');
    });

    test('mention:"Carrefour" for "how much on groceries?" falls back', () {
      final r = validator.validate(
        jsonDecode(
          _spend(
            '{"slug":null,"ref":null,"mention":"Carrefour","currency":null}',
          ),
        ),
        sent: 'how much on groceries?',
        lang: 'en',
      );
      expect(r.reason, 'MENTION_NOT_IN_TEXT');
      expect(r.failedStep, 3);
    });

    test('a template naming a bank of the user is dropped', () {
      final r = validator.validate(
        jsonDecode(
          jsonEncode({
            'v': 1,
            'plan': 'PL-SAVED',
            'p': {
              'period': {'k': 'month', 'o': 0, 'n': null, 'm': null, 'y': null},
            },
            't': {'lang': 'en', 'text': 'Your CIB savings are {amount}'},
          }),
        ),
        sent: 'how much did I save?',
        lang: 'en',
      );
      expect(r.rejected, isFalse);
      expect(r.template, isNull);
      expect(r.templateReason, 'TEMPLATE_PLAIN_NAME');
    });

    test('currency:"CIB" is a plain name (any string of p)', () {
      final r = validator.validate(
        jsonDecode(
          _spend('{"slug":null,"ref":null,"mention":null,"currency":"CIB"}'),
        ),
        sent: 'how much did I spend?',
        lang: 'en',
      );
      expect(r.reason, 'PLAIN_NAME');
      expect(r.failedStep, 2);
    });

    test('currency null uses the primary currency for the fraction rule', () {
      Object? plan() => jsonDecode(
        jsonEncode({
          'v': 1,
          'plan': 'PL-WHATIF-SAVE',
          'p': {
            'amount': {'amount': '12.345', 'currency': null},
            'months': 6,
          },
          't': null,
        }),
      );
      expect(
        validator
            .validate(plan(), sent: 'save 12.345 for 6 months', lang: 'en')
            .rejected,
        isFalse,
      );
      expect(
        validator
            .validate(
              plan(),
              sent: 'save 12.345 for 6 months',
              lang: 'en',
              primaryCurrency: 'EGP',
            )
            .reason,
        'AMOUNT_FRACTION_TOO_LONG',
      );
    });

    test('never throws on garbage', () {
      for (final g in <Object?>[
        null,
        1,
        'x',
        <Object?>[],
        {'v': 1},
        {'v': 1, 'plan': 'PL-SPEND', 'p': 5, 't': null},
        {'v': 1.0, 'plan': 'PL-SAFE-SPEND', 'p': <String, Object?>{}, 't': 7},
      ]) {
        final r = validator.validate(g, sent: 'x', lang: 'en');
        expect(r.plan, isA<Plan>());
      }
    });

    test('toString of sensitive values is redacted', () {
      expect(
        const PlanFilter(mention: 'Carrefour').toString(),
        isNot(contains('Carrefour')),
      );
      expect(const PlanBalance('⟦CARD_1⟧').toString(), isNot(contains('CARD')));
    });
  });

  group('typed plans', () {
    test('whatIf cut parses with decimal-string amount', () {
      final r = validator.validate(
        jsonDecode(
          jsonEncode({
            'v': 1,
            'plan': 'PL-WHATIF-SAVE',
            'p': {
              'amount': {'amount': '1000', 'currency': 'EGP'},
              'months': 12,
            },
            't': null,
          }),
        ),
        sent: 'لو وفرت ألف جنيه كل شهر لمدة 12 شهر',
        lang: 'ar',
      );
      final p = r.plan as PlanWhatIfSave;
      expect(p.amount.amount, '1000');
      expect(planAmountToMinor(p.amount.amount, 2), 100000);
      expect(planAmountToMinor('12.345', 2), isNull);
      expect(planAmountToMinor('12.345', 3), 12345);
      expect(planAmountToMinor('500', 0), 500);
    });
  });

  group('generated constants', () {
    test('regenerating from the schema and vectors gives no diff (AC3)', () {
      final generated = generatePlanSchemaDart(
        File(_schemaPath).readAsStringSync(),
        File(_vectorsPath).readAsStringSync(),
      );
      expect(
        File('lib/chat/llm/plan_schema.g.dart').readAsStringSync(),
        generated,
        reason: 'run: dart run tool/gen_plan_schema.dart',
      );
    });

    test('plan names, slugs, version match the schema file', () {
      final props = schema['properties']! as Map<String, Object?>;
      expect(planNames, (props['plan']! as Map)['enum']);
      expect(
        planCategorySlugs,
        ((schema[r'$defs']! as Map)['CategorySlug']! as Map)['enum'],
      );
      expect(planVersion, vectors['planVersion']);
    });

    test('Dart enums equal the schema enums (no drift)', () {
      final defs = schema[r'$defs']! as Map<String, Object?>;
      List<Object?> en(String def, String prop) =>
          (((defs[def]! as Map)['properties']! as Map)[prop]! as Map)['enum']!
              as List<Object?>;
      expect([for (final e in PeriodKind.values) e.name], en('Period', 'k'));
      expect([
        for (final e in BreakdownBy.values) e.name,
      ], en('P_PL-BREAKDOWN', 'by'));
      expect([for (final e in TopOf.values) e.name], en('P_PL-TOPN', 'of'));
      expect([
        for (final e in AveragePer.values) e.name,
      ], en('P_PL-AVERAGE', 'per'));
      expect([for (final e in WhatIfKind.values) e.name], en('Mode', 'kind'));
      expect([
        for (final e in FallbackReason.values) e.name,
      ], en('P_PL-FALLBACK', 'reason'));
      expect([
        for (final e in RefuseReason.values) e.name,
      ], en('P_PL-REFUSE', 'reason'));
    });

    test('every plan name has a typed class', () {
      final seen = <String>{};
      for (final p in const <Plan>[
        PlanSpend(PlanPeriod(kind: PeriodKind.day, offset: 0), PlanFilter.none),
        PlanCompare(
          PlanPeriod(kind: PeriodKind.day, offset: 0),
          PlanPeriod(kind: PeriodKind.day, offset: 0),
          PlanFilter.none,
        ),
        PlanBreakdown(
          PlanPeriod(kind: PeriodKind.day, offset: 0),
          BreakdownBy.category,
          1,
        ),
        PlanTopN(
          PlanPeriod(kind: PeriodKind.day, offset: 0),
          TopOf.merchant,
          1,
        ),
        PlanAverage(
          AveragePer.day,
          PlanPeriod(kind: PeriodKind.day, offset: 0),
          PlanFilter.none,
        ),
        PlanIncome(
          PlanPeriod(kind: PeriodKind.day, offset: 0),
          PlanFilter.none,
        ),
        PlanSaved(PlanPeriod(kind: PeriodKind.day, offset: 0)),
        PlanBillsDue(1),
        PlanBudgetLeft(null),
        PlanSafeSpend(),
        PlanBalance(null),
        PlanWhatIfCut(PlanFilter.none, PlanMode(kind: WhatIfKind.percent), 1),
        PlanWhatIfSave(PlanAmount('1', null), 1),
        PlanSuggest(null),
        PlanInvest(PlanInvestSource(InvestSourceKind.savedLastPeriod), [], 1),
        PlanFallback(FallbackReason.noData),
        PlanRefuse(RefuseReason.offTopic, selfHarm: false),
      ]) {
        seen.add(p.name);
      }
      expect(seen, planNames.toSet());
    });
  });

  group('number words', () {
    test('match the vectors list', () {
      final words = ((vectors['numberWords']! as Map)['words']! as Map)
          .cast<String, String>();
      expect(planNumberWords, {
        for (final e in words.entries) foldKey(e.key): e.value,
      });
    });

    test('whole words only', () {
      expect(numberWordValues(foldKey('ألف جنيه')), contains('1000'));
      expect(numberWordValues(foldKey('thousands')), isEmpty);
      expect(numberWordValues(foldKey('a Thousand')), contains('1000'));
    });
  });
}
