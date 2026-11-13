// T-110: the Ask Zaghlol grammar against the synthetic utterance set
// (test/fixtures/chat/ask_utterances.tsv, written by the T-110 builder, not
// real user questions). Table-driven: utterance -> intent + slots.

import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

const entities = AskEntities(
  categories: [
    AskEntity('sys:dining', ['اكل', 'مطاعم', 'food', 'coffee', 'قهوة']),
    AskEntity('sys:groceries', ['سوبرماركت', 'groceries']),
    AskEntity('sys:transport', ['مواصلات', 'بنزين', 'fuel', 'transport']),
    AskEntity('sys:bills', ['فواتير', 'bills']),
  ],
  merchants: [
    AskEntity('carrefour', ['Carrefour', 'كارفور'], partial: true),
    AskEntity('uber', ['Uber', 'اوبر'], partial: true),
    AskEntity('talabat', ['Talabat', 'طلبات'], partial: true),
    AskEntity('amazon', ['Amazon', 'امازون'], partial: true),
  ],
  accounts: [
    AskEntity('a_cib_debit', ['CIB Debit'], partial: true),
    AskEntity('a_cib_credit', ['CIB Credit'], partial: true),
    AskEntity('a_misr', ['Banque Misr', 'بنك مصر'], partial: true),
    AskEntity('a_voda', ['فودافون كاش', 'Vodafone Cash'], partial: true),
  ],
);

String period(AskPeriod? p) {
  if (p == null) return '-';
  final k = p.kind.name;
  return switch (p.kind) {
    AskPeriodKind.lastDays => '$k:${p.count}',
    AskPeriodKind.monthOfYear =>
      p.year == null ? '$k:${p.month}' : '$k:${p.month}:${p.year}',
    AskPeriodKind.allTime => k,
    _ => '$k:${p.offset}',
  };
}

String ids(Set<String> s) => s.isEmpty ? '-' : (s.toList()..sort()).join(',');

void main() {
  final lines = File('test/fixtures/chat/ask_utterances.tsv')
      .readAsLinesSync()
      .where((l) => !l.startsWith('#') && l.isNotEmpty)
      .toList();

  test('the set has at least 300 utterances', () {
    expect(lines.length, greaterThanOrEqualTo(300));
  });

  test('every fixture row parses to its expected intent and slots', () {
    final failures = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final c = lines[i].split('\t');
      final r = parseAskQuestion(c[0], entities: entities);
      final String got;
      final String want;
      if (c[1].startsWith('!')) {
        want = c[1];
        got = r is AskUnrecognized ? '!${r.reason.name}' : 'understood';
      } else {
        want = c.sublist(1).join('|');
        got = switch (r) {
          AskUnderstood u =>
            '${u.intent.name}|${period(u.slots.period)}|'
                '${period(u.slots.compareWith)}|${u.slots.categoryId ?? '-'}|'
                '${ids(u.slots.merchantIds)}|${ids(u.slots.accountIds)}|'
                '${u.slots.currencyCode ?? '-'}|${u.slots.limit ?? '-'}|'
                '${u.slots.periodDefaulted ? 1 : 0}',
          AskUnrecognized u => '!${u.reason.name}',
        };
      }
      if (got != want) failures.add('row ${i + 2}: want $want got $got');
    }
    // Row numbers only: the utterances are never printed.
    final pass = lines.length - failures.length;
    // ignore: avoid_print
    print('ask fixtures: $pass/${lines.length}');
    expect(failures, isEmpty, reason: failures.take(60).join('\n'));
  });

  group('never throws, never fabricates', () {
    test('blank and control input', () {
      for (final s in ['', '   ', '\n\t', '\u0000\u0001\u0002', '‏‎']) {
        expect(parseAskQuestion(s), isA<AskUnrecognized>());
      }
    });

    test('long and hostile input stays bounded', () {
      final sw = Stopwatch()..start();
      for (final s in [
        'ا' * 100000,
        'صرفت ' * 5000,
        '😀' * 400,
        '${'(a+)+' * 100}b',
        List.filled(200, 'x').join(' '),
        '\u0000' * 1000,
      ]) {
        final r = parseAskQuestion(s, entities: entities);
        expect(r, isA<AskUnrecognized>());
      }
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('word cap: cues after the cap are ignored', () {
      final q = '${List.filled(maxAskTokens, 'ايه').join(' ')} صرفت';
      expect(parseAskQuestion(q), isA<AskUnrecognized>());
    });

    test('an oversized entity list is capped, not trusted', () {
      final many = [
        for (var i = 0; i < maxAskEntities; i++) AskEntity('m$i', ['store$i']),
        const AskEntity('late', ['uniquename']),
      ];
      final r = parseAskQuestion(
        'صرفت كام على uniquename',
        entities: AskEntities(merchants: many),
      );
      expect(r, isA<AskUnrecognized>());
    });

    test('Arabic-Indic digits equal Western digits', () {
      AskSlots slots(String q) =>
          (parseAskQuestion(q, entities: entities) as AskUnderstood).slots;
      expect(
        slots('اخر ٣٠ يوم صرفت كام').period,
        slots('اخر 30 يوم صرفت كام').period,
      );
    });

    test('the result never prints the question or the names', () {
      final r = parseAskQuestion('صرفت كام على كارفور', entities: entities);
      expect(r.toString(), isNot(contains('كارفور')));
      expect(entities.merchants.first.toString(), isNot(contains('Carrefour')));
    });

    test('a question never yields a number: only intents and slots', () {
      // The parser has no amounts in its output type at all; an unknown
      // question is AskUnrecognized (FR-CHAT-03).
      expect(parseAskQuestion('كام سعر الدهب'), isA<AskUnrecognized>());
    });
  });

  test('chips list is the closed set the app maps to keys', () {
    expect(AskChip.values.length, 10);
  });
}
