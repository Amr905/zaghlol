// T-357: the AI tier (LLM-CATEGORISE, llm-categorise.md §7 "Categorizer").
// It comes after keywords and only answers where every earlier tier found
// nothing. Synthetic data only.

import 'package:test/test.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import 'fake_ports.dart';

final class FakeAi implements AiSuggestionPort {
  final Map<String, String> unconfirmed = {};
  final List<String> asked = [];

  @override
  Future<String?> aiSuggestionFor(String merchantNorm) async {
    asked.add(merchantNorm);
    return unconfirmed[merchantNorm];
  }
}

void main() {
  late FakeAi ai;
  late Categorizer cat;
  late FakeRules rules;

  setUp(() {
    final w = buildWorld();
    ai = FakeAi();
    rules = w.rules;
    cat = Categorizer(
      CategorizerPorts(
        rules: w.rules,
        catalog: w.catalog,
        keywords: w.keywords,
        categories: w.cats,
        ai: ai,
      ),
    );
  });

  const aiDining = CategoryDecision(
    categoryId: 'sys:dining',
    source: CategorySource.ai,
    tier: CategorizeTier.ai,
  );

  test('an unknown merchant gets its unconfirmed suggestion', () async {
    ai.unconfirmed['zawya'] = 'sys:dining';
    expect(await cat.categorize(inp('ZAWYA')), aiDining);
    expect(CategorySource.ai.code, 'ai');
  });

  test('no suggestion, or an archived/missing category: needs '
      'classification', () async {
    expect((await cat.categorize(inp('ZAWYA'))).needsClassification, isTrue);
    ai.unconfirmed['zawya'] = 'sys:gone';
    expect((await cat.categorize(inp('ZAWYA'))).needsClassification, isTrue);
  });

  test('every earlier tier wins over the suggestion', () async {
    ai.unconfirmed
      ..['carrefour'] = 'sys:dining'
      ..['best pharmacy'] = 'sys:dining'
      ..['ruled'] = 'sys:dining';
    rules.add('merchant_norm', 'ruled', 'sys:health');
    // Catalog.
    expect(
      (await cat.categorize(inp('CARREFOUR'))).source,
      CategorySource.catalog,
    );
    // Keyword.
    expect(
      (await cat.categorize(inp('BEST PHARMACY'))).source,
      CategorySource.heuristic,
    );
    // User rule (FU-408).
    expect(
      (await cat.categorize(inp('RULED'))).source,
      CategorySource.userRule,
    );
  });

  test('person-to-person, own account and event rows never reach it', () async {
    ai.unconfirmed['zawya'] = 'sys:dining';
    for (final i in [
      inp('ZAWYA', kind: PartyKind.person, value: 'x'),
      inp('ZAWYA', kind: PartyKind.ipa, value: 'x'),
      inp('ZAWYA', kind: PartyKind.ownAccount, value: 'x'),
    ]) {
      expect((await cat.categorize(i)).source, isNot(CategorySource.ai));
    }
    final c = cleanMerchant('ZAWYA');
    final event = await cat.categorize(
      CategorizeInput(
        merchantNorm: c.key,
        merchantText: foldKey(c.cleaned),
        eventCategoryId: 'sys:cash',
      ),
    );
    expect(event.tier, CategorizeTier.event);
    expect(ai.asked, isEmpty);
  });

  test('no port: the tier is skipped', () async {
    final w = buildWorld();
    final plain = Categorizer(w.ports);
    expect((await plain.categorize(inp('ZAWYA'))).needsClassification, isTrue);
  });
}
