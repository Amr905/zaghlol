// T-115: Riverpod wiring for the ≈ view. Reads the two settings
// (off by default) and the stored rates; never writes anything.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/settings/settings_providers.dart';
import '../domain/approx_view.dart';
import 'prices_providers.dart';

/// The ≈ view for [totals]. When the setting is off the result is
/// [ApproxViewOff] and the rates are not even read.
final approxViewProvider =
    FutureProvider.family<ApproxView, MultiCurrencyTotal>((ref, totals) async {
      final enabled = await ref.watch(approxViewEnabledProvider.future);
      if (!enabled) return const ApproxViewOff();
      final target = await ref.watch(approxViewTargetProvider.future);
      final repo = await ref.watch(pricesRepositoryProvider.future);
      return buildApproxView(
        enabled: true,
        totals: totals,
        target: target,
        rates: await repo.fxTable(),
        nowMs: ref.watch(pricesClockProvider)().millisecondsSinceEpoch,
      );
    }, name: 'approxViewProvider');
