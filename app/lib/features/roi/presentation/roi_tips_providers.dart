// T-170: state behind S-51 (Smart ROI tips). Reads the T-169 providers; no
// database access here. Everything is empty while the `smart_roi` flag is off.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/flags/feature_flags.dart';
import '../../../core/flags/flags_providers.dart';
import '../../insights/presentation/charts/charts_providers.dart';
import '../../share_cards/presentation/share_studio_screen.dart';
import '../data/roi_providers.dart';

/// Whether S-51 and its Tips segment exist at all (FR-ROI-02: hidden unless
/// the flag is on).
final roiTipsEnabledProvider = Provider<bool>(
  (ref) => ref.watch(featureFlagProvider(FeatureFlag.smartRoi)),
  name: 'roiTipsEnabledProvider',
);

/// A tip's identity for dismissals: currency and rule.
String roiTipKey(RoiSuggestion s) => '${s.currency.code}:${s.rule.name}';

/// "Not for me": tips hidden for the rest of the session. (Persisting this
/// needs a settings key; see the T-170 task notes.)
class RoiDismissed extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void dismiss(RoiSuggestion s) => state = {...state, roiTipKey(s)};

  void restore(RoiSuggestion s) => state = {...state}..remove(roiTipKey(s));
}

final roiDismissedProvider = NotifierProvider<RoiDismissed, Set<String>>(
  RoiDismissed.new,
  name: 'roiDismissedProvider',
);

/// The chosen currency code; null means the first one with activity.
class RoiCurrency extends Notifier<String?> {
  @override
  String? build() => null;
  void select(String code) => state = code;
}

final roiCurrencyProvider = NotifierProvider<RoiCurrency, String?>(
  RoiCurrency.new,
  name: 'roiCurrencyProvider',
);

/// The tips of one currency, minus the dismissed ones.
final roiVisibleTipsProvider =
    FutureProvider.family<List<RoiSuggestion>, Currency>((ref, currency) async {
      final all = await ref.watch(roiSuggestionsProvider(currency).future);
      final gone = ref.watch(roiDismissedProvider);
      return [
        for (final s in all)
          if (!gone.contains(roiTipKey(s))) s,
      ];
    }, name: 'roiVisibleTipsProvider');

/// How many tips are showing across all currencies (the badge on the Tips
/// segment). A count, never a sum of money.
final roiTipCountProvider = FutureProvider<int>((ref) async {
  if (!ref.watch(roiTipsEnabledProvider)) return 0;
  final currencies = await ref.watch(chartsCurrenciesProvider.future);
  var n = 0;
  for (final c in currencies) {
    n += (await ref.watch(roiVisibleTipsProvider(c).future)).length;
  }
  return n;
}, name: 'roiTipCountProvider');

/// Opens S-73 (the share studio) for a tip. S-73 has no ROI template, so
/// the studio opens with the user's own templates; overridable by the shell.
final roiShareOpenerProvider =
    Provider<Future<void> Function(BuildContext context, RoiSuggestion tip)>(
      (ref) =>
          (context, tip) => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => const ShareStudioScreen(),
            ),
          ),
      name: 'roiShareOpenerProvider',
    );
