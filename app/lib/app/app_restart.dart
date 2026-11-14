// T-166: restart in first-launch state without killing the process. The
// root [AppRestartScope] builds the ProviderScope; [AppRestartScope.restart]
// first unmounts it (every provider is disposed: database, backend client,
// entitlement, flags), runs [AppRestartScope.beforeStart] (the launch check
// that resumes an unfinished "Delete everything"), then mounts a fresh one.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Restarts the app's provider graph. The root scope overrides it; the
/// default does nothing (tests, the headless engine).
final appRestartProvider = Provider<void Function()>(
  (ref) => () {},
  name: 'appRestartProvider',
);

class AppRestartScope extends StatefulWidget {
  const AppRestartScope({super.key, required this.builder, this.beforeStart});

  /// Builds the app; `restart` is the callback to hand to
  /// [appRestartProvider].
  final Widget Function(BuildContext context, void Function() restart) builder;

  /// Runs between the old scope's unmount and the new one's mount. Errors
  /// are swallowed (the launch continues, as on a cold start).
  final Future<void> Function()? beforeStart;

  @override
  State<AppRestartScope> createState() => _AppRestartScopeState();
}

class _AppRestartScopeState extends State<AppRestartScope> {
  int _generation = 0;
  bool _down = false;

  void _restart() {
    if (_down || !mounted) return;
    setState(() => _down = true);
    unawaited(_bringUp());
  }

  Future<void> _bringUp() async {
    // One frame with nothing mounted, so the old scope (and its global keys)
    // is fully gone before the new one is built.
    await WidgetsBinding.instance.endOfFrame;
    try {
      await widget.beforeStart?.call();
    } on Object {
      // As on a cold start: the app opens anyway.
    }
    if (!mounted) return;
    setState(() {
      _generation++;
      _down = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_down) return const SizedBox.shrink();
    return KeyedSubtree(
      key: ValueKey<int>(_generation),
      child: widget.builder(context, _restart),
    );
  }
}
