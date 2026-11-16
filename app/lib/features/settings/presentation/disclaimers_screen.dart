// Explorer finding (FU-245): the About "Important notices" row had an empty
// handler. This is the list it opens (NFR-LEGAL-03): coaching, estimates and
// prices, each as a summary plus the full (standard Arabic) text, and a
// pointer to the Zakah and tips screens, which carry their own disclaimers.

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import 'settings_widgets.dart';

class DisclaimersScreen extends StatelessWidget {
  const DisclaimersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    Widget notice(String summary, String full) => Padding(
      padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(summary, style: ZType.label.copyWith(color: c.text)),
          const SizedBox(height: ZSpacing.sm),
          Text(full, style: ZType.bodySmall.copyWith(color: c.textMuted)),
        ],
      ),
    );
    return SettingsScaffold(
      title: t.legalDisclaimerTitle,
      children: [
        SettingsSection(
          children: [
            notice(t.legalDisclaimerCoachingSummary, t.legalDisclaimerCoaching),
            notice(
              t.legalDisclaimerEstimatesSummary,
              t.legalDisclaimerEstimates,
            ),
            notice(t.legalDisclaimerPricesSummary, t.legalDisclaimerPrices),
            Padding(
              padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
              child: Text(
                '${t.legalDisclaimerZakahRef}\n${t.legalDisclaimerRoiRef}',
                style: ZType.bodySmall.copyWith(color: c.textMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
