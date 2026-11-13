// T-109: voice phrase parser. Table-driven over the synthetic phrase
// fixture (test/fixtures/voice/phrases.json) plus targeted unit tests.
// Ports are in-memory fakes; the real catalog is exercised in the app.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../categorize/fake_ports.dart';

final Currency egp = Currency.of('EGP');

CategorizerPorts world() {
  final catalog = FakeCatalog()
    ..merchant(1, 'Carrefour', 'groceries')
    ..alias(1, 'carrefour')
    ..merchant(2, 'Talabat', 'dining')
    ..alias(2, 'talabat')
    ..merchant(3, 'Uber', 'transport')
    ..alias(3, 'uber', AliasMatch.token)
    ..merchant(4, 'Careem', 'transport')
    ..alias(4, 'careem', AliasMatch.token)
    ..merchant(5, 'Starbucks', 'dining')
    ..alias(5, 'starbucks')
    ..merchant(6, 'Netflix', 'subscriptions')
    ..alias(6, 'netflix', AliasMatch.exact)
    ..merchant(7, 'Vodafone', 'bills')
    ..alias(7, 'vodafone');
  final raw = jsonDecode(
    File('test/fixtures/voice/keywords.json').readAsStringSync(),
  ) as List<Object?>;
  final keywords = FakeKeywords([
    for (final e in raw.cast<Map<String, Object?>>())
      kw(e['k']! as String, e['c']! as String, e['w']! as int),
  ]);
  final cats = FakeCategories([
    'groceries',
    'dining',
    'transport',
    'bills',
    'health',
    'shopping',
    'entertainment',
    'subscriptions',
  ]);
  return CategorizerPorts(
    rules: FakeRules(),
    catalog: catalog,
    keywords: keywords,
    categories: cats,
  );
}

List<VoiceItem> parse(String s, {Currency? def}) {
  final r = parseVoicePhrase(s, defaultCurrency: def ?? egp);
  expect(r, isA<VoiceParsed>(), reason: 'unrecognized phrase');
  return (r as VoiceParsed).items;
}

Set<String> issueNames(VoiceItem i) => {for (final x in i.issues) x.name};

