// T-080: providers behind S-13.

import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/app_database_providers.dart';
import '../../../../core/db/daos/accounts_dao.dart';
import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/settings/settings_keys.dart';
import '../../../../core/settings/settings_providers.dart';
import '../../../accounts/data/accounts_providers.dart';
import '../../../categorization/application/contributions.dart'
    show contributionQueueProvider;
import '../../application/transaction_editor.dart';
import '../../data/transactions_providers.dart';
import '../list/txn_list_providers.dart';

final transactionEditorProvider = FutureProvider<TxnEditorPort>((ref) async {
  return TransactionEditor(
    await ref.watch(transactionRepositoryProvider.future),
    await ref.watch(transferPairingUseCaseProvider.future),
    await ref.watch(refundMatchingProvider.future),
    // FU-141: an unknown merchant the user categorizes is offered as a
    // contribution (queued only with the opt-in on; filtered on device).
    onCategorized: (id) async {
      final queue = await ref.read(contributionQueueProvider.future);
      await queue.offerForTransaction(id);
    },
  );
}, name: 'transactionEditorProvider');

/// The id of the default Cash account (FR-ACC-03). On a fresh install no
/// account exists yet, so the first manual or voice entry creates Cash (in
/// the primary currency, named in the app's language); without it S-13 had
/// no account and could never save (FIX-device-flows). Null only when the
/// account cannot be written.
final defaultCashAccountIdProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final existing = await AccountsDao(db).defaultCash();
  if (existing != null) return existing.id;
  try {
    final repo = await ref.read(accountsRepositoryProvider.future);
    // Read directly: a setting stream nobody listens to never yields here.
    final settings = await ref.read(settingsRepositoryProvider.future);
    final cash = await repo.ensureDefaultCash(
      currency: await settings.get(Settings.primaryCurrency),
      label: _l10n(await settings.get(Settings.language)).commonAccountTypeCash,
    );
    // The editor's account list was read before Cash existed.
    ref.invalidate(txnLookupsProvider);
    return cash.id;
  } on Object {
    return null;
  }
}, name: 'defaultCashAccountIdProvider');

AppLocalizations _l10n(LanguagePref pref) {
  final chosen = switch (pref) {
    LanguagePref.ar => const Locale('ar'),
    LanguagePref.en => const Locale('en'),
    LanguagePref.system => null,
  };
  final device = PlatformDispatcher.instance.locale;
  for (final l in [?chosen, device]) {
    if (AppLocalizations.delegate.isSupported(Locale(l.languageCode))) {
      return lookupAppLocalizations(Locale(l.languageCode));
    }
  }
  return lookupAppLocalizations(const Locale('ar'));
}
