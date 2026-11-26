import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/settings/settings_providers.dart';
import '../../budget/presentation/budget_providers_ui.dart';

/// T-295: the "X left in Category" line of the Saved! toast, or null when the
/// category has no budget in [currency] (or nothing is left). Amounts stay in
/// their own currency. Never throws: the toast then just says "Saved!".
Future<String?> savedToastBudgetLine(
  ProviderContainer container, {
  required String? categoryId,
  required Currency currency,
  required String languageCode,
  required AppLocalizations l10n,
}) async {
  if (categoryId == null) return null;
  try {
    final data = await container.read(budgetScreenDataProvider.future);
    for (final cur in data.currencies) {
      if (cur.currency != currency) continue;
      for (final r in cur.rows) {
        if (r.categoryId != categoryId) continue;
        final left = r.progress.remaining;
        if (left.minor <= 0) return null;
        final amount = MoneyFormat.format(
          left,
          languageCode: languageCode,
          digits: container.read(digitsModeProvider(languageCode)),
          hidden: container.read(hideAmountsProvider),
        );
        return l10n.savedToastBudgetLeft(
          amount,
          languageCode == 'ar' ? r.nameAr : r.nameEn,
        );
      }
    }
  } on Object {
    return null;
  }
  return null;
}
