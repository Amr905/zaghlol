// SMS-device: the debug-only "SMS diagnostics" screen (Settings, About; dev
// flavours only). English only on purpose: it is a developer tool, never
// shown in staging or production (`smsDiagnosticsEnabledProvider`). Counts
// and sender names only; no message text is read or shown here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'debug_sms_diagnostics.dart';

const String kDiagTitle = 'SMS diagnostics';
const String kDiagRowSubtitle = 'Counts per stage and sender (debug builds)';
const String kDiagRefresh = 'Refresh';
const String kDiagReset = 'Reset counts';
const String kDiagEmpty = 'Nothing counted yet';
const String kDiagNote =
    'received -> Guard kept / dropped (reason) -> spooled -> stored -> saved / '
    'review. inbox_* is the historical scan. Counts only, never message text.';

/// The status line (a plain function: not UI scope for the string lint).
/// One unread-reason row (T-244): reason code and count, no message text.
String unreadLine(String reason, int count) => 'unread:$reason: $count';

/// One shape-signature row (T-244): text-free signature and count.
String shapeLine(String signature, int count) => 'shape x$count: $signature';

String guardLine(SmsDiagSnapshot s) =>
    'Guard: ${s.guardMode} / user part: ${s.userState} / '
    'spooled waiting: ${s.pending}';

final smsDiagnosticsProvider = FutureProvider.autoDispose<SmsDiagSnapshot>((
  ref,
) async {
  final source = await ref.watch(smsDiagnosticsSourceProvider.future);
  return source.read();
}, name: 'smsDiagnosticsProvider');

class DebugSmsDiagnosticsScreen extends ConsumerWidget {
  const DebugSmsDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(smsDiagnosticsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(kDiagTitle),
        actions: [
          IconButton(
            key: const Key('sms-diag-refresh'),
            tooltip: kDiagRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(smsDiagnosticsProvider),
          ),
          IconButton(
            key: const Key('sms-diag-reset'),
            tooltip: kDiagReset,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final source = await ref.read(
                smsDiagnosticsSourceProvider.future,
              );
              await source.reset();
              ref.invalidate(smsDiagnosticsProvider);
            },
          ),
        ],
      ),
      body: snap.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${e.runtimeType}')),
        data: (s) => _Body(snapshot: s),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.snapshot});

  final SmsDiagSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final names = snapshot.senders.keys.toList()..sort();
    final theme = Theme.of(context).textTheme;
    return ListView(
      key: const Key('sms-diag-list'),
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        Text(
          guardLine(snapshot),
          key: const Key('sms-diag-guard'),
          style: theme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(kDiagNote, style: theme.bodySmall),
        const SizedBox(height: 12),
        if (names.isEmpty) const Text(kDiagEmpty, key: Key('sms-diag-empty')),
        for (final name in names) ...[
          Text(
            name,
            key: Key('sms-diag-sender-$name'),
            style: theme.titleMedium,
          ),
          for (final e
              in (snapshot.senders[name]!.entries.toList()
                ..sort((a, b) => a.key.compareTo(b.key))))
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 12),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  '${e.key}: ${e.value}',
                  key: Key('sms-diag-$name-${e.key}'),
                ),
              ),
            ),
          for (final e
              in (snapshot.unreadReasons[name]?.entries.toList() ??
                  const <MapEntry<String, int>>[]))
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 12),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  unreadLine(e.key, e.value),
                  key: Key('sms-diag-$name-unread-${e.key}'),
                ),
              ),
            ),
          for (final e
              in (snapshot.signatures[name] ?? const <MapEntry<String, int>>[]))
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 12),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  shapeLine(e.key, e.value),
                  key: Key('sms-diag-$name-shape-${e.key}'),
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
