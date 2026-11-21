import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/theme/app_theme.dart';
import 'package:zaghlol/core/theme/z_tokens.dart';
import 'package:zaghlol/core/ui/z_card.dart';
import 'package:zaghlol/features/insights/presentation/charts/chart_palette.dart';

Widget _host(ThemeData t) => MaterialApp(
  theme: t,
  home: Scaffold(
    body: Column(
      children: [
        const SizedBox(width: 200, child: ZProgressBar(value: 0.5)),
        Switch(value: true, onChanged: (_) {}),
        const LinearProgressIndicator(value: 0.5),
      ],
    ),
  ),
);

void main() {
  testWidgets('dark: progress, switch, chart series use brandMint', (t) async {
    await t.pumpWidget(_host(ZaghlolTheme.dark));
    final theme = ZaghlolTheme.dark;
    expect(theme.progressIndicatorTheme.color, ZColors.dark.brandMint);
    expect(
      theme.switchTheme.trackColor!.resolve({WidgetState.selected}),
      ZColors.dark.brandMint,
    );
    expect(ZChartColors.incomeOf(ZColors.dark), ZColors.dark.brandMint);
    expect(ZChartColors.rampOf(ZColors.dark).first, ZColors.dark.brandMint);
    final bar = t.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.color, isNull); // resolved from the theme
    final deco = t
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(ZProgressBar),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .expand((d) => d.gradient?.colors ?? const <Color>[]);
    expect(deco, contains(ZColors.dark.brandMint));
  });

  testWidgets('light unchanged', (t) async {
    final theme = ZaghlolTheme.light;
    expect(theme.progressIndicatorTheme.color, ZColors.light.primary);
    expect(ZChartColors.incomeOf(ZColors.light), ZChartColors.income);
    expect(ZChartColors.rampOf(ZColors.light), ZChartColors.ramp);
  });
}
