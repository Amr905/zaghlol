// T-103: S-05 App lock. A full-screen cover with no financial data. It
// prompts once on its own; the button prompts again.

import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../data/device_security_providers.dart';

class LockScreen extends StatelessWidget {
  const LockScreen({
    super.key,
    required this.outcome,
    required this.busy,
    required this.onUnlock,
  });

  final AuthOutcome? outcome;
  final bool busy;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = ZColors.of(context);
    final message = switch (outcome) {
      AuthOutcome.failed => l10n.appLockFailed,
      AuthOutcome.unavailable => l10n.appLockUnavailable,
      AuthOutcome.lockedOut => l10n.appLockLockedOut,
      _ => null,
    };
    return ColoredBox(
      color: colors.bg,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.appLockTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    message,
                    key: const ValueKey('lock-message'),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const ValueKey('lock-unlock'),
                  onPressed: busy ? null : onUnlock,
                  child: Text(l10n.appLockUnlock),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
