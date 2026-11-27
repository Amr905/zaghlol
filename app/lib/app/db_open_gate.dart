// FREEZE-FIX: the startup gate's failure screen (error-handling §1). Until
// now nothing mapped a failed open to a screen: a failed migration left the
// app on a blank cover (the lock gate waiting on settings that can never
// load) with nothing on screen or in the console. This shows the failure
// with "Try again" (`ref.invalidate(appDatabaseProvider)`), before the lock
// gate: it holds no financial data.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/app_database_opener.dart';
import '../core/db/app_database_providers.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/z_tokens.dart';
import 'db_open_debug.dart';

class DbOpenGate extends ConsumerWidget {
  const DbOpenGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(appDatabaseProvider, (_, next) {
      final e = next.error;
      if (e is DbOpenFailure) dbOpenProbe(e);
    });
    final open = ref.watch(appDatabaseProvider);
    final error = open.hasError && !open.isLoading ? open.error : null;
    final failed = error is DbOpenFailure;
    // The child stays mounted (hidden) so its providers are not torn down
    // mid-load; a retry that opens brings it back as it was.
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: failed,
          child: TickerMode(enabled: !failed, child: child),
        ),
        if (error is DbOpenFailure)
          Positioned.fill(
            child: DbOpenFailedScreen(
              state: dbGateStateFor(error.failure),
              onRetry: () => ref.invalidate(appDatabaseProvider),
            ),
          ),
      ],
    );
  }
}

class DbOpenFailedScreen extends StatelessWidget {
  const DbOpenFailedScreen({
    super.key,
    required this.state,
    required this.onRetry,
  });

  final DbGateState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = ZColors.of(context);
    final update = state == DbGateState.updateFailed;
    return ColoredBox(
      color: colors.bg,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  update
                      ? l10n.errorsStorageMigrationTitle
                      : l10n.errorsStorageOpenTitle,
                  key: const ValueKey('db-open-failed-title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  update
                      ? l10n.errorsStorageMigrationBody
                      : l10n.errorsStorageIo,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const ValueKey('db-open-failed-retry'),
                  onPressed: onRetry,
                  child: Text(l10n.commonActionTryAgain),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
