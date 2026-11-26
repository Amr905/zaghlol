// T-279 (D-86): the per-currency view of the month. One currency only: every
// figure and feed row comes from that currency, nothing is converted or
// summed with another currency (CLAUDE.md section 2.4). No UI, no logging.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/settings/settings_keys.dart';
import '../../../core/settings/settings_providers.dart';
import '../../transactions/data/transactions_providers.dart';
import '../../transactions/domain/transaction.dart';
import 'home_read_model.dart';

/// Feed rows shown on the view.
const int currencyViewFeedLimit = 10;

final budgetOffersHandledProvider = settingProvider(
  Settings.budgetOffersHandled,
);

/// The slug that marks the budget offer of [currency] for the month starting
/// [cycleStart] as handled.
String budgetOfferSlug(Currency currency, CivilDate cycleStart) =>
    '${currency.code.toLowerCase()}_${cycleStart.epochDay}';

final class CurrencyViewModel {
  const CurrencyViewModel({
    required this.currency,
    required this.home,
    required this.figures,
    required this.feed,
    required this.offerSlug,
    required this.offerVisible,
  });

  /// Null for an unknown ISO code.
  final Currency? currency;

  /// The Home model (cycle, today, days remaining) the hero needs.
  final HomeModel? home;

  /// Null when the code is unknown or the currency has no activity and no
  /// budget this month.
  final HomeCurrencyFigures? figures;
  final List<HomeFeedItem> feed;
  final String? offerSlug;

  /// The "want a budget in this currency?" offer is due.
  final bool offerVisible;

  bool get isEmpty => figures == null;
}

bool _hasActivity(HomeCurrencyFigures f) =>
    f.moneyIn.isPositive ||
    f.spend.isPositive ||
    f.exchangedOut.isPositive ||
    f.pending.isPositive;

final currencyViewProvider = FutureProvider.autoDispose
    .family<CurrencyViewModel, String>((ref, iso) async {
      final currency = Currency.tryOf(iso.toUpperCase());
      if (currency == null) {
        return const CurrencyViewModel(
          currency: null,
          home: null,
          figures: null,
          feed: [],
          offerSlug: null,
          offerVisible: false,
        );
      }
      final home = await ref.watch(homeModelProvider.future);
      final handled =
          ref.watch(budgetOffersHandledProvider).value ?? const <String>{};
      final primary = await ref.watch(primaryCurrencyProvider.future);
      HomeCurrencyFigures? figures;
      for (final f in home.currencies) {
        if (f.currency == currency) figures = f;
      }
      if (figures == null) {
        return CurrencyViewModel(
          currency: currency,
          home: home,
          figures: null,
          feed: const [],
          offerSlug: null,
          offerVisible: false,
        );
      }
      final txns = await ref.watch(transactionRepositoryProvider.future);
      // The query window is the cycle padded by the largest UTC offset; the
      // exact day test then uses each row's stored offset, like cycle totals.
      const dayMs = 86400000;
      const padMs = 14 * 3600000;
      final rows = await txns.query(
        filter: TransactionFilter(
          currencies: {currency},
          from: DateTime.fromMillisecondsSinceEpoch(
            home.cycle.start.epochDay * dayMs - padMs,
            isUtc: true,
          ),
          to: DateTime.fromMillisecondsSinceEpoch(
            (home.cycle.end.epochDay + 1) * dayMs + padMs,
            isUtc: true,
          ),
        ),
        page: const PageRequest(limit: 500),
      );
      bool inCycle(TransactionRecord r) {
        final day = CivilDate.fromLocalMs(
          r.occurredAt.millisecondsSinceEpoch,
          r.occurredTzOffsetMin,
        ).epochDay;
        return day >= home.cycle.start.epochDay &&
            day <= home.cycle.end.epochDay;
      }

      final slug = budgetOfferSlug(currency, home.cycle.start);
      return CurrencyViewModel(
        currency: currency,
        home: home,
        figures: figures,
        feed: [
          for (final r in rows.where(inCycle).take(currencyViewFeedLimit))
            HomeFeedItem(record: r, excludedFromTotals: r.isInternal),
        ],
        offerSlug: slug,
        offerVisible:
            currency != primary &&
            figures.budget == null &&
            _hasActivity(figures) &&
            !handled.contains(slug),
      );
    }, name: 'currencyViewProvider');

/// Remembers that the offer [slug] was shown and answered (Yes or dismissed).
Future<void> markBudgetOfferHandled(WidgetRef ref, String slug) async {
  final repo = await ref.read(settingsRepositoryProvider.future);
  final now = await repo.get(Settings.budgetOffersHandled);
  // The setting holds at most 64 slugs: keep the newest months.
  final all = {...now, slug}.toList()
    ..sort((a, b) => _monthOf(a).compareTo(_monthOf(b)));
  await repo.set(
    Settings.budgetOffersHandled,
    all.skip(all.length > 40 ? all.length - 40 : 0).toSet(),
  );
}

int _monthOf(String slug) => int.tryParse(slug.split('_').last) ?? 0;
