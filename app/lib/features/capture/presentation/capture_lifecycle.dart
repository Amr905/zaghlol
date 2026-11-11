// T-047: no UI. Starts the capture module with the app and tells it about
// `AppLifecycleState.resumed` (drain, status read, share-intake poll).

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/capture_providers.dart';

class CaptureLifecycle extends ConsumerStatefulWidget {
  const CaptureLifecycle({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<CaptureLifecycle> createState() => _CaptureLifecycleState();
}

class _CaptureLifecycleState extends ConsumerState<CaptureLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    ref.read(captureCoordinatorProvider).value?.onResumed();
  }

  @override
  Widget build(BuildContext context) {
    // Creating the provider starts the coordinator once the database opens.
    ref.watch(captureCoordinatorProvider);
    return widget.child;
  }
}
