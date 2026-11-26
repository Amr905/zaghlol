import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The bottom bar's laid-out height including the bottom inset, or null while
/// no bar is shown (T-298, FU-402). The saved toast reads it so it clears the
/// bar at any text scale.
class ShellBarHeightNotifier extends Notifier<double?> {
  @override
  double? build() => null;

  void report(double? value) {
    if (ref.mounted && state != value) state = value;
  }
}

final shellBarHeightProvider =
    NotifierProvider<ShellBarHeightNotifier, double?>(
      ShellBarHeightNotifier.new,
    );

/// Wraps the bar and reports its size after each layout. Without a
/// ProviderScope above it (some widget tests) it reports nothing.
class ShellBarHeightReporter extends StatefulWidget {
  const ShellBarHeightReporter({super.key, required this.child});
  final Widget child;

  @override
  State<ShellBarHeightReporter> createState() => _ReporterState();
}

class _ReporterState extends State<ShellBarHeightReporter> {
  ShellBarHeightNotifier? _notifier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _notifier = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(shellBarHeightProvider.notifier);
    } on StateError {
      _notifier = null;
    }
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) _notifier?.report(box.size.height);
  }

  @override
  void dispose() {
    final n = _notifier;
    Future.microtask(() => n?.report(null));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return widget.child;
  }
}
