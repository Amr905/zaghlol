import 'package:flutter/material.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F7A55)),
        scaffoldBackgroundColor: const Color(0xFFF3FBF7),
      ),
      home: const Scaffold(body: SizedBox.shrink()),
    );
  }
}
