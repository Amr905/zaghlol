import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';

void main() {
  runApp(const ZaghlolApp());
}

/// Root widget. Placeholder until theming, routing and l10n land in later
/// tasks; it deliberately contains no user-facing strings.
class ZaghlolApp extends StatelessWidget {
  const ZaghlolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ZaghlolTheme.light,
      darkTheme: ZaghlolTheme.dark,
      home: const Scaffold(body: SizedBox.shrink()),
    );
  }
}
