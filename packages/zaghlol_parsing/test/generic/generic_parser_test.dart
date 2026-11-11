import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../support/registry_files.dart';

final DateTime _at = DateTime.utc(2026, 11, 12, 9, 30);

const String _unseenPath = 'test/fixtures/generic/unseen_set.json';

ParsingPipeline _pipeline() {
  final f = RegistryFiles.load(pipelineRoot);
  final r = RegistryLoader.load(
    manifest: f.manifest,
    shared: f.shared,
    institutions: f.institutions,
  );
  if (r.issues.isNotEmpty) {
    throw StateError('test registry failed to load');
  }
  return ParsingPipeline(r.registry!);
}

ParseRequest _req(
  String body, {
  String source = 'SOMEBANK',
  RegistryChannel channel = RegistryChannel.share,
}) =>
    ParseRequest(body: body, source: source, channel: channel, receivedAt: _at);

String _money(ParseGeneric g) {
  final a = g.amount;
  final digits = a.minor.abs().toString().padLeft(a.currency.exponent + 1, '0');
  final cut = digits.length - a.currency.exponent;
  return a.currency.exponent == 0
      ? digits
      : '${digits.substring(0, cut)}.${digits.substring(cut)}';
}

List<Map<String, Object?>> _unseen() =>
    (jsonDecode(File(_unseenPath).readAsStringSync()) as List)
        .cast<Map<String, Object?>>();

