// FU-224: which Captain Zaghlol message Home shows in the mascot slot (C-14).
// Picks from figures the app already computes, one currency at a time: no
// amount is ever summed across currencies. Pure picker plus one provider.
// Nothing here logs.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../budget/application/budget_providers.dart';
import 'card_filter.dart';
import 'home_read_model.dart';

sealed class HomeMascotMessage {
  const HomeMascotMessage();
}

/// `homeMascotProudSavedMore`: [amount] more saved than last cycle.
final class MascotSavedMore extends HomeMascotMessage {
  const MascotSavedMore(this.amount);
  final Money amount;
}

/// `homeMascotProudOnTrack`: under the ideal spending line (BR-MAS-02).
final class MascotOnTrack extends HomeMascotMessage {
  const MascotOnTrack(this.currency);
  final Currency currency;
}

/// One currency's message, or null. "Saved" is income minus spend, and counts
/// only when it is positive and beats a previous cycle that had activity.
HomeMascotMessage? pickHomeMascot({
  required HomeCurrencyFigures figures,
  CycleTotals? previous,
}) {
  if (previous != null && previous.currency == figures.currency) {
    final hadActivity = previous.income.minor != 0 || previous.spend.minor != 0;
    final lastNet = previous.income - previous.spend;
    // T-272: "saved" stays income minus spend. An exchange moves money
    // between currencies; it is not saving, so it never triggers this.
    final net = figures.net - figures.exchangedIn + figures.exchangedOut;
    if (hadActivity && net.minor > 0 && net > lastNet) {
      return MascotSavedMore(net - lastNet);
    }
  }
  if (figures.overview.underIdealLine == true) {
    return MascotOnTrack(figures.currency);
  }
  return null;
}

/// The first currency (primary first) that has a message.
final homeMascotMessageProvider = FutureProvider<HomeMascotMessage?>((
  ref,
) async {
  final model = await ref.watch(homeModelProvider.future);
  if (model.currencies.isEmpty) return null;
  final schedule = await ref.watch(paydayScheduleProvider.future);
  final repo = await ref.watch(cycleRepositoryProvider.future);
  final filter = ref.watch(cardFilterProvider);
  final last = await repo.totals(
    schedule.cycleOn(model.cycle.start.plusDays(-1)),
    accounts: filter,
  );
  for (final f in model.currencies) {
    final m = pickHomeMascot(figures: f, previous: last[f.currency]);
    if (m != null) return m;
  }
  return null;
}, name: 'homeMascotMessageProvider');
