import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/mascot/presentation/zaghlol_avatar.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/z_tokens.dart';
import 'shell/shell_bar_height.dart';
import 'z_haptics.dart';

/// T-295 / D-87 place 1: the "Saved!" toast with Captain Zaghlol. It is the
/// normal floating snackbar (one toast system) with the bird in front. Never
/// shown for bulk actions or background ingestion; callers decide.
///
/// [title] replaces "Saved!" (voice multi-draft count).
/// [budgetLine] is the already formatted "X left in Category" text, or null.
/// [onUndo] adds the Undo action when the caller can undo the save.
/// [extraLabel]/[onExtra] is an optional second action (used instead of Undo).
void showSavedToast(
  ScaffoldMessengerState messenger,
  AppLocalizations l10n, {
  String? title,
  String? budgetLine,
  VoidCallback? onUndo,
  String? extraLabel,
  VoidCallback? onExtra,
}) {
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        key: const ValueKey('savedToast'),
        behavior: SnackBarBehavior.floating,
        margin: savedToastMargin(messenger.context),
        duration: const Duration(milliseconds: 2500),
        // A snackbar with an action stays up by default; this one must hide.
        persist: false,
        content: _SavedToastBody(
          title: title ?? l10n.savedToastTitle,
          line: budgetLine,
          // A long label lives in the body (wraps) instead of the action,
          // which overflowed at 1.3x text.
          extraLabel: onUndo == null ? extraLabel : null,
          onExtra: onUndo == null && onExtra != null
              ? () {
                  ZHaptics.light();
                  messenger.hideCurrentSnackBar();
                  onExtra();
                }
              : null,
        ),
        action: onUndo == null
            ? null
            : SnackBarAction(
                label: l10n.commonActionUndo,
                onPressed: () {
                  ZHaptics.light();
                  onUndo();
                },
              ),
      ),
    );
}

class _SavedToastBody extends ConsumerStatefulWidget {
  const _SavedToastBody({
    required this.title,
    this.line,
    this.extraLabel,
    this.onExtra,
  });

  final String title;
  final String? line;
  final String? extraLabel;
  final VoidCallback? onExtra;

  @override
  ConsumerState<_SavedToastBody> createState() => _SavedToastBodyState();
}

class _SavedToastBodyState extends ConsumerState<_SavedToastBody> {
  bool _ticked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ticked) return;
    _ticked = true;
    final reduce =
        ref.read(reduceMotionProvider) ||
        MediaQuery.disableAnimationsOf(context);
    // Reduce motion: one light tick instead of the pattern.
    if (reduce) {
      ZHaptics.light();
    } else {
      ZHaptics.play(ZHapticPattern.saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The snackbar surface is inverse; take its text colour, not the page's.
    final color = DefaultTextStyle.of(context).style.color;
    return Row(
      children: [
        const ZaghlolAvatar(moment: ZaghlolMoment.saved, size: 56),
        const SizedBox(width: ZSpacing.sm),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: ZType.title.copyWith(color: color)),
              if (widget.line != null)
                Text(widget.line!, style: ZType.caption.copyWith(color: color)),
              if (widget.extraLabel != null && widget.onExtra != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: widget.onExtra,
                    child: Text(widget.extraLabel!),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bottom margin that lifts the toast above the shell's bottom bar and the
/// raised Add circle (both are laid over the Scaffold body, not in the
/// Scaffold's own FAB/bar slots, so the snackbar cannot avoid them itself).
EdgeInsetsGeometry savedToastMargin(BuildContext context) {
  final inset = MediaQuery.paddingOf(context).bottom;
  // The messenger sits above the shell, so the bar publishes its laid-out
  // height (bottom inset included) through a provider.
  final measured = _measuredBarHeight(context);
  return EdgeInsetsDirectional.only(
    start: ZSpacing.md,
    end: ZSpacing.md,
    bottom:
        (measured ?? inset + ZSpacing.barHeight) +
        ZSpacing.addRaise +
        ZSpacing.sm,
  );
}

double? _measuredBarHeight(BuildContext context) {
  try {
    return ProviderScope.containerOf(
      context,
      listen: false,
    ).read(shellBarHeightProvider);
  } on Object {
    return null; // no ProviderScope above: use the token fallback
  }
}
