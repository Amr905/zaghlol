// T-104: Home contextual cards (mockup 25), rendered in the mascot banner slot
// (C-14). Payday / budget / backup suggestion (T-097), the one-time app-lock
// offer (FR-ONB-04) and the finish-setup prompt (FR-ONB-11). Nothing here
// blocks interaction; the bird ignores pointers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/theme/z_tokens.dart';
import '../../../../core/ui/z_button.dart';
import '../../../../core/ui/z_card.dart';
import '../../../mascot/presentation/zaghlol_avatar.dart';
import '../../../onboarding/application/contextual.dart';
import '../../../security/domain/app_lock_controller.dart';
import '../../application/home_cards.dart';
import '../home_format.dart';

/// ICU select key; no biometric type API yet, so the generic phone-lock copy.
const String _lockMethod = 'other';

class HomeContextualCards extends ConsumerWidget {
  const HomeContextualCards({
    super.key,
    required this.hasTransactions,
    this.openSetBudget,
    this.openBackup,
    this.openFinishSetup,
  });

  final bool hasTransactions;
  final VoidCallback? openSetBudget;
  final VoidCallback? openBackup;
  final VoidCallback? openFinishSetup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(homeCardsProvider(hasTransactions)).value;
    if (cards == null || cards.isEmpty) return const SizedBox.shrink();
    final s = cards.suggestion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ZSpacing.md),
        if (s != null)
          SuggestionCard(
            key: const ValueKey('home-card-suggestion'),
            suggestion: s,
            salary: cards.salary,
            openSetBudget: openSetBudget,
            openBackup: openBackup,
          ),
        if (cards.offerAppLock) ...[
          if (s != null) const SizedBox(height: ZSpacing.md),
          const AppLockOfferCard(key: ValueKey('home-card-app-lock')),
        ],
        if (cards.stepsLeft > 0) ...[
          if (s != null || cards.offerAppLock)
            const SizedBox(height: ZSpacing.md),
          FinishSetupCard(
            key: const ValueKey('home-card-finish-setup'),
            steps: cards.stepsLeft,
            onTap: openFinishSetup,
          ),
        ],
      ],
    );
  }
}

class SuggestionCard extends ConsumerWidget {
  const SuggestionCard({
    super.key,
    required this.suggestion,
    this.salary,
    this.openSetBudget,
    this.openBackup,
  });

  final SetupSuggestion suggestion;
  final Money? salary;
  final VoidCallback? openSetBudget;
  final VoidCallback? openBackup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final format = HomeFormat.of(context, ref);
    final actions = ref.read(homeCardActionsProvider);
    final kind = suggestion.kind;
    final day = suggestion.paydayDay;
    final String message;
    final String yes;
    final Future<void> Function() onYes;
    switch (kind) {
      case SetupSuggestionKind.payday:
        final d = day ?? 1;
        message = l.homePromptPayday(
          salary == null ? '' : format.money(salary!),
          format.count(d),
        );
        yes = l.homePromptPaydayYes(format.count(d));
        onYes = () => actions.acceptPayday(d);
      case SetupSuggestionKind.budget:
        message = l.homePromptBudget;
        yes = l.homePromptBudgetYes;
        onYes = () async {
          await actions.handle(kind);
          openSetBudget?.call();
        };
      case SetupSuggestionKind.backup:
        message = l.homePromptBackup;
        yes = l.homePromptBackupYes;
        onYes = () async {
          await actions.handle(kind);
          openBackup?.call();
        };
    }
    return ZCard(
      color: c.warningBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: c.text),
                ),
              ),
              const SizedBox(width: ZSpacing.sm),
              const ExcludeSemantics(
                child: ZaghlolAvatar(moment: ZaghlolMoment.detective, size: 64),
              ),
            ],
          ),
          const SizedBox(height: ZSpacing.md),
          Wrap(
            spacing: ZSpacing.sm,
            runSpacing: ZSpacing.sm,
            children: [
              ZButton(
                key: const ValueKey('suggestion-yes'),
                label: yes,
                onPressed: onYes,
              ),
              ZButton(
                key: const ValueKey('suggestion-no'),
                label: l.commonActionNo,
                variant: ZButtonVariant.secondary,
                onPressed: () => actions.handle(kind),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AppLockOfferCard extends ConsumerStatefulWidget {
  const AppLockOfferCard({super.key});

  @override
  ConsumerState<AppLockOfferCard> createState() => _AppLockOfferCardState();
}

class _AppLockOfferCardState extends ConsumerState<AppLockOfferCard> {
  bool _busy = false;
  String? _error;

  Future<void> _toggle(bool on) async {
    if (!on || _busy) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await ref
        .read(homeCardActionsProvider)
        .enableAppLock(l.appLockReason);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = switch (r) {
        EnableLockResult.notSecure => l.appLockUnavailable,
        EnableLockResult.failed => l.appLockFailed,
        _ => null,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final t = Theme.of(context).textTheme;
    final title = l.homePromptAppLockTitle(_lockMethod);
    return ZCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: ZSpacing.minTarget,
                  child: Icon(Icons.lock_outline, color: c.onPrimaryContainer),
                ),
              ),
              const SizedBox(width: ZSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleMedium?.copyWith(color: c.text)),
                    Text(
                      l.homePromptAppLockSub,
                      style: t.bodyMedium?.copyWith(color: c.textMuted),
                    ),
                  ],
                ),
              ),
              Semantics(
                label: title,
                child: Switch(
                  key: const ValueKey('app-lock-switch'),
                  value: false,
                  onChanged: _busy ? null : _toggle,
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
              child: Text(
                _error!,
                key: const ValueKey('app-lock-error'),
                style: t.bodyMedium?.copyWith(color: c.warningText),
              ),
            ),
        ],
      ),
    );
  }
}

class FinishSetupCard extends ConsumerWidget {
  const FinishSetupCard({super.key, required this.steps, this.onTap});

  final int steps;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final format = HomeFormat.of(context, ref);
    final t = Theme.of(context).textTheme;
    final sub = l.homePromptFinishSetupSteps(steps, format.count(steps));
    return Semantics(
      button: true,
      label: '${l.homePromptFinishSetup}, $sub',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
        child: ZCard(
          color: c.warningBg,
          onTap: onTap,
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: c.warningText),
              const SizedBox(width: ZSpacing.md),
              Expanded(
                child: Text(
                  '${l.homePromptFinishSetup} · $sub',
                  style: t.titleSmall?.copyWith(color: c.warningText),
                ),
              ),
              Icon(Icons.chevron_right, color: c.warningText),
            ],
          ),
        ),
      ),
    );
  }
}
