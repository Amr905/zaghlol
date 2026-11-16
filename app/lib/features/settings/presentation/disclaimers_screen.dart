// About > Important notices (FU-245, NFR-LEGAL-03): coaching, estimates and
// prices, each as a summary plus the full (standard Arabic) text, and a
// pointer to the Zakah and tips screens, which carry their own disclaimers.

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import 'settings_widgets.dart';

/// The important-notices list behind About > Disclaimers (FU-245). Uses the
/// existing legal strings only.
class DisclaimersScreen extends StatelessWidget {
  const DisclaimersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    Widget block(String summary, String body) => Padding(
      padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary,
            style: ZType.body.copyWith(
              color: c.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: ZSpacing.xs),
          Text(body, style: ZType.bodySmall.copyWith(color: c.textMuted)),
        ],
      ),
    );
    Widget ref(String text) => Padding(
      padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
      child: Text(text, style: ZType.bodySmall.copyWith(color: c.textMuted)),
    );
    return SettingsScaffold(
      title: t.legalDisclaimerTitle,
      children: [
        SettingsSection(
          children: [
            block(t.legalDisclaimerCoachingSummary, t.legalDisclaimerCoaching),
            block(
              t.legalDisclaimerEstimatesSummary,
              t.legalDisclaimerEstimates,
            ),
            block(t.legalDisclaimerPricesSummary, t.legalDisclaimerPrices),
            ref(t.legalDisclaimerZakahRef),
            ref(t.legalDisclaimerRoiRef),
          ],
        ),
        Text(
          t.legalDisclaimerFooter,
          textAlign: TextAlign.center,
          style: ZType.caption.copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}