void main() {
  final ports = world();
  final phrases = (jsonDecode(
    File('test/fixtures/voice/phrases.json').readAsStringSync(),
  ) as List<Object?>).cast<Map<String, Object?>>();

  group('phrase fixtures (FR-VOI-02/05, EC-30, EC-31)', () {
    var total = 0;
    var correct = 0;
    final failures = <String>[];

    test('fixture set is at least 200 phrases', () {
      expect(phrases.length, greaterThanOrEqualTo(200));
    });

    test(
      'item accuracy is at least 95% and every phrase is reported',
      () async {
        for (final p in phrases) {
          final expected = (p['items']! as List<Object?>)
              .cast<Map<String, Object?>>();
          final r = parseVoicePhrase(
            p['text']! as String,
            defaultCurrency: egp,
          );
          final got = r is VoiceParsed
              ? await categorizeVoiceItems(r.items, ports)
              : <CategorizedVoiceItem>[];
          total += expected.length;
          for (var k = 0; k < expected.length; k++) {
            final e = expected[k];
            final ok = k < got.length && _matches(got[k], e);
            if (ok) {
              correct++;
            } else {
              failures.add('${p['id']} item $k (${p['tag']})');
            }
          }
          if (got.length != expected.length) {
            failures.add(
              '${p['id']} count ${got.length} != ${expected.length}',
            );
          }
        }
        final pct = correct * 100 / total;
        // ignore: avoid_print
        print(
          'voice fixtures: $correct/$total items ($pct%), '
          '${phrases.length} phrases; failures: $failures',
        );
        expect(pct, greaterThanOrEqualTo(95));
      },
    );

    test('every phrase matches exactly (count and each item)', () async {
      // Run after the accuracy test; stricter than the AC so regressions
      // in a single phrase are visible by id.
      expect(failures, isEmpty);
    });
  });

  test('spec phrase gives 150 Groceries, 45 Dining, 30 Transport', () async {
    final items = parse(
      'دفعت ١٥٠ جنيه خضار وفاكهة و ٤٥ جنيه قهوة و ٣٠ جنيه تاكسي',
    );
    final cat = await categorizeVoiceItems(items, ports);
    expect([for (final c in cat) c.item.amount!.minor], [15000, 4500, 3000]);
    expect(
      [for (final c in cat) c.decision.categoryId],
      ['sys:groceries', 'sys:dining', 'sys:transport'],
    );
    expect(
      [for (final c in cat) c.item.amount!.currency.code],
      ['EGP', 'EGP', 'EGP'],
    );
  });

  group('unrecognized input never throws', () {
    VoiceUnrecognizedReason? why(String s) {
      final r = parseVoicePhrase(s, defaultCurrency: egp);
      return r is VoiceUnrecognized ? r.reason : null;
    }

    test('empty, blank, only verbs, too long', () {
      expect(why(''), VoiceUnrecognizedReason.empty);
      expect(why('   \n '), VoiceUnrecognizedReason.empty);
      expect(why('...'), VoiceUnrecognizedReason.empty);
      expect(why('دفعت'), VoiceUnrecognizedReason.noContent);
      expect(why('I paid for'), VoiceUnrecognizedReason.noContent);
      expect(why('x' * 1001), VoiceUnrecognizedReason.tooLong);
    });

    test('hostile text does not throw or hang', () {
      final sw = Stopwatch()..start();
      for (final s in [
        '${'ميت و' * 100}خمسين',
        '9' * 500,
        '${'٩' * 40} جنيه',
        List.filled(200, 'و').join(' '),
        '\u200f\u202e١٥٠\u0640جنيه',
        '1,2,3,4,5,6',
        '،،،',
        '\u{1F600} 5',
        'جنيه ' * 100,
        'ألف ' * 100,
      ]) {
        expect(
          () => parseVoicePhrase(s, defaultCurrency: egp),
          returnsNormally,
        );
      }
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('toString never carries the phrase', () {
      final items = parse('دفعت 150 جنيه سر');
      expect(items.single.toString(), isNot(contains('سر')));
    });
  });

  group('amounts', () {
    int minor(String s, {Currency? def}) =>
        parse(s, def: def).first.amount!.minor;

    test('thousands, fractions and pounds-and-piasters', () {
      expect(minor('دفعت الف ونص قهوة'), 150000);
      expect(minor('دفعت ميت ونص قهوة'), 15000);
      expect(minor('دفعت جنيه ونص قهوة'), 150);
      expect(minor('دفعت تلت جنيه قهوة'), 33);
      expect(minor('دفعت خمسة جنيه وخمسين قرش قهوة'), 550);
    });

    test('currency exponent drives minor units (no double)', () {
      final kwd = Currency.of('KWD');
      expect(minor('دفعت 12.5 قهوة', def: kwd), 12500);
      final jpy = Currency.of('JPY');
      expect(minor('دفعت 500 قهوة', def: jpy), 500);
    });

    test('digits beyond 12 are not an amount; huge words do not overflow', () {
      final items = parse('دفعت ${'9' * 13} قهوة');
      expect(items.first.amount, isNull);
    });

    test('T109-1: fraction before million scales the million', () {
      expect(minor('دفعت نص مليون جنيه عربية'), 50000000);
      expect(minor('اشتريت ربع مليون شقة'), 25000000);
      expect(minor('دفعت تلت مليون جنيه'), 33333333);
      final items = parse('دفعت نص مليون جنيه عربية');
      expect(items, hasLength(1));
      expect(items.single.text, 'عربية');
      expect(minor('دفعت نص الف قهوة'), 50000);
    });

    test('T109-2: over-long digit amounts are invalid, not 1 pound', () {
      for (final s in [
        'دفعت 1000000000000 جنيه قهوة',
        'دفعت 12345678901234567890 جنيه',
        'دفعت 12.34567 جنيه قهوة',
        'دفعت 12.34567 قهوة',
        'دفعت ${'9' * 13} قهوة',
      ]) {
        final items = parse(s);
        expect(items, hasLength(1), reason: s);
        expect(items.first.amount, isNull, reason: s);
        expect(
          items.first.issues,
          contains(VoiceIssue.invalidAmount),
          reason: s,
        );
      }
    });

    test('the default currency applies only when none is spoken', () {
      final usd = Currency.of('USD');
      final a = parse('دفعت 50 قهوة', def: usd).single;
      expect(a.amount!.currency, usd);
      expect(a.currencySpoken, isFalse);
      final b = parse('دفعت 50 جنيه قهوة', def: usd).single;
      expect(b.amount!.currency, egp);
      expect(b.currencySpoken, isTrue);
    });
  });

  group('EC-30 flags', () {
    test('no amount and no item text', () {
      final a = parse('قهوة').single;
      expect(a.amount, isNull);
      expect(issueNames(a), {'missingAmount'});
      final b = parse('دفعت 150 جنيه').single;
      expect(b.amount!.minor, 15000);
      expect(issueNames(b), {'missingItemText'});
    });
  });

  group('categorization', () {
    test('catalog merchant, keyword, needs classification (EC-31)', () async {
      final items = parse('دفعت 200 Uber و 45 شي غريب');
      final cat = await categorizeVoiceItems(items, ports);
      expect(cat[0].decision.categoryId, 'sys:transport');
      expect(cat[1].decision.needsClassification, isTrue);
      expect(cat[1].confidencePermille, lessThan(cat[0].confidencePermille));
    });

    test('a user rule wins over the catalog', () async {
      final w = world();
      (w.rules as FakeRules).add('merchant_norm', 'uber', 'sys:dining');
      final cat = await categorizeVoiceItems(parse('دفعت 200 Uber'), w);
      expect(cat.single.decision.categoryId, 'sys:dining');
      expect(cat.single.decision.source, CategorySource.userRule);
    });

    test('glued prefixes still find the keyword', () async {
      final cat = await categorizeVoiceItems(
        parse('دفعت 30 للتاكسي و 20 وقهوة'),
        ports,
      );
      expect(cat[0].decision.categoryId, 'sys:transport');
      expect(cat[1].decision.categoryId, 'sys:dining');
    });

    test('deterministic', () async {
      final a = await categorizeVoiceItems(parse('قهوة 50 وتاكسي 30'), ports);
      final b = await categorizeVoiceItems(parse('قهوة 50 وتاكسي 30'), ports);
      expect([for (final x in a) x.decision], [for (final x in b) x.decision]);
    });
  });

  test('parses within the performance budget', () {
    final sw = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      parse('دفعت ١٥٠ جنيه خضار وفاكهة و ٤٥ جنيه قهوة و ٣٠ جنيه تاكسي');
    }
    // 200 parses: far under 10 ms each even on a slow CI box.
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });
}

bool _matches(CategorizedVoiceItem got, Map<String, Object?> e) {
  final m = got.item.amount;
  final wantMinor = e['amountMinor'] as int?;
  if ((m?.minor) != wantMinor) return false;
  if (m != null && m.currency.code != e['currency']) return false;
  final cat = e['category'] as String?;
  final gotCat = got.decision.categoryId;
  if (cat == null ? gotCat != null : gotCat != 'sys:$cat') return false;
  final wantIssues = ((e['issues'] as List<Object?>?) ?? const []).toSet();
  return issueNames(got.item).containsAll(wantIssues) &&
      issueNames(got.item).length == wantIssues.length;
}