void main() {
  final pipeline = _pipeline();
  final cases = _unseen();

  group('unseen set (AC 1: at least 80% correct amount and currency)', () {
    test('accuracy report', () {
      var suggest = 0;
      var correct = 0;
      final misses = <String>[];
      for (final c in cases.where((c) => c['outcome'] == 'suggest')) {
        suggest += 1;
        final ex = c['expect']! as Map<String, Object?>;
        final r = pipeline.parse(_req(c['body']! as String));
        if (r is ParseGeneric &&
            _money(r) == ex['amount'] &&
            r.amount.currency.code == ex['currency']) {
          correct += 1;
        } else {
          misses.add(c['id']! as String);
        }
      }
      final pct = (correct * 1000 ~/ suggest) / 10;
      // Ids only: never message text in test output.
      // ignore: avoid_print
      print(
        'generic unseen set: $correct/$suggest amount+currency correct '
        '($pct%); misses: ${misses.isEmpty ? 'none' : misses.join(', ')}',
      );
      expect(suggest, greaterThanOrEqualTo(35));
      expect(correct * 100, greaterThanOrEqualTo(suggest * 80));
    });

    // A known miss is counted in the accuracy report and must stay a miss
    // (so a fix is noticed and the flag removed); it has no field test.
    test('known misses are still misses', () {
      for (final c in cases.where((c) => c['knownMiss'] == true)) {
        final ex = c['expect']! as Map<String, Object?>;
        final r = pipeline.parse(_req(c['body']! as String));
        expect(
          r is ParseGeneric &&
              _money(r) == ex['amount'] &&
              r.amount.currency.code == ex['currency'],
          isFalse,
          reason: '${c['id']} now passes: remove knownMiss',
        );
      }
    });

    for (final c in cases.where(
      (c) => c['outcome'] == 'suggest' && c['knownMiss'] != true,
    )) {
      test('fields: ${c['id']}', () {
        final ex = c['expect']! as Map<String, Object?>;
        final r = pipeline.parse(_req(c['body']! as String));
        expect(r, isA<ParseGeneric>());
        final g = r as ParseGeneric;
        expect(_money(g), ex['amount']);
        expect(g.amount.currency.code, ex['currency']);
        expect(g.direction?.name, ex['direction']);
        if (ex.containsKey('last4')) {
          expect(g.last4, ex['last4']);
        }
        if (ex.containsKey('merchant')) {
          expect(g.merchant?.display, ex['merchant']);
        }
      });
    }

    for (final c in cases.where((c) => c['outcome'] != 'suggest')) {
      test('abstains: ${c['id']}', () {
        final r = pipeline.parse(_req(c['body']! as String));
        expect(r, isA<ParseUnrecognized>());
        expect(
          (r as ParseUnrecognized).reason,
          c['outcome'] == 'declined'
              ? UnrecognizedReason.genericDeclined
              : UnrecognizedReason.genericNoAmount,
        );
      });
    }
  });

  group('always review, never auto-saved (AC 2)', () {
    test('every suggestion needs review and is below the threshold', () {
      var seen = 0;
      for (final c in cases.where((c) => c['outcome'] == 'suggest')) {
        final r = pipeline.parse(_req(c['body']! as String));
        if (r is ParseGeneric) {
          seen += 1;
          expect(r.needsReview, isTrue);
          expect(r.confidencePermille, lessThanOrEqualTo(700));
          expect(r.confidencePermille, lessThan(kAutoAcceptThresholdPermille));
        }
      }
      expect(seen, greaterThan(30));
    });

    test('policy: review until 3 confirmations and always-capture', () {
      for (var n = -1; n < 3; n++) {
        for (final always in [true, false]) {
          expect(
            genericDisposition(confirmedCount: n, alwaysCapture: always),
            GenericDisposition.review,
            reason: 'n=$n always=$always',
          );
        }
      }
      expect(
        genericDisposition(confirmedCount: 5, alwaysCapture: false),
        GenericDisposition.review,
      );
      expect(
        genericDisposition(confirmedCount: 3, alwaysCapture: true),
        GenericDisposition.autoSaveLowConfidence,
      );
      expect(kGenericConfirmationsRequired, 3);
    });
  });

  group('who reaches the generic parser', () {
    const body = 'EGP 100.00 debited at SHOP ONE';
    test('hinted sender and body hints: yes', () {
      final r = pipeline.parse(
        _req(
          'Your account was debited EGP 100.00 at SHOP ONE',
          source: 'NEW BANK',
          channel: RegistryChannel.sms,
        ),
      );
      expect(r, isA<ParseGeneric>());
    });

    test('hinted sender but no amount-looking body: unknown source', () {
      final r = pipeline.parse(
        _req(
          'Welcome to our new app',
          source: 'NEW BANK',
          channel: RegistryChannel.sms,
        ),
      );
      expect((r as ParseUnrecognized).reason, UnrecognizedReason.unknownSource);
    });

    test('financial body from a sender with no hint: unknown source', () {
      final r = pipeline.parse(
        _req(body, source: 'FRIEND', channel: RegistryChannel.sms),
      );
      expect((r as ParseUnrecognized).reason, UnrecognizedReason.unknownSource);
    });

    test('always-capture source reaches it without hints', () {
      final r = pipeline.parse(
        _req(
          'Debited 40 EGP at SHOP ONE',
          source: 'bdc-alert',
          channel: RegistryChannel.sms,
        ),
      );
      expect(r, isA<ParseGeneric>());
    });

    test('shortcut, Apple Pay and share inputs reach it', () {
      for (final ch in [
        RegistryChannel.shortcutMessage,
        RegistryChannel.applePay,
        RegistryChannel.share,
      ]) {
        expect(
          pipeline.parse(_req(body, source: '', channel: ch)),
          isA<ParseGeneric>(),
        );
      }
    });

    test('an OTP from an unknown sender is still dropped', () {
      final r = pipeline.parse(
        _req('OTP 123456 for EGP 100.00 payment', source: 'NEW BANK'),
      );
      expect(r, isA<ParseDropped>());
    });

    test('a known institution never falls back to generic', () {
      final r = pipeline.parse(
        _req('nothing the NBE templates know about EGP 100', source: 'NBE'),
      );
      expect(r, isNot(isA<ParseGeneric>()));
    });
  });

  group('conservative behavior', () {
    ParseGeneric g(String body) => pipeline.parse(_req(body)) as ParseGeneric;

    test('no direction keyword leaves direction null with a reason', () {
      final r = g('Amount: 450.00 EGP Merchant: CARREFOUR');
      expect(r.direction, isNull);
      expect(r.reasons, contains(GenericReason.directionUnknown));
      expect(r.confidencePermille, lessThan(700));
    });

    test('opposite keywords close together leave direction null', () {
      final r = g('Your payment of USD 1,000.00 was received');
      expect(r.direction, isNull);
      expect(r.reasons, contains(GenericReason.directionConflict));
    });

    test('two different amounts and no keyword is flagged ambiguous', () {
      final r = g('Amounts EGP 10.00 and EGP 20.00');
      expect(r.reasons, contains(GenericReason.amountAmbiguous));
      expect(_money(r), '10.00');
    });

    test('nothing but an amount: sparse, lowest tier', () {
      final r = g('EGP 10.00');
      expect(r.last4, isNull);
      expect(r.merchant, isNull);
      expect(r.reasons, contains(GenericReason.sparseFields));
      // 700 x 0.8 (direction) x 0.9 (sparse), floored each step.
      expect(r.confidencePermille, 504);
    });

    test('multiple penalties multiply in integers', () {
      final r = g('Amounts EGP 10.00 and EGP 20.00');
      // 700 x 0.7 = 490, x 0.8 = 392, x 0.9 = 352.
      expect(r.reasons, [
        GenericReason.amountAmbiguous,
        GenericReason.directionUnknown,
        GenericReason.sparseFields,
      ]);
      expect(r.confidencePermille, 352);
    });

    test('a bare four-digit number is not a last-4', () {
      expect(g('Debited EGP 100.00 ref 1234').last4, isNull);
    });

    test('a lowercase Latin span after a marker word is not a merchant', () {
      expect(g('Debited EGP 100.00 at the market').merchant, isNull);
      expect(g('Debited EGP 100.00 at some place').merchant, isNull);
    });

    test(
      'no fallback currency: a number without a marker is not an amount',
      () {
        final r = pipeline.parse(_req('Debited 100.00 at SHOP'));
        expect(
          (r as ParseUnrecognized).reason,
          UnrecognizedReason.genericNoAmount,
        );
      },
    );

    test('a zero amount is not a suggestion', () {
      expect(
        pipeline.parse(_req('Debited EGP 0.00')),
        isA<ParseUnrecognized>(),
      );
    });

    test('more decimals than the currency allows drops that candidate', () {
      expect(
        pipeline.parse(_req('Debited EGP 1.239')),
        isA<ParseUnrecognized>(),
      );
    });

    test('occurredAt is the receipt time and no date is read', () {
      expect(g('Debited EGP 10 on 01/01/2020').occurredAt, _at);
    });

    test('Arabic digits and the Arabic decimal mark', () {
      final r = g('تم خصم ١٢٣٫٤٥ جنيه');
      expect(_money(r), '123.45');
      expect(r.language, 'ar');
    });

    test('language follows the text', () {
      expect(g('Debited EGP 10 at SHOP').language, 'en');
    });

    test('a user-facing amount is Money, never a double', () {
      expect(g('Debited EGP 10.5').amount.minor, 1050);
    });
  });

  group('safety', () {
    test('results never carry text outside the extracted fields', () {
      // The sentinel sits where no field is read from (no marker word, not a
      // number, not next to the amount's currency), so it must not appear in
      // any code or field of the result.
      const sentinel = 'ZXQSENTINELWORD';
      final results = [
        pipeline.parse(_req('Debited EGP 10 $sentinel card 1234')),
        pipeline.parse(_req('Declined $sentinel EGP 10')),
        pipeline.parse(_req('$sentinel only text')),
        pipeline.parse(_req('$sentinel EGP 10 debited', source: 'FRIEND')),
      ];
      for (final r in results) {
        final strings = switch (r) {
          ParseGeneric() => [
            r.language,
            ?r.last4,
            ?r.merchant?.display,
            ?r.merchant?.cleaned,
            ?r.merchant?.key,
          ],
          ParseUnrecognized() => [r.reason.name, ?r.institutionCode],
          ParseDropped() => [r.reason.name],
          ParseParsed() => <String>[],
        };
        for (final s in strings) {
          expect(s.toLowerCase(), isNot(contains('sentinel')));
        }
        expect(r.toString(), isNot(contains(sentinel)));
      }
    });

    test('never throws on hostile input', () {
      final inputs = <String>[
        '',
        ' ',
        '\u0000' * 50,
        'EGP ' * 900,
        '9' * 3999,
        '9.' * 1500,
        '*' * 4000,
        'x' * 4000,
        'ا ' * 2000,
        '٠١٢٣٤٥٦٧٨٩' * 300,
        'at ' * 1300,
        'EGP 1,2,3,4,5,6,7,8,9,0,' * 150,
        '\u{1F600}EGP 5\u{1F600}',
        'EGP \uD800 5',
      ];
      for (final body in inputs) {
        expect(() => pipeline.parse(_req(body)), returnsNormally);
      }
    });

    test('adversarial 4000-character bodies are fast (M-2)', () {
      final bodies = <String>[
        '1' * 4000,
        '*' * 4000,
        'x' * 4000,
        'EGP ' * 1000,
        '1 ' * 2000,
        'at A ' * 800,
        'card ' * 800,
        '${'debited ' * 400} EGP 5',
        'EGP 1,' * 650,
        'ا ' * 2000,
        '1.' * 2000,
        'x*' * 2000,
      ];
      final clock = Stopwatch();
      for (final body in bodies) {
        final text = body.substring(0, body.length.clamp(0, 4000));
        clock
          ..reset()
          ..start();
        pipeline.parse(_req(text));
        clock.stop();
        expect(
          clock.elapsedMilliseconds,
          lessThan(100),
          reason: 'slow on an adversarial body',
        );
      }
    });

    test('benchmark: mean generic parse time (printed)', () {
      final requests = [for (final c in cases) _req(c['body']! as String)];
      for (var i = 0; i < 300; i++) {
        pipeline.parse(requests[i % requests.length]);
      }
      const runs = 4000;
      final clock = Stopwatch()..start();
      var suggested = 0;
      for (var i = 0; i < runs; i++) {
        if (pipeline.parse(requests[i % requests.length]) is ParseGeneric) {
          suggested += 1;
        }
      }
      clock.stop();
      final meanMicros = clock.elapsedMicroseconds / runs;
      // ignore: avoid_print
      print('generic parse mean: ${meanMicros.round()} us over $runs runs');
      expect(suggested, greaterThan(runs ~/ 2));
      expect(meanMicros, lessThan(10000), reason: 'budget is 10 ms');
    });
  });
}
