// T-085: providers behind S-43. Institutions come from the registry the
// capture feature already loads; the capture-toggle port is wired by the
// shell (it needs the ignore-rules service and the Guard config write).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../capture/application/capture_providers.dart';
import '../../../recurring/data/recurring_repository.dart';
import '../../../transactions/data/transactions_providers.dart';
import '../../../transactions/domain/transaction.dart';

/// A bank the user can pick (mockup 29).
final class InstitutionOption {
  const InstitutionOption({
    required this.code,
    required this.nameAr,
    required this.nameEn,
    required this.defaultCurrency,
    required this.isEgypt,
  });

  final String code;
  final String nameAr;
  final String nameEn;
  final Currency defaultCurrency;
  final bool isEgypt;

  String name(String languageCode) => languageCode == 'ar' ? nameAr : nameEn;

  /// Monogram fallback while bank logos are gated (OQ-09, NFR-LEGAL-04).
  String monogram(String languageCode) {
    final n = name(languageCode).trim();
    return n.isEmpty ? '?' : String.fromCharCode(n.runes.first).toUpperCase();
  }
}

final institutionOptionsProvider = Provider<List<InstitutionOption>>((ref) {
  final registry = ref.watch(captureRegistryLoaderProvider)();
  return [
    for (final i in registry.institutions)
      InstitutionOption(
        code: i.code,
        nameAr: i.nameAr,
        nameEn: i.nameEn,
        defaultCurrency: i.defaultCurrency,
        isEgypt: i.country == 'EG',
      ),
  ];
}, name: 'institutionOptionsProvider');

/// Capture toggles chosen on a new card become ignore rules (T-078) through
/// this port. Null means the shell has not wired it: the toggles are hidden.
abstract interface class CardCapturePort {
  /// Adds an ignore rule for each channel in [offChannels] (values of
  /// `IgnoreChannel`) for this card.
  Future<void> turnOff({
    required String institutionCode,
    required String? last4,
    required Set<String> offChannels,
  });
}

final cardCapturePortProvider = Provider<CardCapturePort?>(
  (ref) => null,
  name: 'cardCapturePortProvider',
);

/// Transactions that a merge of [accountId] would move.
final accountTxnCountProvider = FutureProvider.family<int, String>((
  ref,
  accountId,
) async {
  final repo = await ref.watch(transactionRepositoryProvider.future);
  return repo.count(filter: TransactionFilter(accountIds: {accountId}));
}, name: 'accountTxnCountProvider');

/// Moves the due-date reminders after a due-day change (T-096). A failure
/// must not fail the save.
Future<void> syncCardDues(WidgetRef ref) async {
  try {
    final repo = await ref.read(recurringRepositoryProvider.future);
    await repo.syncCardDues();
  } on Object {
    // The reminders catch up on the next sync.
  }
}
