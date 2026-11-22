// T-209 stub: T-211 replaces this file completely with the Trends tab.

import 'package:flutter/material.dart';

import '../../../../core/theme/z_tokens.dart';
import 'all_charts_button.dart';

class TrendsTab extends StatelessWidget {
  const TrendsTab({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsetsDirectional.fromSTEB(
      ZSpacing.screen,
      ZSpacing.sm,
      ZSpacing.screen,
      ZSpacing.fabClearance,
    ),
    children: const [AllChartsButton()],
  );
}
