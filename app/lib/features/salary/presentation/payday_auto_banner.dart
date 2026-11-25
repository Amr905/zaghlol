// T-246 (D-81): the one banner after the payday followed the salary, with
// Undo. Shows nothing when no automatic change is waiting.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/z_banner.dart';
import '../../home/presentation/home_format.dart';
import '../application/payday_auto_service.dart';
import '../application/salary_providers.dart';

class PaydayAutoBanner extends ConsumerWidget {
  const PaydayAutoBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(paydayAutoProvider).value;
    final day = state?.autoDay;
    if (state == null || !state.bannerPending || day == null) {
      return const SizedBox.shrink();
    }
    final salary = state.salaryDay;
    final l = AppLocalizations.of(context);
    final format = HomeFormat.of(context, ref);
    Future<PaydayAutoService> service() =>
        ref.read(paydayAutoServiceProvider.future);
    return ZBanner(
      key: const ValueKey('payday-auto-banner'),
      // m-6: a 29..31 salary sets 28; the copy names the real salary day.
      message: salary != null && salary != day
          ? l.paydayAutoBannerCapped(format.count(day), format.count(salary))
          : l.paydayAutoBanner(format.count(day)),
      actionLabel: l.paydayAutoUndo,
      onAction: () async => (await service()).undo(),
      onDismiss: () async => (await service()).dismissBanner(),
      dismissSemanticsLabel: l.paydayAutoDismissA11y,
    );
  }
}
