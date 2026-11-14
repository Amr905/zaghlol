import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../support/registry_files.dart';

final DateTime _at = DateTime.utc(2026, 10, 23, 11, 14);

ParsingPipeline _pipelineOf(RegistryFiles f) {
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
  String source = 'NBE',
  RegistryChannel channel = RegistryChannel.sms,
  DateTime? at,
}) => ParseRequest(
  body: body,
  source: source,
  channel: channel,
  receivedAt: at ?? _at,
);

ParseParsed _parsed(ParseResult r) {
  expect(r, isA<ParseParsed>());
  return r as ParseParsed;
}

UnrecognizedReason? _why(ParseResult r) =>
    r is ParseUnrecognized ? r.reason : null;

void main() {
  final files = RegistryFiles.load(pipelineRoot);
  final pipeline = _pipelineOf(files);

  group('spec NBE example (AC 1)', () {
    test('Arabic sample parses to the expected fields', () {
      final r = _parsed(
        pipeline.parse(
          _req(
            'البنك الأهلي المصري: تم خصم 200.00 جم ببطاقة فيزا **4567 لدى AMAZON EG يوم 23/10. الرصيد المتاح 12400.00 جم',
          ),
        ),
      );
      expect(r.institutionCode, 'nbe');
      expect(r.templateId, 'nbe.card_purchase.ar');
      expect(r.templateVersion, 1);
      expect(r.language, 'ar');
      expect(r.event, TemplateEvent.cardPurchase);
      expect(r.direction, TemplateDirection.expense);
      expect(r.fields.amount!.toCanonicalString(), '200.00');
      expect(r.fields.amount!.currency.code, 'EGP');
      expect(r.fields.originalAmount, isNull);
      expect(r.fields.last4, '4567');
      expect(r.fields.merchant!.display, 'Amazon');
      expect(r.fields.merchant!.key, 'amazon');
      expect(r.fields.balance!.toCanonicalString(), '12400.00');
      expect(r.fields.available, isNull);
      expect(r.fields.counterparty, isNull);
      expect(r.fields.ref, isNull);
      expect(r.fields.date, DateTime.utc(2026, 10, 23));
      expect(r.fields.time, isNull);
      expect(r.fields.occurredAt, DateTime.utc(2026, 10, 23, 11, 14));
      expect(r.fields.occurredAtSource, OccurredAtSource.messageDate);
      expect(r.confidencePermille, 980);
      expect(r.reasons, isEmpty);
      expect(r.needsReview, isFalse);
    });

    test('English sample parses to the expected fields', () {
      final r = _parsed(
        pipeline.parse(
          _req(
            'NBE: Purchase of EGP 200.00 from NBE Visa **4567 at AMAZON EG on 23/10. Avl Bal EGP 12,400.00',
          ),
        ),
      );
      expect(r.templateId, 'nbe.card_purchase.en');
      expect(r.language, 'en');
      expect(r.fields.amount!.toCanonicalString(), '200.00');
      expect(r.fields.merchant!.display, 'Amazon');
      expect(r.fields.balance!.toCanonicalString(), '12400.00');
      expect(r.fields.last4, '4567');
      expect(r.confidencePermille, 970);
    });
  });

  group('missing optional fields are null, never guessed (AC 2)', () {
    test('no balance, merchant-less deposit, no date or time', () {
      final r = _parsed(
        pipeline.parse(_req('تم إيداع نقدي 500.00 جم في حسابكم')),
      );
      final f = r.fields;
      expect(f.amount!.toCanonicalString(), '500.00');
      expect(f.balance, isNull);
      expect(f.available, isNull);
      expect(f.originalAmount, isNull);
      expect(f.last4, isNull);
      expect(f.merchant, isNull);
      expect(f.counterparty, isNull);
      expect(f.ref, isNull);
      expect(f.date, isNull);
      expect(f.time, isNull);
      expect(f.occurredAtSource, OccurredAtSource.receivedAt);
      expect(f.occurredAt, _at);
      expect(r.reasons, [ParseReason.sparseFields]);
    });

    test('a balance-only notice has no amount', () {
      final r = _parsed(
        pipeline.parse(_req('رصيد حسابكم رقم **4567 هو 12,400.00 جم')),
      );
      expect(r.fields.amount, isNull);
      expect(r.fields.balance!.toCanonicalString(), '12400.00');
      expect(r.direction, TemplateDirection.neutral);
      expect(r.reasons, isEmpty);
    });

    test('a last4 group that did not participate is not borrowed', () {
      // The template owns a `last4` group, so the institution pattern
      // (`رقم 4567` in the body) is not consulted: absent stays null.
      final f = files.copy()
        ..editInstitution('nbe.json', (j) {
          (j['templates']! as List<Object?>).add({
            'id': 'nbe.opt_last4.en',
            'version': 1,
            'lang': 'en',
            'event': 'fee',
            'direction': 'expense',
            'baseConfidence': 0.9,
            'pattern': r'^zq (?<amount>[\d.]+)(?: card (?<last4>\d{4}))?',
          });
        });
      final r = _parsed(_pipelineOf(f).parse(_req('zq 5.00 رقم 4567')));
      expect(r.fields.last4, isNull);
    });
  });

  group('typed extraction', () {
    test('foreign purchase keeps billed and original amounts apart', () {
      final r = _parsed(
        pipeline.parse(
          _req('NBE: JPY 15000 at UNIQLO charged EGP 4,950.00 on card *4567'),
        ),
      );
      expect(r.event, TemplateEvent.cardPurchaseFx);
      expect(r.fields.amount!.toCanonicalString(), '4950.00');
      expect(r.fields.amount!.currency.code, 'EGP');
      expect(r.fields.originalAmount!.toCanonicalString(), '15000');
      expect(r.fields.originalAmount!.currency.code, 'JPY');
    });

    test('counterparty kinds: name, IPA, phone', () {
      final name = _parsed(
        pipeline.parse(
          _req(
            'تم تحويل 500.00 جم إلى أحمد محمود عبر إنستاباي. رقم مرجعي 123456789',
            source: 'CIB',
          ),
        ),
      );
      expect(name.fields.counterparty!.kind, CounterpartyKind.name);
      expect(name.fields.counterparty!.name, 'أحمد محمود');
      expect(name.fields.ref, '123456789');

      final ipa = _parsed(
        pipeline.parse(
          _req(
            'CIB: You sent EGP 5.00 to Omar.K@instapay via InstaPay. Ref AB12CD34',
            source: 'CIB',
          ),
        ),
      );
      expect(ipa.fields.counterparty!.kind, CounterpartyKind.ipaAddress);
      expect(ipa.fields.counterparty!.ipa, 'Omar.K@instapay');
      expect(ipa.fields.counterparty!.name, isNull);

      final phones = _pipelineOf(RegistryFiles.load());
      final phone = _parsed(
        phones.parse(
          _req(
            'CIB: You sent EGP 500.00 to 01012345678 via InstaPay. Ref 123456789',
            source: 'CIB',
          ),
        ),
      );
      expect(phone.fields.counterparty!.kind, CounterpartyKind.phone);
      expect(phone.fields.counterparty!.phone, '01012345678');
    });

    test('declared last4 patterns fill a template with no last4 group', () {
      final r = _parsed(
        pipeline.parse(_req('تم إيداع نقدي 1,000.00 جم في حسابكم رقم 4567')),
      );
      expect(r.fields.last4, '4567');
      expect(r.reasons, isEmpty);
    });

    test('the shared last4 patterns are the second source', () {
      final f = files.copy()
        ..editInstitution('nbe.json', (j) {
          j['last4'] = <Object?>[];
        });
      final p = _pipelineOf(f);
      final r = _parsed(
        p.parse(_req('تم إيداع نقدي 1,000.00 جم في حسابكم **4567')),
      );
      expect(r.fields.last4, '4567');
    });

    test('the available-limit flag is passed through', () {
      final f = files.copy()
        ..editInstitution('nbe.json', (j) {
          final t =
              (j['templates']! as List<Object?>).first! as Map<String, Object?>;
          t['flags'] = {'isAvailableLimit': true};
        });
      final r = _parsed(
        _pipelineOf(f).parse(
          _req(
            'تم خصم 200.00 جم ببطاقة فيزا **4567 لدى AMAZON يوم 23/10. الرصيد المتاح 100.00 جم',
          ),
        ),
      );
      expect(r.fields.balanceIsAvailableLimit, isTrue);
    });
  });

  group('stage 0 guard and routing', () {
    test('institution drop pattern', () {
      final r = pipeline.parse(_req('NBE: special offer on cards'));
      expect(r, isA<ParseDropped>());
      expect((r as ParseDropped).reason, DropReason.institutionPattern);
      expect(r.institutionCode, 'nbe');
    });

    test('global drop pattern, known and unknown sender', () {
      final known = pipeline.parse(_req('Your OTP is 123456'));
      expect((known as ParseDropped).reason, DropReason.globalPattern);
      expect(known.institutionCode, 'nbe');
      final unknown = pipeline.parse(
        _req('رمز التحقق 123456', source: 'SOMEONE'),
      );
      expect((unknown as ParseDropped).reason, DropReason.globalPattern);
      expect(unknown.institutionCode, isNull);
    });

    test('unknown source is unrecognized, ready for the generic parser', () {
      expect(
        _why(pipeline.parse(_req('تم خصم 200.00 جم', source: 'NOBODY'))),
        UnrecognizedReason.unknownSource,
      );
    });

    test('known source, no template', () {
      final r = pipeline.parse(_req('NBE: welcome to our new app'));
      expect(_why(r), UnrecognizedReason.noTemplateMatched);
      expect((r as ParseUnrecognized).institutionCode, 'nbe');
    });

    test('empty, blank and invisible-only bodies', () {
      for (final body in ['', '   ', '‏‎  \n']) {
        expect(
          _why(pipeline.parse(_req(body))),
          UnrecognizedReason.emptyBody,
          reason: 'body of ${body.length} units',
        );
      }
    });

    test('over-long body is refused before matching', () {
      final r = pipeline.parse(_req('1' * (maxParseBodyLength + 1)));
      expect(_why(r), UnrecognizedReason.bodyTooLong);
      final atCap = pipeline.parse(_req('1' * maxParseBodyLength));
      expect(_why(atCap), UnrecognizedReason.noTemplateMatched);
    });

    test('channel filter: SMS templates do not match a notification', () {
      final r = pipeline.parse(
        _req(
          'تم إيداع نقدي 500.00 جم في حسابكم',
          source: 'com.example.nbe',
          channel: RegistryChannel.notification,
        ),
      );
      expect(_why(r), UnrecognizedReason.noTemplateMatched);
    });

    test('alternate sender id resolves to the same institution', () {
      final r = _parsed(
        pipeline.parse(
          _req('تم إيداع نقدي 500.00 جم في حسابكم', source: 'alahly'),
        ),
      );
      expect(r.institutionCode, 'nbe');
    });
  });

  group('fatal extraction problems become unrecognized', () {
    final rows = <(String, String, UnrecognizedReason)>[
      (
        'too many decimals for EGP',
        'NBE: Purchase of EGP 10.505 from NBE Visa **4567 at ZARA on 23/10.',
        UnrecognizedReason.invalidAmount,
      ),
      (
        'zero amount',
        'NBE: Purchase of EGP 0.00 from NBE Visa **4567 at ZARA on 23/10.',
        UnrecognizedReason.invalidAmount,
      ),
      (
        'malformed amount',
        'NBE: Purchase of EGP 1.2.3 from NBE Visa **4567 at ZARA on 23/10.',
        UnrecognizedReason.invalidAmount,
      ),
    ];
    for (final (name, body, reason) in rows) {
      test(name, () {
        final r = pipeline.parse(_req(body));
        expect(_why(r), reason);
        expect((r as ParseUnrecognized).templateId, 'nbe.card_purchase.en');
      });
    }

    test('an unknown currency marker is never replaced by the default', () {
      final f = files.copy()
        ..editInstitution('nbe.json', (j) {
          (j['templates']! as List<Object?>).add({
            'id': 'nbe.any_cur.en',
            'version': 1,
            'lang': 'en',
            'event': 'card_purchase',
            'direction': 'expense',
            'baseConfidence': 0.9,
            'pattern': r'^pay (?<amount>[\d,.]+) (?<cur>\S+)$',
          });
        });
      final p = _pipelineOf(f);
      expect(
        _why(p.parse(_req('pay 5.00 qqq'))),
        UnrecognizedReason.invalidCurrency,
      );
      expect(
        _parsed(p.parse(_req('pay 5.00 usd'))).fields.amount!.currency.code,
        'USD',
      );
    });

    test('a later template reads what an earlier one could not', () {
      final f = files.copy()
        ..editInstitution('nbe.json', (j) {
          (j['templates']! as List<Object?>)
            ..add({
              'id': 'nbe.zz_a.en',
              'version': 1,
              'lang': 'en',
              'event': 'fee',
              'direction': 'expense',
              'baseConfidence': 0.9,
              'pattern': r'^zz (?<amount>[\d.]+)',
            })
            ..add({
              'id': 'nbe.zz_b.en',
              'version': 1,
              'lang': 'en',
              'event': 'fee',
              'direction': 'expense',
              'baseConfidence': 0.9,
              'pattern': r'^zz 0\.00 (?<amount>[\d.]+)',
            });
        });
      final r = _parsed(_pipelineOf(f).parse(_req('zz 0.00 5.00')));
      expect(r.templateId, 'nbe.zz_b.en');
      expect(r.fields.amount!.toCanonicalString(), '5.00');
    });
  });

  group('language ordering (stage 3)', () {
    test('detectLanguage', () {
      final rows = <(String, MessageLanguage)>[
        ('تم خصم 200 جم', MessageLanguage.ar),
        ('Purchase of EGP 200', MessageLanguage.en),
        ('NBE: تم خصم 200.00 جم لدى AMAZON', MessageLanguage.ar),
        ('1234 5678', MessageLanguage.ar),
        ('', MessageLanguage.ar),
      ];
      for (final (text, lang) in rows) {
        expect(detectLanguage(text), lang, reason: 'row of ${text.length}');
      }
    });

    test('the detected language is tried first, the other still tried', () {
      final f = files.copy()
        ..editInstitution('nbe.json', (j) {
          // An English-tagged template placed first that also matches an
          // Arabic body: the Arabic template must win by language order.
          (j['templates']! as List<Object?>).insert(0, {
            'id': 'nbe.loose.en',
            'version': 1,
            'lang': 'en',
            'event': 'fee',
            'direction': 'expense',
            'baseConfidence': 0.5,
            'pattern': r'(?<amount>[\d,.]+)',
          });
        });
      final p = _pipelineOf(f);
      final ar = _parsed(p.parse(_req('تم إيداع نقدي 500.00 جم في حسابكم')));
      expect(ar.templateId, 'nbe.cash_deposit.ar');
      // An English body of no known shape falls to the loose English one.
      final en = _parsed(p.parse(_req('hello 12.50')));
      expect(en.templateId, 'nbe.loose.en');
      // An Arabic body that only the other-language template matches is
      // still read.
      final other = _parsed(p.parse(_req('مرحبا 7.25')));
      expect(other.templateId, 'nbe.loose.en');
    });
  });

  group('sanity penalties and confidence (stage 7)', () {
    ParseParsed salary(String date, {String? time, DateTime? at}) => _parsed(
      pipeline.parse(
        _req(
          'تم إيداع راتب 15,000.00 جم في حسابكم رقم **4567 بتاريخ $date'
          '${time == null ? '' : ' الساعة $time'}',
          at: at,
        ),
      ),
    );

    test('date window: 3 days ahead is fine, 4 is not', () {
      final at = DateTime.utc(2026, 10, 12, 9);
      expect(salary('15/10/2026', at: at).reasons, isEmpty);
      final late = salary('16/10/2026', at: at);
      expect(late.reasons, [ParseReason.dateOutOfRange]);
      expect(late.confidencePermille, 672);
      expect(late.needsReview, isTrue);
    });

    test('date window: exactly 2 years back is fine, one day more is not', () {
      expect(salary('23/10/2024').reasons, isEmpty);
      expect(salary('22/10/2024').reasons, [ParseReason.dateOutOfRange]);
    });

    test('a calendar-invalid date is a reason, the field stays null', () {
      final r = salary('31/02/2026');
      expect(r.fields.date, isNull);
      expect(r.reasons, [ParseReason.dateInvalid]);
      expect(r.confidencePermille, 672);
      expect(r.fields.occurredAtSource, OccurredAtSource.receivedAt);
    });

    test('an impossible time is a reason, the field stays null', () {
      final r = salary('25/10/2026', time: '25:99');
      expect(r.fields.time, isNull);
      expect(r.reasons, [ParseReason.timeInvalid]);
      expect(r.fields.occurredAtSource, OccurredAtSource.messageDate);
    });

    test('an invalid balance is dropped with a penalty, amount kept', () {
      final r = _parsed(
        pipeline.parse(
          _req(
            'NBE: Purchase of EGP 200.00 from NBE Visa **4567 at ZARA on 23/10. Avl Bal EGP 1.2.3',
          ),
        ),
      );
      expect(r.fields.amount!.toCanonicalString(), '200.00');
      expect(r.fields.balance, isNull);
      expect(r.reasons, [ParseReason.balanceInvalid]);
      expect(r.confidencePermille, 776);
      expect(r.needsReview, isTrue);
    });

    group('signed balance (FU-078)', () {
      // The shipped test template captures no sign; a copy whose balance
      // group allows leading `-` or `−` stands in for a bank that writes
      // overdrawn balances (up to two, so the parser's one-sign rule is
      // what rejects `--`).
      final signed = files.copy()
        ..editInstitution('nbe.json', (json) {
          for (final t in json['templates']! as List<Object?>) {
            final m = t! as Map<String, Object?>;
            if (m['id'] == 'nbe.card_purchase.en') {
              m['pattern'] = (m['pattern']! as String).replaceFirst(
                '(?<balance>[\\d,.]+)',
                '(?<balance>[-\u2212]{0,2}[\\d,.]+)',
              );
              m['version'] = 3;
            }
          }
        });
      final p = _pipelineOf(signed);
      ParseParsed purchase(String balance) => _parsed(
        p.parse(
          _req(
            'NBE: Purchase of EGP 200.00 from NBE Visa **4567 at ZARA on 23/10. Avl Bal EGP $balance',
          ),
        ),
      );

      for (final sign in ['-', '\u2212']) {
        test('a leading ${sign == '-' ? 'hyphen' : 'minus sign'} gives a '
            'negative balance, informational reason, no penalty', () {
          final r = purchase('${sign}500.25');
          expect(r.fields.balance!.minor, -50025);
          expect(r.fields.balance!.currency.code, 'EGP');
          expect(r.fields.amount!.minor, 20000);
          expect(r.reasons, [ParseReason.balanceNegative]);
          expect(r.confidencePermille, 970);
          expect(r.needsReview, isFalse);
        });
      }

      test('a negative zero is zero, no reason', () {
        final r = purchase('-0.00');
        expect(r.fields.balance!.minor, 0);
        expect(r.reasons, isEmpty);
      });

      test('two signs are still invalid', () {
        final r = purchase('--5.00');
        expect(r.fields.balance, isNull);
        expect(r.reasons, [ParseReason.balanceInvalid]);
      });

      test('a sign on the amount is never accepted', () {
        final amountSigned = files.copy()
          ..editInstitution('nbe.json', (json) {
            for (final t in json['templates']! as List<Object?>) {
              final m = t! as Map<String, Object?>;
              if (m['id'] == 'nbe.card_purchase.en') {
                m['pattern'] = (m['pattern']! as String).replaceFirst(
                  '(?<amount>[\\d,.]+)',
                  '(?<amount>-?[\\d,.]+)',
                );
                m['version'] = 3;
              }
            }
          });
        final r = _pipelineOf(amountSigned).parse(
          _req(
            'NBE: Purchase of EGP -200.00 from NBE Visa **4567 at ZARA on 23/10.',
          ),
        );
        expect(r, isNot(isA<ParseParsed>()));
      });
    });

    test('an unknown original currency is dropped with a penalty', () {
      final r = _parsed(
        pipeline.parse(
          _req('NBE: XQZ 10.50 at ZALANDO charged EGP 560.25 on card *4567'),
        ),
      );
      expect(r.fields.originalAmount, isNull);
      expect(r.fields.amount!.toCanonicalString(), '560.25');
      expect(r.reasons, [ParseReason.originalAmountInvalid]);
      expect(r.confidencePermille, 679);
    });

    test('a merchant that cleans to nothing is a reason and null', () {
      final r = _parsed(
        pipeline.parse(
          _req('NBE: Card *4567 purchase of EGP 20.00 at ... declined'),
        ),
      );
      expect(r.fields.merchant, isNull);
      expect(r.reasons, [ParseReason.merchantEmpty]);
      expect(r.confidencePermille, 760);
    });

    test('each penalty has a factor in 600..900 (informational reasons '
        '1000) and the threshold is 850', () {
      for (final reason in ParseReason.values) {
        if (reason == ParseReason.balanceNegative) {
          expect(reason.factorPermille, 1000);
          continue;
        }
        expect(reason.factorPermille, inInclusiveRange(600, 900));
      }
      expect(kAutoAcceptThresholdPermille, 850);
    });

    test('the threshold decides needsReview', () {
      // 950 x 0.9 = 855: above the line, saved without review.
      final sparse = _parsed(
        pipeline.parse(_req('تم إيداع نقدي 500.00 جم في حسابكم')),
      );
      expect(sparse.confidencePermille, 855);
      expect(sparse.needsReview, isFalse);
      final low = salary('25/10/2022');
      expect(low.needsReview, isTrue);
    });
  });

  group('occurredAt policy (parsing-engine 4.4)', () {
    final at = DateTime.utc(2026, 10, 23, 0, 5);
    final rows = <(String, DateTime?, WallTime?, DateTime, OccurredAtSource)>[
      (
        'date and time',
        DateTime.utc(2026, 10, 20),
        const WallTime(9, 30),
        DateTime.utc(2026, 10, 20, 9, 30),
        OccurredAtSource.messageDateTime,
      ),
      (
        'date only takes the received time of day',
        DateTime.utc(2026, 10, 20),
        null,
        DateTime.utc(2026, 10, 20, 0, 5),
        OccurredAtSource.messageDate,
      ),
      (
        'time only, earlier today',
        null,
        const WallTime(0, 1),
        DateTime.utc(2026, 10, 23, 0, 1),
        OccurredAtSource.messageTime,
      ),
      (
        'time only, later than receipt means yesterday',
        null,
        const WallTime(23, 58),
        DateTime.utc(2026, 10, 22, 23, 58),
        OccurredAtSource.messageTime,
      ),
      (
        'nothing in the message',
        null,
        null,
        DateTime.utc(2026, 10, 23, 0, 5),
        OccurredAtSource.receivedAt,
      ),
    ];
    for (final (name, date, time, want, source) in rows) {
      test(name, () {
        final (got, src) = resolveOccurredAt(date, time, at);
        expect(got, want);
        expect(src, source);
      });
    }

    test('year wrap comes from the template policy', () {
      final r = _parsed(
        pipeline.parse(
          _req(
            'تم خصم 45.00 جم ببطاقة فيزا **4567 لدى TALABAT يوم 30/12',
            at: DateTime.utc(2026, 1, 2, 8),
          ),
        ),
      );
      expect(r.fields.date, DateTime.utc(2025, 12, 30));
    });

    test('a zoned DateTime counts by its wall clock only', () {
      final local = DateTime(2026, 10, 23, 11, 14);
      final a = _parsed(
        pipeline.parse(
          _req('تم إيداع نقدي 500.00 جم في حسابكم رقم 4567', at: local),
        ),
      );
      expect(a.fields.occurredAt, DateTime.utc(2026, 10, 23, 11, 14));
      expect(a.fields.occurredAt.isUtc, isTrue);
    });
  });

  group('parseWallTime', () {
    final rows = <(String, WallTime?)>[
      ('09:30', const WallTime(9, 30)),
      ('9:30', const WallTime(9, 30)),
      ('23:59:58', const WallTime(23, 59, 58)),
      ('٠٩:٣٠', const WallTime(9, 30)),
      ('3:05 pm', const WallTime(15, 5)),
      ('3:05pm', const WallTime(15, 5)),
      ('3:05 م', const WallTime(15, 5)),
      ('3:05 ص', const WallTime(3, 5)),
      ('12:00 am', const WallTime(0, 0)),
      ('12:30 pm', const WallTime(12, 30)),
      ('13:00 pm', null),
      ('0:30 am', null),
      ('24:00', null),
      ('12:60', null),
      ('12:30:60', null),
      ('1230', null),
      ('', null),
      ('ab:cd', null),
    ];
    for (final (text, want) in rows) {
      test('time "$text"', () {
        expect(parseWallTime(text), want);
      });
    }
  });

  group('invariants', () {
    test('deterministic: the same input gives the same result', () {
      const body =
          'NBE: Purchase of EGP 200.00 from NBE Visa **4567 at AMAZON EG on 23/10. Avl Bal EGP 12,400.00';
      final a = _parsed(pipeline.parse(_req(body)));
      final b = _parsed(pipeline.parse(_req(body)));
      expect(a.templateId, b.templateId);
      expect(a.confidencePermille, b.confidencePermille);
      expect(a.fields.amount, b.fields.amount);
      expect(a.fields.occurredAt, b.fields.occurredAt);
    });

    test('fuzz: never throws, always a typed result', () {
      final rnd = Random(33);
      const alphabet = [
        'تم خصم ',
        'NBE: ',
        'Purchase of EGP ',
        '**4567',
        ' *',
        '١٢٣٫٤٥',
        '200.00',
        ' جم ',
        'لدى ',
        'يوم ',
        '23/10',
        'ـ',
        '‏',
        '(',
        ')',
        r'\',
        '😀',
        ' ',
        '\n',
        'x',
      ];
      const sources = ['NBE', 'CIB', 'AlAhly', 'NOBODY', '', 'com.example.nbe'];
      for (var i = 0; i < 4000; i++) {
        final b = StringBuffer();
        for (var k = rnd.nextInt(30); k >= 0; k--) {
          b.write(alphabet[rnd.nextInt(alphabet.length)]);
        }
        final r = pipeline.parse(
          _req(
            b.toString(),
            source: sources[rnd.nextInt(sources.length)],
            channel: RegistryChannel
                .values[rnd.nextInt(RegistryChannel.values.length)],
          ),
        );
        expect(
          r,
          anyOf(
            isA<ParseParsed>(),
            isA<ParseGeneric>(),
            isA<ParseDropped>(),
            isA<ParseUnrecognized>(),
          ),
        );
        if (r is ParseUnrecognized) {
          expect(r.reason, isNot(UnrecognizedReason.internalError));
        }
      }
    });

    test('results carry no message text beyond the captured fields', () {
      const sentinel = 'ZZSENTINEL7Q';
      final cases = <String>[
        'NBE: Purchase of EGP 200.00 from NBE Visa **4567 at AMAZON on 23/10. $sentinel',
        'NBE: $sentinel hello',
        '$sentinel OTP 1234',
        'تم خصم 10.505 جم ببطاقة **4567 لدى X يوم 23/10 $sentinel',
        sentinel,
      ];
      for (final body in cases) {
        for (final source in ['NBE', 'NOBODY']) {
          final r = pipeline.parse(_req(body, source: source));
          expect(_allStrings(r).any((s) => s.contains(sentinel)), isFalse);
        }
      }
    });

    test('non-parsed results hold only registry ids and enum codes', () {
      final institutions = {
        for (final i in _registryOf(files).institutions) i.code,
      };
      final templates = {
        for (final i in _registryOf(files).institutions)
          for (final t in i.templates) t.id,
      };
      for (final body in [
        'NBE: Purchase of EGP 10.505 from NBE Visa **4567 at ZARA on 23/10.',
        'NBE: nothing here',
        'Your OTP is 1',
      ]) {
        final r = pipeline.parse(_req(body));
        for (final s in _allStrings(r)) {
          expect(institutions.contains(s) || templates.contains(s), isTrue);
        }
      }
    });
  });

  test('benchmark: mean parse time is under 2 ms (AC 3)', () {
    final bodies = <(String, String)>[];
    for (final text in files.fixtures.values) {
      final j = jsonDecode(text) as Map<String, Object?>;
      bodies.add((j['sender']! as String, j['body']! as String));
    }
    final requests = [
      for (final (s, b) in bodies) _req(b, source: s),
      // Misses cost the most: every template is tried.
      _req('NBE: ${'ا' * 300} ${'1' * 300}'),
      _req('x' * 1500, source: 'CIB'),
    ];
    for (var i = 0; i < 300; i++) {
      pipeline.parse(requests[i % requests.length]); // warm-up (JIT)
    }
    const runs = 4000;
    final clock = Stopwatch()..start();
    var parsed = 0;
    for (var i = 0; i < runs; i++) {
      if (pipeline.parse(requests[i % requests.length]) is ParseParsed) {
        parsed += 1;
      }
    }
    clock.stop();
    final meanMicros = clock.elapsedMicroseconds / runs;
    expect(parsed, greaterThan(runs ~/ 2));
    // ignore: avoid_print
    print('pipeline parse mean: ${meanMicros.round()} us over $runs runs');
    // FU-214: ~1.3x the first perf run (83 us).
    expect(meanMicros, lessThan(110), reason: 'mean ${meanMicros.round()} us');
  }, tags: 'benchmark');
}

Registry _registryOf(RegistryFiles f) => RegistryLoader.load(
  manifest: f.manifest,
  shared: f.shared,
  institutions: f.institutions,
).registry!;

/// Every string a result holds, for the no-echo checks.
List<String> _allStrings(ParseResult r) {
  switch (r) {
    case ParseDropped():
      return [?r.institutionCode];
    case ParseUnrecognized():
      return [?r.institutionCode, ?r.templateId];
    case ParseGeneric():
      return [r.language, ?r.last4, ?r.merchant?.display, ?r.merchant?.key];
    case ParseParsed():
      final f = r.fields;
      return [
        r.institutionCode,
        r.templateId,
        r.language,
        ?f.last4,
        ?f.merchant?.display,
        ?f.merchant?.cleaned,
        ?f.merchant?.key,
        ?f.counterparty?.name,
        ?f.counterparty?.ipa,
        ?f.counterparty?.phone,
        ?f.ref,
      ];
  }
}
