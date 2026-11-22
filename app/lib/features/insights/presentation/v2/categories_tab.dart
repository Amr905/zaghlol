// T-209 stub: T-210 replaces this file completely with the Categories tab.

import 'package:flutter/material.dart';

import '../../../../core/theme/z_tokens.dart';
import 'all_charts_button.dart';

class CategoriesTab extends StatelessWidget {
  const CategoriesTab({super.key});

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
