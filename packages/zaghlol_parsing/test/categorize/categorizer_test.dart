// T-075: categorizer tiers, thresholds, negative proofs, determinism. Ports
// are in-memory fakes with synthetic data. The real seed and database are
// exercised in app/test/features/categorization.

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import 'fake_ports.dart';

Future<CategoryDecision> run(
  ({
    FakeRules rules,
    FakeCatalog catalog,
    FakeKeywords keywords,
    FakeCategories cats,
    CategorizerPorts ports,
  })
  w,
  CategorizeInput i, {
  CategorizerConfig config = const CategorizerConfig(),
}) => categorize(i, w.ports, config: config);

AliasHit hit(int id, String alias, int merchant, AliasMatch m) =>
    AliasHit(id: id, aliasNorm: alias, merchantId: merchant, match: m);

void main() {
  group('threshold edges with a fake scorer (millionths)', () {
    final merchants = {
      1: const CatalogMerchant(id: 1, canonical: 'A', categoryCode: 'x'),
      2: const CatalogMerchant(id: 2, canonical: 'B', categoryCode: 'y'),
    };
    FuzzyPick pick(int s1, [int? s2]) {
      final scores = {'alphaa': s1, 'betaaa': s2 ?? 0};
      return pickFuzzy(
        'target',
        [
          hit(1, 'alphaa', 1, AliasMatch.prefix),
          hit(2, 'betaaa', 2, AliasMatch.prefix),
        ],
        merchants,
        CategorizerConfig(scorer: (a, b) => scores[a.replaceAll(' ', '')] ?? 0),
      );
    }

    test('919999 rejected, 920000 accepted, 920001 accepted', () {
      expect(pick(919999).merchant, isNull);
      expect(pick(919999).ambiguous, isFalse);
      expect(pick(920000).merchant?.id, 1);
      expect(pick(920001).merchant?.id, 1);
    });
    test('margin: 19999 ambiguous, 20000 not', () {
      expect(pick(960000, 960000 - 19999).ambiguous, isTrue);
      expect(pick(960000, 960000 - 19999).merchant, isNull);
      expect(pick(960000, 960000 - 20000).merchant?.id, 1);
    });
    test('margin only counts a runner-up of another category', () {
      final same = {
        1: const CatalogMerchant(id: 1, canonical: 'A', categoryCode: 'x'),
        2: const CatalogMerchant(id: 2, canonical: 'B', categoryCode: 'x'),
      };
      final scores = {'alphaa': 960000, 'betaaa': 959000};
      final p = pickFuzzy(
        'target',
        [
          hit(1, 'alphaa', 1, AliasMatch.prefix),
          hit(2, 'betaaa', 2, AliasMatch.prefix),
        ],
        same,
        CategorizerConfig(scorer: (a, b) => scores[a.replaceAll(' ', '')] ?? 0),
      );
      expect(p.merchant?.id, 1);
    });
    test(
      'contributed alias uses its own threshold (parameter, off by default)',
      () {
        final cfg = CategorizerConfig(
          contributedAliasIds: const {1},
          scorer: (a, b) => 890000,
        );
        expect(
          pickFuzzy(
            'target',
            [hit(1, 'alphaa', 1, AliasMatch.prefix)],
            merchants,
            cfg,
          ).merchant?.id,
          1,
        );
        expect(
          pickFuzzy(
            'target',
            [hit(2, 'alphaa', 1, AliasMatch.prefix)],
            merchants,
            cfg,
          ).merchant,
          isNull,
        );
      },
    );
    test('key length 5 never fuzzy, 6 may', () {
      final ms = {1: merchants[1]!};
      CategorizerConfig cfg() => CategorizerConfig(scorer: (a, b) => scoreOne);
      expect(
        pickFuzzy(
          'abcde',
          [hit(1, 'abcde', 1, AliasMatch.prefix)],
          ms,
          cfg(),
        ).merchant,
        isNull,
      );
      expect(
        pickFuzzy(
          'abcdef',
          [hit(1, 'abcdef', 1, AliasMatch.prefix)],
          ms,
          cfg(),
        ).merchant?.id,
        1,
      );
      // spaces do not count
      expect(
        pickFuzzy(
          'ab cd e',
          [hit(1, 'abcde', 1, AliasMatch.prefix)],
          ms,
          cfg(),
        ).merchant,
        isNull,
      );
    });
    test('digit mismatch rejects, digit match keeps', () {
      final ms = {1: merchants[1]!};
      final cfg = CategorizerConfig(scorer: (a, b) => scoreOne);
      expect(
        pickFuzzy(
          'ezaby 2',
          [hit(1, 'ezaby', 1, AliasMatch.prefix)],
          ms,
          cfg,
        ).merchant,
        isNull,
      );
      expect(
        pickFuzzy(
          'ezaby 2',
          [hit(1, 'ezaby 2', 1, AliasMatch.prefix)],
          ms,
          cfg,
        ).merchant?.id,
        1,
      );
      expect(
        pickFuzzy(
          'route 12',
          [hit(1, 'route 21', 1, AliasMatch.prefix)],
          ms,
          cfg,
        ).merchant,
        isNull,
      );
    });
  });

  group('keyword thresholds', () {
    test('score 59 / 60', () {
      expect(decideKeywords({'a': 59}), isNull);
      expect(decideKeywords({'a': 60}), 'a');
    });
    test('margin 19 / 20', () {
      expect(decideKeywords({'a': 80, 'b': 61}), isNull);
      expect(decideKeywords({'a': 80, 'b': 60}), 'a');
    });
    test('tie is ambiguous; no entries', () {
      expect(decideKeywords({'a': 80, 'b': 80}), isNull);
      expect(decideKeywords({}), isNull);
    });
    test(
      'whole tokens only, article ignored, multi-word, once per keyword',
      () {
        final k = [
          kw('cafe', 'd', 40),
          kw('coffee', 'd', 30),
          kw('بقالة', 'g', 60),
          kw('super market', 'g', 20),
        ];
        expect(scoreKeywords('cafe coffee', k), {'d': 70});
        expect(scoreKeywords('cafeteria', k), isEmpty);
        expect(scoreKeywords('البقالة', k), {'g': 60}); // leading ال ignored
        expect(scoreKeywords('ابقالة', k), isEmpty);
        expect(scoreKeywords('البقاله', [kw('بقاله', 'g', 60)]), {'g': 60});
        expect(scoreKeywords('big super market', k), {'g': 20});
        expect(
          scoreKeywords('cafe', [kw('cafe', 'd', 40), kw('cafe', 'd', 40)]),
          {'d': 40},
        );
      },
    );
  });

  group('tier order', () {
    test('rule beats catalog (merchant_norm rule)', () async {
      final w = buildWorld()
        ..rules.add('merchant_norm', 'carrefour', 'sys:dining');
      final d = await run(w, inp('CARREFOUR MAADI EG 041'));
      expect(d.categoryId, 'sys:dining');
      expect(d.source, CategorySource.userRule);
      expect(d.tier, CategorizeTier.rule);
    });

    test('counterparty rule beats merchant_norm rule', () async {
      final w = buildWorld()
        ..rules.add('merchant_norm', 'carrefour', 'sys:dining')
        ..rules.add('counterparty', 'shop@bank', 'sys:transport');
      final d = await run(
        w,
        inp('CARREFOUR', kind: PartyKind.merchant, value: 'shop@bank'),
      );
      expect(d.categoryId, 'sys:transport');
    });

    test(
      'merchant_norm rule beats catalog-merchant rule beats catalog',
      () async {
        final w = buildWorld()
          ..rules.add('catalog_merchant', '1', 'sys:transport')
          ..rules.add('merchant_norm', 'carrefour', 'sys:dining');
        expect((await run(w, inp('CARREFOUR'))).categoryId, 'sys:dining');
        final w2 = buildWorld()
          ..rules.add('catalog_merchant', '1', 'sys:transport');
        final d = await run(w2, inp('CARREFOUR'));
        expect(d.categoryId, 'sys:transport');
        expect(d.catalogMerchantId, 1);
        expect(d.source, CategorySource.userRule);
        final d3 = await run(buildWorld(), inp('CARREFOUR'));
        expect(d3.categoryId, 'sys:groceries');
        expect(d3.source, CategorySource.catalog);
      },
    );

    test('call B fires only after a merchant is found', () async {
      final w = buildWorld();
      await run(w, inp('ZZZZ UNKNOWN SHOP'));
      expect(w.rules.calls, ['A:norm']);
      final w2 = buildWorld();
      await run(w2, inp('CARREFOUR'));
      expect(w2.rules.calls, ['A:norm', 'B']);
    });

    test('exact beats a longer-looking prefix', () async {
      final w = buildWorld();
      w.catalog
        ..merchant(8, 'Zed', 'transport')
        ..alias(8, 'carrefour market', AliasMatch.exact)
        ..aliases.removeWhere(
          (a) => a.aliasNorm == 'carrefour market' && a.merchantId == 1,
        );
      w.catalog.alias(1, 'carrefour market x', AliasMatch.prefix);
      final d = await run(w, inp('CARREFOUR MARKET'));
      expect(d.catalogMerchantId, 8);
      expect(d.tier, CategorizeTier.exact);
    });

    test('longest prefix wins; talabat mart over talabat', () async {
      final w = buildWorld();
      final d = await run(w, inp('TALABAT MART 22'));
      expect(d.catalogMerchantId, 4);
      expect(d.tier, CategorizeTier.prefix);
      expect((await run(w, inp('TALABAT FOOD'))).catalogMerchantId, 3);
      expect((await run(w, inp('EL EZABY'))).catalogMerchantId, 2);
      expect((await run(w, inp('ELEZABY'))).catalogMerchantId, 2);
    });

    test('token alias matches mid-key, prefix alias does not', () async {
      final w = buildWorld();
      final d = await run(w, inp('ORDER UBER TRIP'));
      expect(d.catalogMerchantId, 6);
      expect(d.tier, CategorizeTier.token);
      final d2 = await run(w, inp('FOO CARREFOUR'));
      expect(d2.catalogMerchantId, isNull);
    });

    test('alias must end on a token boundary (no substring)', () async {
      final w = buildWorld();
      expect((await run(w, inp('UBERX'))).catalogMerchantId, isNull);
      expect((await run(w, inp('CARREFOURS'))).tier, CategorizeTier.fuzzy);
    });

    test('alias with digits', () async {
      final d = await run(buildWorld(), inp('19011'));
      expect(d.catalogMerchantId, 2);
    });

    test('Arabic spelling reaches the Arabic alias', () async {
      final d = await run(buildWorld(), inp('صيدليات العزبي'));
      expect(d.catalogMerchantId, 2);
      expect(d.categoryId, 'sys:health');
    });
  });

  group('person-to-person and internal', () {
    for (final kind in [PartyKind.ipa, PartyKind.phone, PartyKind.person]) {
      test('${kind.name} without rule is needs classification', () async {
        final d = await run(
          buildWorld(),
          inp('CARREFOUR', kind: kind, value: 'x'),
        );
        expect(d.categoryId, isNull);
        expect(d.source, CategorySource.none);
        expect(d.tier, CategorizeTier.p2p);
        expect(d.catalogMerchantId, isNull);
      });
      test('${kind.name} with a rule is user_rule', () async {
        final w = buildWorld()..rules.add('counterparty', 'p', 'sys:dining');
        final d = await run(w, inp('', kind: kind, value: 'p'));
        expect(d.source, CategorySource.userRule);
        expect(d.categoryId, 'sys:dining');
      });
    }
    test('person named like a merchant stays none, keywords skipped', () async {
      final d = await run(
        buildWorld(),
        inp('Carrefour Cafe', kind: PartyKind.person, value: 'Carrefour Cafe'),
      );
      expect(d.categoryId, isNull);
    });
    test('own_account is internal, not categorized', () async {
      final d = await run(
        buildWorld(),
        inp('CARREFOUR', kind: PartyKind.ownAccount, value: 'me'),
      );
      expect(d.tier, CategorizeTier.internal);
      expect(d.categoryId, isNull);
    });
  });

  group('fuzzy', () {
    test('typo of a long key reaches the merchant', () async {
      final d = await run(buildWorld(), inp('CARREFOURR'));
      expect(d.tier, CategorizeTier.fuzzy);
      expect(d.catalogMerchantId, 1);
      expect(d.source, CategorySource.catalog);
    });
    test('metro does not fuzzy to metra (length gate)', () async {
      final d = await run(buildWorld(), inp('METRO'));
      expect(d.catalogMerchantId, isNull);
    });
    test('ezaby 2 does not match ezaby by fuzzy (digits)', () async {
      final d = await run(buildWorld(), inp('EZABYY 2'));
      expect(d.catalogMerchantId, isNull);
    });
    test('two same-score merchants in different categories: none', () async {
      final w = buildWorld();
      w.catalog
        ..merchant(10, 'Aaa', 'transport')
        ..alias(10, 'zamzamia')
        ..merchant(11, 'Bbb', 'dining')
        ..alias(11, 'zamzamie');
      final d = await run(w, inp('ZAMZAMIB'));
      expect(d.catalogMerchantId, isNull);
      expect(d.categoryId, isNull);
    });
    test('same category: lower canonical wins', () async {
      final w = buildWorld();
      w.catalog
        ..merchant(10, 'Bbb', 'dining')
        ..alias(10, 'zamzamia')
        ..merchant(11, 'Aaa', 'dining')
        ..alias(11, 'zamzamie');
      final d = await run(w, inp('ZAMZAMIB'));
      expect(d.catalogMerchantId, 11);
    });
    test(
      'ambiguous prefix level falls through to fuzzy/keywords, never guesses',
      () async {
        final w = buildWorld();
        w.catalog
          ..merchant(20, 'One', 'transport')
          ..alias(20, 'sharedname')
          ..merchant(21, 'Two', 'dining')
          ..alias(21, 'sharedname');
        final d = await run(w, inp('SHAREDNAME'));
        expect(d.catalogMerchantId, isNull);
      },
    );
  });

  group('categories and failures', () {
    test(
      'rule on an archived category is ignored; catalog continues',
      () async {
        final w = buildWorld(archived: {'dining'})
          ..rules.add('merchant_norm', 'carrefour', 'sys:dining');
        final d = await run(w, inp('CARREFOUR'));
        expect(d.source, CategorySource.catalog);
        expect(d.categoryId, 'sys:groceries');
      },
    );
    test('merchant with an archived category: merchant kept, none', () async {
      final d = await run(
        buildWorld(archived: {'groceries'}),
        inp('CARREFOUR'),
      );
      expect(d.categoryId, isNull);
      expect(d.catalogMerchantId, 1);
      expect(d.source, CategorySource.none);
    });
    test(
      'merchant with an unknown category code: merchant kept, none',
      () async {
        final w = buildWorld();
        w.catalog
          ..merchant(30, 'Ghost', 'nonexistent')
          ..alias(30, 'ghostly');
        final d = await run(w, inp('GHOSTLY'));
        expect(d.catalogMerchantId, 30);
        expect(d.categoryId, isNull);
      },
    );
    test('keywords decide when the catalog has nothing', () async {
      final d = await run(buildWorld(), inp('QWERTY PHARMACY'));
      expect(d.source, CategorySource.heuristic);
      expect(d.categoryId, 'sys:health');
      expect(d.tier, CategorizeTier.keyword);
    });
    test('Arabic keyword with article', () async {
      final d = await run(
        buildWorld(),
        CategorizeInput(
          merchantText: foldKey('الصيدلية الجديدة'),
          merchantNorm: 'aljdyda',
        ),
      );
      expect(d.categoryId, 'sys:health');
    });
    test('keyword margin: gym 60 vs 30 is below the margin', () async {
      final d = await run(buildWorld(), inp('QWERTY GYM'));
      expect(d.categoryId, 'sys:fitness'); // 60 vs 30: margin 30
    });
    test('counterparty-only message, empty key', () async {
      final w = buildWorld()
        ..rules.add('counterparty', 'shop@bank', 'sys:dining');
      final d = await run(
        w,
        const CategorizeInput(
          counterpartyKind: PartyKind.merchant,
          counterpartyValue: 'shop@bank',
        ),
      );
      expect(d.categoryId, 'sys:dining');
    });
    test('empty and emoji-only keys: no catalog, no rule call', () async {
      final w = buildWorld();
      expect((await run(w, inp(''))).tier, CategorizeTier.none);
      expect((await run(w, inp('🍔'))).tier, CategorizeTier.none);
      expect(w.rules.calls, isEmpty);
      expect(w.catalog.queries, 0);
    });
    test('non-canonical key is treated as no key', () async {
      final w = buildWorld();
      final d = await run(
        w,
        const CategorizeInput(merchantNorm: 'Not Canonical!'),
      );
      expect(d.tier, CategorizeTier.none);
      expect(w.catalog.queries, 0);
    });
    test('el-prefixed English word stays unmatched', () async {
      final d = await run(buildWorld(), inp('ELECTRONICS HUB'));
      expect(d.catalogMerchantId, isNull);
    });
    test('port failure propagates, is not read as no match', () async {
      final w = buildWorld();
      final ports = CategorizerPorts(
        rules: w.rules,
        catalog: _Failing(),
        keywords: w.keywords,
        categories: w.cats,
      );
      await expectLater(
        categorize(inp('CARREFOUR'), ports),
        throwsA(isA<StateError>()),
      );
    });
    test('no raw text in decision or input toString', () async {
      const s = 'T075SENTINEL';
      final d = await run(buildWorld(), inp(s));
      expect(d.toString(), isNot(contains(s)));
      expect(inp(s).toString(), isNot(contains(s)));
    });
  });

  group('determinism and memo', () {
    final inputs = [
      'CARREFOUR MAADI EG 041',
      'TALABAT MART',
      'EL EZABY',
      'CARREFOURR',
      'QWERTY PHARMACY',
      'ORDER UBER TRIP',
      'ZZZ',
      'NETFLIX',
      'صيدليات العزبي',
    ];
    test(
      'shuffled port results give the identical decision (20 runs)',
      () async {
        final base = [for (final i in inputs) await run(buildWorld(), inp(i))];
        for (var seed = 1; seed <= 20; seed++) {
          final w = buildWorld(shuffleSeed: seed);
          for (var n = 0; n < inputs.length; n++) {
            expect(
              await run(w, inp(inputs[n])),
              base[n],
              reason: 'seed $seed ${inputs[n].hashCode}',
            );
          }
        }
      },
    );
    test('matchAliases ignores input order', () {
      final hits = [
        hit(1, 'a b', 1, AliasMatch.prefix),
        hit(2, 'a', 2, AliasMatch.prefix),
        hit(3, 'b', 3, AliasMatch.token),
      ];
      for (var i = 0; i < 6; i++) {
        final l = [...hits]..shuffle();
        expect(matchAliases('a b c', l).map((h) => h.id), [1]);
      }
    });
    test('memoized run categorizes each distinct input once', () async {
      final w = buildWorld();
      final c = Categorizer(w.ports, memoize: true);
      for (var i = 0; i < 5; i++) {
        await c.categorize(inp('CARREFOUR'));
      }
      expect(w.rules.calls.where((c) => c == 'B').length, 1);
      await c.categorize(inp('QWERTY PHARMACY'));
      await c.categorize(inp('ASDF GYM'));
      expect(w.keywords.loads, 1);
    });
    test('round trips per message are at most 7', () async {
      final w = buildWorld();
      await run(w, inp('CARREFOURR'));
      // rules A + B, exact, prefix/token, FTS, merchants x (exact skip) ...
      expect(w.rules.calls.length + w.catalog.queries, lessThanOrEqualTo(7));
    });
  });
}

final class _Failing implements CatalogPort {
  @override
  Future<List<AliasHit>> aliasesEqualTo(String key) => throw StateError('DB');
  @override
  Future<List<AliasHit>> aliasesByKeys(
    Set<String> keys,
    Set<AliasMatch> kinds,
  ) => throw StateError('DB');
  @override
  Future<List<AliasHit>> aliasCandidates(String key, {int limit = 10}) =>
      throw StateError('DB');
  @override
  Future<List<CatalogMerchant>> merchantsByIds(Set<int> ids) =>
      throw StateError('DB');
}
