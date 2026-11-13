// T-143: no UI. Starts the entitlement service and runs the daily sync when
// the app opens and each time it returns to the foreground. The 24 h throttle
// and the back-off live in the orchestrator, so ten opens a day make at most
// one successful sync. Failures are typed outcomes; nothing is surfaced here.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../gold/application/entitlement.dart';
import '../../gold/application/gold_providers.dart';
import '../application/sync_providers.dart';

class SyncLifecycle extends ConsumerStatefulWidget {
  const SyncLifecycle({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SyncLifecycle> createState() => _SyncLifecycleState();
}

class _SyncLifecycleState extends ConsumerState<SyncLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_tick());
  }

  Future<void> _start() async {
    try {
      await ref.read(entitlementServiceProvider).start();
    } on Object {
      // Stays Free (fail closed); the next resume tries again.
    }
    await _startPurchases();
    await _tick();
  }

  /// T-145: listen to the store from app start (Play and StoreKit redeliver
  /// unfinished purchases then) and retry what the outbox holds.
  Future<void> _startPurchases() async {
    try {
      await ref.read(purchaseServiceProvider).start();
    } on Object {
      // No store (tests, a device without Play): purchases are unavailable.
    }
  }

  Future<void> _tick() async {
    try {
      await ref.read(purchaseServiceProvider).retryDue();
    } on Object {
      // Retried at the next resume or timer.
    }
    try {
      await ref.read(entitlementServiceProvider).onResume();
      final o = await ref.read(syncOrchestratorProvider.future);
      await o.run();
    } on Object {
      // Typed failures are recorded by the orchestrator; a database that is
      // not open yet simply means no sync this time.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
