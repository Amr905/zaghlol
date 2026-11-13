import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

// Synthetic samples only (fake sender, card digits, merchants).

({String sample, List<TagSpan> spans}) tag(
  String sample,
  Map<CustomTag, String> parts,
) {
  final spans = <TagSpan>[];
  parts.forEach((t, text) {
    final at = sample.indexOf(text);
    spans.add(TagSpan(t, at, at + text.length));
  });
  return (sample: sample, spans: spans);
}

CustomTemplateSpec build(
  String sample,
  Map<CustomTag, String> parts, {
  TemplateDirection dir = TemplateDirection.expense,
  String sender = 'XYZBANK',
}) {
  final t = tag(sample, parts);
  final b = buildCustomTemplate(
    sample: t.sample,
    spans: t.spans,
    direction: dir,
    sender: sender,
  );
  expect(b.error, isNull, reason: 'build error');
  return b.spec!;
}

ParseParsed parsed(CustomTemplateSpec spec, String body) {
  final r = parseWithCustomTemplate(
    spec,
    'abc123',
    body,
    DateTime.utc(2026, 11, 14),
  );
  expect(r, isA<ParseParsed>(), reason: 'parse');
  return r as ParseParsed;
}

void main() {
  const en = 'XYZ: You paid 220.00 USD at AMAZON on 23/10 card 1234.';
  final enParts = {
    CustomTag.amount: '220.00',
    CustomTag.currency: 'USD',
    CustomTag.merchant: 'AMAZON',
    CustomTag.date: '23/10',
    CustomTag.last4: '1234',
  };

  group('generated template', () {
    test('parses its own sample into typed fields', () {
      final p = parsed(build(en, enParts), en);
      expect(p.fields.amount, Money(Currency.of('USD'), 22000));
      expect(p.fields.merchant?.display.toLowerCase(), contains('amazon'));
      expect(p.fields.last4, '1234');
      expect(p.direction, TemplateDirection.expense);
      expect(p.fields.date?.day, 23);
      expect(p.fields.date?.month, 10);
    });

    test('parses similar messages (other amount, merchant, digits)', () {
      final spec = build(en, enParts);
      final p = parsed(
        spec,
        'XYZ: You paid 1,250.50 USD at NOON STORE on 05/11 card 9876.',
      );
      expect(p.fields.amount, Money(Currency.of('USD'), 125050));
      expect(p.fields.last4, '9876');
      expect(p.fields.date?.month, 11);
    });

    test('Arabic message with Arabic-Indic digits', () {
      const ar = 'تم خصم 150.00 جم من بطاقة 4321 لدى كارفور';
      final spec = build(ar, {
        CustomTag.amount: '150.00',
        CustomTag.currency: 'جم',
        CustomTag.last4: '4321',
        CustomTag.merchant: 'كارفور',
      });
      final p = parsed(spec, 'تم خصم ٢٥٠٫٥٠ جم من بطاقة ٥٥٥٥ لدى هايبر وان');
      expect(p.fields.amount, Money(Currency.of('EGP'), 25050));
      expect(p.fields.last4, '5555');
    });

    test('income direction and no currency uses the default', () {
      const s = 'Salary credited 9000.00 to your account';
      final spec = build(s, {
        CustomTag.amount: '9000.00',
      }, dir: TemplateDirection.income);
      final p = parsed(spec, 'Salary credited 12000.00 to your account');
      expect(p.direction, TemplateDirection.income);
      expect(p.fields.amount, Money(Currency.of('EGP'), 1200000));
    });

    test('amount first, merchant last (greedy tail)', () {
      const s = '500.00 EGP spent at Test Cafe';
      final spec = build(s, {
        CustomTag.amount: '500.00',
        CustomTag.currency: 'EGP',
        CustomTag.merchant: 'Test Cafe',
      });
      final p = parsed(spec, '75.25 EGP spent at Other Shop Cairo');
      expect(p.fields.amount, Money(Currency.of('EGP'), 7525));
      expect(p.fields.merchant, isNotNull);
    });

    test('balance and a date with a year', () {
      const s = 'Paid 10.00 EGP on 01/02/2026. Balance 990.00';
      final spec = build(s, {
        CustomTag.amount: '10.00',
        CustomTag.date: '01/02/2026',
        CustomTag.balance: '990.00',
      });
      final p = parsed(spec, 'Paid 20.00 EGP on 15/03/2026. Balance 970.00');
      expect(p.fields.balance, Money(Currency.of('EGP'), 97000));
      expect(p.fields.date?.year, 2026);
      expect(p.fields.date?.month, 3);
    });

    test('a different message does not match', () {
      final spec = build(en, enParts);
      final r = parseWithCustomTemplate(
        spec,
        'x',
        'Your OTP is 123456',
        DateTime.utc(2026, 11, 14),
      );
      expect(r, isNot(isA<ParseParsed>()));
    });

    test('built pattern passes the lint and stays under the cap', () {
      final spec = build(en, enParts);
      expect(backtrackingProblems(spec.pattern), isEmpty);
      expect(spec.pattern.length, lessThanOrEqualTo(maxPatternLength));
    });

    test('long literal between parts stays bounded', () {
      final s = 'Paid 10.00 EGP ${'filler words ' * 12}ref at Shop';
      final spec = build(s, {CustomTag.amount: '10.00'});
      expect(backtrackingProblems(spec.pattern), isEmpty);
      parsed(spec, s.replaceFirst('10.00', '33.30'));
    });
  });

  group('validation (error codes)', () {
    CustomTemplateError? err(
      String sample,
      List<TagSpan> spans, {
      String sender = 'XYZ',
      TemplateDirection dir = TemplateDirection.expense,
    }) => buildCustomTemplate(
      sample: sample,
      spans: spans,
      direction: dir,
      sender: sender,
    ).error;

    test('no amount tag', () {
      expect(
        err(en, [const TagSpan(CustomTag.merchant, 15, 21)]),
        CustomTemplateError.noAmountTag,
      );
    });
    test('empty and oversize sample', () {
      expect(err('  ', const []), CustomTemplateError.sampleEmpty);
      expect(
        err('a' * (maxCustomSampleLength + 1), const []),
        CustomTemplateError.sampleTooLong,
      );
    });
    test('bad sender and neutral direction', () {
      final t = tag(en, {CustomTag.amount: '220.00'});
      expect(err(en, t.spans, sender: ' '), CustomTemplateError.senderInvalid);
      expect(
        err(en, t.spans, dir: TemplateDirection.neutral),
        CustomTemplateError.senderInvalid,
      );
    });
    test('overlap, duplicate tag, bad span', () {
      expect(
        err(en, const [
          TagSpan(CustomTag.amount, 14, 20),
          TagSpan(CustomTag.merchant, 18, 24),
        ]),
        CustomTemplateError.overlap,
      );
      expect(
        err(en, const [
          TagSpan(CustomTag.amount, 14, 20),
          TagSpan(CustomTag.amount, 25, 28),
        ]),
        CustomTemplateError.duplicateTag,
      );
      expect(
        err(en, const [TagSpan(CustomTag.amount, 5, 999)]),
        CustomTemplateError.badSpan,
      );
    });
    test('tag value shapes', () {
      expect(
        err(en, [
          tag(en, {CustomTag.amount: 'paid'}).spans.single,
        ]),
        CustomTemplateError.badAmount,
      );
      final t = tag(en, {CustomTag.amount: '220.00', CustomTag.last4: '123'});
      expect(err(en, t.spans), CustomTemplateError.badLast4);
    });
    test('a message with one tag per kind is the cap', () {
      expect(CustomTag.values.length, maxCustomSpans);
    });
  });

  group('stored template is untrusted', () {
    Map<String, Object?> good() => build(en, enParts).toJson();

    test('round trip', () {
      final spec = CustomTemplateSpec.fromJson(good());
      expect(spec, isNotNull);
      parsed(spec!, en);
    });

    Map<String, Object?> with_(String k, Object? v) => {...good(), k: v};

    test('rejects catastrophic and oversize patterns', () {
      expect(
        CustomTemplateSpec.fromJson(
          with_('pattern', r'(?<amount>[0-9]+)(a+)+$'),
        ),
        isNull,
      );
      expect(
        CustomTemplateSpec.fromJson(
          with_('pattern', '(?<amount>[0-9]+)${'a' * 700}'),
        ),
        isNull,
      );
      expect(
        CustomTemplateSpec.fromJson(
          with_('pattern', r'(?<amount>[0-9]+)(?=x)'),
        ),
        isNull,
      );
    });
    test('rejects unknown groups, missing amount, bad types', () {
      expect(
        CustomTemplateSpec.fromJson(
          with_('pattern', r'(?<amount>[0-9]+)(?<ref>x)'),
        ),
        isNull,
      );
      expect(
        CustomTemplateSpec.fromJson(with_('pattern', r'(?<cur>x)')),
        isNull,
      );
      expect(CustomTemplateSpec.fromJson(with_('currency', 'XXQ')), isNull);
      expect(CustomTemplateSpec.fromJson(with_('v', 2)), isNull);
      expect(CustomTemplateSpec.fromJson(with_('sender', 5)), isNull);
      expect(CustomTemplateSpec.fromJson(with_('channel', 'email')), isNull);
      expect(
        CustomTemplateSpec.fromJson(with_('direction', 'neutral')),
        isNull,
      );
      expect(CustomTemplateSpec.fromJson('nope'), isNull);
      expect(CustomTemplateSpec.fromJson(null), isNull);
    });
    test('rejects a date group without a valid format', () {
      expect(CustomTemplateSpec.fromJson(with_('dateFormat', 'x')), isNull);
    });
    test('toString redacts', () {
      expect(
        CustomTemplateSpec.fromJson(good()).toString(),
        isNot(contains('XYZ')),
      );
    });
  });

  group('testCustomTemplate', () {
    test('counts matches over sender history without echoing text', () {
      final spec = build(en, enParts);
      final history = [
        'XYZ: You paid 10.00 USD at A SHOP on 01/10 card 1111.',
        'XYZ: You paid 20.00 USD at B SHOP on 02/10 card 2222.',
        'XYZ: Your OTP is 123456',
        'XYZ: You paid 0.00 USD at C on 03/10 card 3333.',
      ];
      final r = testCustomTemplate(
        spec,
        history,
        receivedAt: DateTime.utc(2026, 11, 14),
      );
      expect(r.total, 4);
      expect(r.matched, 2);
      expect(r.failures.map((f) => f.$1), [2, 3]);
      expect(r.failures[0].$2, CustomTestFailure.other);
      expect(r.failures[1].$2, CustomTestFailure.amount);
    });

    test('reads at most maxCustomTestMessages', () {
      final spec = build(en, enParts);
      final r = testCustomTemplate(
        spec,
        List.filled(500, en),
        receivedAt: DateTime.utc(2026, 11, 14),
      );
      expect(r.total, maxCustomTestMessages);
      expect(r.matched, maxCustomTestMessages);
    });

    test('hostile input stays fast (no catastrophic backtracking)', () {
      final spec = build(en, enParts);
      final hostile = 'XYZ: You paid ${'1,' * 1500} USD at ${'A ' * 1000}';
      final r = testCustomTemplate(spec, [
        hostile,
        'a ' * 1900,
      ], receivedAt: DateTime.utc(2026, 11, 14));
      expect(r.slow, isFalse, reason: 'slowest ${r.slowest}us');
    });
  });

  group('tokenizeSample', () {
    test('splits on spaces and trims edge punctuation', () {
      const s = 'XYZ: paid (220.00) at AMAZON.';
      final words = [
        for (final t in tokenizeSample(s)) s.substring(t.start, t.end),
      ];
      expect(words, ['XYZ', 'paid', '220.00', 'at', 'AMAZON']);
    });
  });

  test('custom institution joins a base registry, built-in senders first', () {
    final spec = build(en, enParts);
    final base = Registry.ofInstitutions(const []);
    final r = base.withExtra([spec.toInstitution('01ABC')]);
    expect(
      r.resolveSource('xyzbank', RegistryChannel.sms)?.code,
      'custom_01abc',
    );
    expect(
      customInstitutionCode('01ARZ-3NDEKTSV4RRFFQ69G5FAV'),
      matches(RegExp(r'^custom_[a-z0-9]{1,24}$')),
    );
  });
}
