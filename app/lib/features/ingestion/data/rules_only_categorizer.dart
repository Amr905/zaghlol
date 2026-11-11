// T-046: the categorize hook until T-075 (design note §8): the user's rules
// (T-074; counterparty, then merchant_norm, then catalog merchant), else
// "needs classification" (`category_source = none`). Called inside the
// ingest write transaction, so a rule the UI committed before our BEGIN is
// applied. Nothing here logs.

import '../../categorization/domain/merchant_rule.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/ingest_ports.dart';

final class RulesOnlyCategorizer implements Categorizer {
  const RulesOnlyCategorizer(this._rules);

  final RulesRepository _rules;

  @override
  Future<CategorizeResult> categorize(CategorizeInput input) async {
    if (input.merchantNorm == null && input.counterparty == null) {
      return CategorizeResult.none;
    }
    final match = await _rules.match(
      counterparty: input.counterparty,
      merchantNorm: input.merchantNorm,
    );
    if (match == null) return CategorizeResult.none;
    return CategorizeResult(
      categoryId: match.categoryId,
      source: CategorySource.userRule,
    );
  }
}
