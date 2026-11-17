import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

// SMS-fuzzy (PO 2026-11-16): the generic extractor on a corpus of synthetic,
// reworded bank messages (paraphrases of the PO's bank list and the HSBC
// wording, fields reordered or missing, AR and EN). Card digits, names,
// phone numbers and references are made up. Output prints ids and counts
// only, never message text.

const String _assets = '../../app/assets';
const String _corpusPath = 'test/fixtures/generic/fuzzy_corpus.json';
final DateTime _at = DateTime.utc(2026, 11, 14, 10);

Registry _registry() {
  final inst = <String, String>{};
  for (final f in Directory('$_assets/registry/institutions').listSync()) {
    if (f is File) {
      inst[f.uri.pathSegments.last] = f.readAsStringSync();
    }
  }
  return RegistryLoader.load(
    manifest: File('$_assets/registry/registry_manifest.json')
        .readAsStringSync(),
    shared: File('$_assets/registry/shared.json').readAsStringSync(),
    institutions: inst,
  ).registry!;
}

String _decimal(Money m) {
  final digits = m.minor.abs().toString().padLeft(m.currency.exponent + 1, '0');
  final cut = digits.length - m.currency.exponent;
  return m.currency.exponent == 0
      ? digits
      : '${digits.substring(0, cut)}.${digits.substring(cut)}';
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

ParseResult _generic(String body, Registry registry) {
  final folded = foldKeyIndexed(body);
  return parseGeneric(
    body: body,
    folded: folded,
    receivedAt: _at,
    language: detectLanguage(folded.text).name,
    globalLast4: registry.shared.globalLast4,
    cleaning: registry.shared.merchantCleaning,
  );
}

/// Field values as text, null when absent.
Map<String, String?> _fields(ParseResult r) {
  if (r is! ParseGeneric) {
    return const {};
  }
  return {
    'amount': _decimal(r.amount),
    'currency': r.amount.currency.code,
    'direction': r.direction?.name,
    'event': r.event?.name,
    'last4': r.last4,
    'merchant': r.merchant?.display,
    'date': r.dateRead ? _day(r.occurredAt) : null,
    'ref': r.reference,
  };
}

final class _Score {
  int tp = 0;
  int fp = 0;
  int fn = 0;
  final List<String> misses = [];

  double get precision => tp + fp == 0 ? 1 : tp / (tp + fp);
  double get recall => tp + fn == 0 ? 1 : tp / (tp + fn);
}

const List<String> _fieldNames = [
  'amount',
  'currency',
  'direction',
  'event',
  'last4',
  'merchant',
  'date',
  'ref',
];

void main() {
  final registry = _registry();
  final pipeline = ParsingPipeline(registry);
  final corpus = (jsonDecode(File(_corpusPath).readAsStringSync()) as List)
      .cast<Map<String, Object?>>();

  test('corpus size', () {
    expect(corpus.length, greaterThanOrEqualTo(80));
    final ids = {for (final c in corpus) c['id']};
    expect(ids.length, corpus.length, reason: 'duplicate ids');
  });

  Map<String, _Score> score(Iterable<Map<String, Object?>> cases) {
    final scores = {for (final f in _fieldNames) f: _Score()};
    for (final c in cases) {
      final id = c['id']! as String;
      final expected = (c['expect']! as Map).cast<String, Object?>();
      final got = _fields(_generic(c['body']! as String, registry));
      for (final f in _fieldNames) {
        var e = expected[f] as String?;
        if (f == 'merchant' && e != null) {
          // The corpus names the merchant as written; the cleaner's display
          // form is what both sides compare (extraction, not cleaning).
          e = cleanMerchant(
            foldForMatching(e),
            config: registry.shared.merchantCleaning,
          ).display;
        }
        final p = got[f];
        final s = scores[f]!;
        if (e != null && p == e) {
          s.tp++;
        } else {
          if (p != null) s.fp++;
          if (e != null) s.fn++;
          if (p != null || e != null) s.misses.add(id);
        }
      }
    }
    return scores;
  }

  String table(String title, int n, Map<String, _Score> scores) {
    final out = StringBuffer(
      '$title ($n messages)\n'
      'field      precision  recall   tp  fp  fn\n',
    );
    for (final f in _fieldNames) {
      final s = scores[f]!;
      out.writeln(
        '${f.padRight(10)} '
        '${(s.precision * 100).toStringAsFixed(1).padLeft(8)}% '
        '${(s.recall * 100).toStringAsFixed(1).padLeft(6)}% '
        '${s.tp.toString().padLeft(4)}'
        '${s.fp.toString().padLeft(4)}'
        '${s.fn.toString().padLeft(4)}'
        '${s.misses.isEmpty ? '' : '  misses: ${s.misses.join(', ')}'}',
      );
    }
    return out.toString();
  }

  final tuned = [
    for (final c in corpus)
      if (c['split'] != 'holdout') c,
  ];
  final holdout = [
    for (final c in corpus)
      if (c['split'] == 'holdout') c,
  ];

  test('per-field precision and recall, tuning set (printed)', () {
    final scores = score(tuned);
    // Ids and counts only.
    // ignore: avoid_print
    print(table('generic fuzzy corpus, tuning set', tuned.length, scores));
    // Money fields: wrong is worse than missing.
    expect(scores['amount']!.precision, greaterThanOrEqualTo(0.98));
    expect(scores['amount']!.recall, greaterThanOrEqualTo(0.95));
    expect(scores['currency']!.precision, greaterThanOrEqualTo(0.98));
    expect(scores['direction']!.precision, greaterThanOrEqualTo(0.95));
    expect(scores['direction']!.recall, greaterThanOrEqualTo(0.85));
    expect(scores['last4']!.precision, greaterThanOrEqualTo(0.98));
    expect(scores['last4']!.recall, greaterThanOrEqualTo(0.9));
    expect(scores['merchant']!.precision, greaterThanOrEqualTo(0.85));
    expect(scores['merchant']!.recall, greaterThanOrEqualTo(0.8));
    expect(scores['date']!.precision, greaterThanOrEqualTo(0.98));
    expect(scores['date']!.recall, greaterThanOrEqualTo(0.9));
    expect(scores['ref']!.precision, greaterThanOrEqualTo(0.98));
  });

  test('per-field precision and recall, hold-out set (printed)', () {
    // Written after tuning and not tuned against: the honest number.
    expect(holdout.length, greaterThanOrEqualTo(20));
    final scores = score(holdout);
    // ignore: avoid_print
    print(table('generic fuzzy corpus, hold-out set', holdout.length, scores));
    expect(scores['amount']!.precision, greaterThanOrEqualTo(0.95));
    expect(scores['currency']!.precision, greaterThanOrEqualTo(0.95));
    expect(scores['direction']!.precision, greaterThanOrEqualTo(0.9));
    expect(scores['last4']!.precision, greaterThanOrEqualTo(0.95));
  });

  group('known bank sender: reworded messages still give the fields', () {
    // A known sender whose wording misses every template falls to the
    // generic reader; a template match is also fine. Either way the amount
    // and currency are the corpus ones.
    for (final c in corpus.take(20)) {
      test(c['id']! as String, () {
        final r = pipeline.parse(
          ParseRequest(
            body: c['body']! as String,
            source: 'HSBC',
            channel: RegistryChannel.sms,
            receivedAt: _at,
          ),
        );
        final ex = (c['expect']! as Map).cast<String, Object?>();
        final money = switch (r) {
          ParseGeneric() => r.amount,
          ParseParsed() => r.fields.amount,
          _ => null,
        };
        expect(money, isNotNull, reason: 'no transaction read');
        expect(_decimal(money!), ex['amount']);
        expect(money.currency.code, ex['currency']);
        // Either the generic reader (review, below the threshold) or a real
        // template matched; anything else already failed on `money` above.
        expect(r, anyOf(isA<ParseGeneric>(), isA<ParseParsed>()));
        if (r is ParseGeneric) {
          expect(r.institutionCode, 'hsbc');
          expect(r.needsReview, isTrue);
          expect(r.confidencePermille, lessThan(kAutoAcceptThresholdPermille));
        }
      });
    }
  });

  group('prefill tier (review with all fields, one tap)', () {
    test('complete readings are flagged; partial ones are not', () {
      var complete = 0;
      for (final c in tuned) {
        final r = _generic(c['body']! as String, registry);
        if (r is! ParseGeneric) continue;
        final ex = (c['expect']! as Map).cast<String, Object?>();
        if (r.prefillComplete) {
          complete++;
          // Never on a guess: direction set, an anchor field present.
          expect(r.direction, isNotNull, reason: c['id'] as String);
          expect(r.last4 ?? r.merchant, isNotNull, reason: c['id'] as String);
        }
        if (ex['direction'] == null) {
          expect(r.prefillComplete, isFalse, reason: c['id'] as String);
        }
        // Always review: the flag never raises the confidence.
        expect(r.confidencePermille, lessThanOrEqualTo(700));
      }
      expect(complete, greaterThanOrEqualTo(tuned.length * 3 ~/ 4));
    });

    test('field confidence is set only for fields that were read', () {
      final r = _generic(
        'Your card ending 5590 was debited EGP 420.00 on 13/11/2026',
        registry,
      ) as ParseGeneric;
      expect(r.fieldConfidence.keys, isNot(contains(GenericField.merchant)));
      expect(r.fieldConfidence.keys, isNot(contains(GenericField.reference)));
      expect(r.fieldConfidence[GenericField.amount], greaterThan(0));
      expect(r.fieldConfidence[GenericField.last4], greaterThan(0));
      expect(r.fieldConfidence[GenericField.date], greaterThan(0));
      expect(r.merchant, isNull);
    });
  });

  group('negative cases: no transaction from a known bank', () {
    const negatives = <String>[
      // OTPs
      'Your OTP for the purchase of EGP 1,250.00 at AMAZON is 483920. Do not share it.',
      'Use 551203 as your one-time password for card ending 4417 transaction of USD 20.00',
      'رمز التحقق الخاص بك هو 448812 لعملية شراء بمبلغ 300 جم',
      // Promotions
      'Enjoy up to 20% cashback on purchases over EGP 500 with your HSBC card. T&Cs apply',
      'Congratulations! You could win EGP 10,000 when you spend with your card this month',
      'عرض خاص: احصل على كاش باك 10% على مشترياتك بقيمة 1000 جم',
      // Statements and due reminders
      'Your credit card statement is ready. Total due EGP 5,400.00, minimum due EGP 270.00 by 25/11/2026',
      'Payment due date for card ending 4417 is 25/11/2026. Minimum payment due EGP 350.00',
      'كشف حساب بطاقتك جاهز. المبلغ المستحق 4200 جم',
      // Balance only
      'Your balance is EGP 12,450.00 as of 13/11/2026',
      'Your available balance on account ending 8120 is EGP 3,200.50',
      'رصيدك الحالي 1240.00 جنيه',
      'Avl Bal EGP 4,865.00 on card ending 6033',
      // Declines
      'Transaction of EGP 900.00 at ZARA on card ending 6612 was declined: insufficient funds',
      'تم رفض عملية شراء بمبلغ 450 جم لدى كارفور',
    ];
    for (var i = 0; i < negatives.length; i++) {
      test('negative $i', () {
        final r = pipeline.parse(
          ParseRequest(
            body: negatives[i],
            source: 'HSBC',
            channel: RegistryChannel.sms,
            receivedAt: _at,
          ),
        );
        // Declines may parse through a bank's `declined` template (neutral,
        // stored as declined, never spend); everything else is dropped or
        // unrecognized.
        if (r is ParseParsed) {
          expect(r.event, TemplateEvent.declined, reason: 'negative $i');
        } else {
          expect(r, isNot(isA<ParseGeneric>()), reason: 'negative $i');
        }
      });
    }
  });

  group('learn: a confirmed generic reading becomes a custom template', () {
    test('tags from the generic reading build a template that reads it', () {
      const body =
          'Your card ending 6612 was used for EGP 845.50 at SPINNEYS ZAYED on '
          '12/11/2026. Available limit EGP 30,100.00';
      const next =
          'Your card ending 6612 was used for EGP 99.00 at TALABAT FOOD on '
          '13/11/2026. Available limit EGP 30,001.00';
      final g = _generic(body, registry) as ParseGeneric;
      final built = templateFromGeneric(
        sample: body,
        generic: g,
        direction: TemplateDirection.expense,
        sender: 'MYBANK',
      );
      expect(built.error, isNull);
      final report = testCustomTemplate(built.spec!, [next], receivedAt: _at);
      expect(report.matched, 1);
    });

    test('suggestTemplateTags tags amount, currency, last-4, merchant', () {
      const body = 'تم خصم 155.00 جم لدى كارفور ببطاقة *2281';
      final s = suggestTemplateTags(body)!;
      final tags = {
        for (final t in s.tags) t.tag: body.substring(t.start, t.end),
      };
      expect(tags[CustomTag.amount], '155.00');
      expect(tags[CustomTag.currency], 'جم');
      expect(tags[CustomTag.last4], '2281');
      expect(tags[CustomTag.merchant], 'كارفور');
      expect(s.direction, TemplateDirection.expense);
    });

    test('nothing readable: no suggestion', () {
      expect(suggestTemplateTags('hello there'), isNull);
    });
  });

  group('regressions found by the corpus', () {
    ParseResult g(String body) => _generic(body, registry);

    test('a word starting with a month name is not a date', () {
      final r = g('Card **4010 EGP 75.00 SEOUDI MARKET') as ParseGeneric;
      expect(r.dateRead, isFalse);
      expect(r.occurredAt, _at);
    });

    test('masked card digits never take the amount currency', () {
      final r = g('Card **4010 EGP 75.00 SEOUDI MARKET') as ParseGeneric;
      expect(r.amount.minor, 7500);
      expect(r.last4, '4010');
    });

    test('unknown dollar prefixes are never USD; known ones map', () {
      expect(g('Debited MX\$ 20.00 at SHOP'), isA<ParseUnrecognized>());
      expect(g('Debited R\$20.00 at SHOP'), isA<ParseUnrecognized>());
      expect(
        (g('Debited A\$20.00 at SHOP') as ParseGeneric).amount.currency.code,
        'AUD',
      );
      expect(
        (g('Debited US\$20.00 at SHOP') as ParseGeneric).amount.currency.code,
        'USD',
      );
      expect(
        (g('Debited \$20.00 at SHOP') as ParseGeneric).amount.currency.code,
        'USD',
      );
    });

    test('a balance named earlier in the clause is not the amount', () {
      expect(
        g('Your available balance on account ending 8120 is EGP 3,200.50'),
        isA<ParseUnrecognized>(),
      );
    });

    test('Ali is a name, the preposition ends the span', () {
      final r = g('تم استلام 100 جم من محمد علي على حسابك') as ParseGeneric;
      expect(r.merchant?.display, 'محمد علي');
    });

    test('`may` without a year is not a date', () {
      expect(
        (g('Debited EGP 5 at SHOP. Fees 5 may apply') as ParseGeneric).dateRead,
        isFalse,
      );
    });
  });

  group('batch-27 delta: OTP guard in the generic parser', () {
    final registry = _registry();
    test('a purchase with an OTP footer and a colon balance still parses', () {
      for (final body in const [
        'Purchase of EGP 250.00 at TESTMART card *4321. '
            'Never share your OTP. Balance: 15000 EGP',
        'EGP 1,200.00 debited from card *9876. OTP: never asked by bank. '
            'Ref: 55512345',
      ]) {
        expect(_generic(body, registry), isA<ParseGeneric>());
      }
    });
    test('an OTP message with a code is not a spend', () {
      expect(
        _generic(
          'Your OTP for the purchase of EGP 1,250.00 at TESTSHOP is 483920',
          registry,
        ),
        isNot(isA<ParseGeneric>()),
      );
    });
  });
}
