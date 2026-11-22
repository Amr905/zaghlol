// T-209 (CHARTS-V2): "All charts (12)" opens the T-189 charts screen, which
// stays as it was. Every v2 tab ends with it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/l10n/locale_providers.dart';
import '../../../../core/theme/z_tokens.dart';
import '../charts/charts_screen.dart';

class AllChartsButton extends ConsumerWidget {
  const AllChartsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final label = l.insightsChartsAllCharts(
      ref
          .watch(
            digitsModeProvider(Localizations.localeOf(context).languageCode),
          )
          .render('$kAllChartsCount'),
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: OutlinedButton(
          key: const Key('charts-all-v2'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(ZSpacing.minTarget),
            foregroundColor: c.primary,
            side: BorderSide(color: c.primary),
            shape: const StadiumBorder(),
          ),
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const AllChartsPage()),
          ),
          child: Text(
            label,
            style: ZType.titleSmall.copyWith(color: c.primary),
          ),
        ),
      ),
    );
  }
}

/// The T-189 charts screen on its own page, with its own back button.
class AllChartsPage extends StatelessWidget {
  const AllChartsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(backgroundColor: c.bg, title: Text(l.insightsTabsCharts)),
      body: const ChartsScreen(),
    );
  }
}
