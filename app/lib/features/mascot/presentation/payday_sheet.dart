// T-294: the payday celebration sheet (mockup B). Bottom sheet over Home with
// the Rive bird in the payday moment, falling coins, the amount in its own
// currency, an optional per-day line and two buttons. Coins and haptic beats
// share one timeline (`ZHaptics.timelineMs`). Reduce motion: still bird, no
// coins, one light tick. The bird and coins ignore pointers and never cover a
// button.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_haptics.dart';
import '../../../core/ui/z_sheet.dart';
import '../../budget/application/budget_providers.dart'
    show currentCycleOverviewProvider;
import '../../home/presentation/home_format.dart';
import '../application/payday_celebration.dart';
import 'zaghlol_avatar.dart';

final Currency _egp = Currency.of('EGP');

/// Length of the coin fall (08-mascot-motion: payday 1.6 s).
const Duration kPaydayCoinsDuration = Duration(milliseconds: 1600);

/// Opens the sheet; [openBudget] runs after it closes from "Plan the month".
Future<void> showPaydaySheet(
  BuildContext context,
  PaydayCelebration salary, {
  VoidCallback? openBudget,
}) async {
  final plan = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: const AnimationStyle(
      duration: ZMotion.sheet,
      curve: ZMotion.curve,
    ),
    builder: (_) => PaydaySheet(salary: salary),
  );
  if (plan == true) openBudget?.call();
}

class PaydaySheet extends ConsumerStatefulWidget {
  const PaydaySheet({super.key, required this.salary});

  final PaydayCelebration salary;

  @override
  ConsumerState<PaydaySheet> createState() => _PaydaySheetState();
}

class _PaydaySheetState extends ConsumerState<PaydaySheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _coins = AnimationController(
    vsync: this,
    duration: kPaydayCoinsDuration,
  );
  bool _started = false;

  bool get _reduce =>
      ref.read(reduceMotionProvider) || MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_reduce) {
      ZHaptics.light();
    } else {
      ZHaptics.play(ZHapticPattern.payday);
      _coins.forward();
    }
  }

  @override
  void dispose() {
    _coins.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final format = HomeFormat.of(context, ref);
    final amount = l.paydaySheetAmount(format.moneyExact(widget.salary.amount));
    final perDay = ref
        .watch(currentCycleOverviewProvider)
        .value
        ?.byCurrency[_egp]
        ?.safeToSpend;
    final showPerDay =
        widget.salary.amount.currency == _egp &&
        perDay != null &&
        perDay.minor > 0;
    final reduce = _reduce;
    return ZSheetBody(
      title: l.paydaySheetTitle,
      centerTitle: true,
      actions: Row(
        children: [
          Expanded(
            child: ZButton(
              key: const ValueKey('payday-plan'),
              label: l.paydaySheetPlan,
              expand: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ),
          const SizedBox(width: ZSpacing.md),
          Expanded(
            child: ZButton(
              key: const ValueKey('payday-done'),
              label: l.paydaySheetDone,
              variant: ZButtonVariant.secondary,
              expand: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 150,
            child: Stack(
              alignment: AlignmentDirectional.bottomCenter,
              children: [
                const ZaghlolAvatar(moment: ZaghlolMoment.payday, size: 132),
                if (!reduce)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: AnimatedBuilder(
                          animation: _coins,
                          builder: (_, _) => CustomPaint(
                            key: const ValueKey('payday-coins'),
                            painter: _CoinsPainter(
                              t: _coins.value,
                              beats: ZHaptics.timelineMs(ZHapticPattern.payday),
                              fill: c.accent,
                              edge: c.accentDark,
                              rtl:
                                  Directionality.of(context) ==
                                  TextDirection.rtl,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: ZSpacing.md),
          Semantics(
            liveRegion: true,
            label: l.paydaySheetA11y(amount),
            excludeSemantics: true,
            child: Text(
              amount,
              key: const ValueKey('payday-amount'),
              textAlign: TextAlign.center,
              style: ZType.title.copyWith(color: c.text),
            ),
          ),
          if (showPerDay) ...[
            const SizedBox(height: ZSpacing.sm),
            Text(
              l.paydaySheetPerDay(format.money(perDay)),
              key: const ValueKey('payday-per-day'),
              textAlign: TextAlign.center,
              style: ZType.body.copyWith(color: c.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Coins drop from the top; coin i starts at the i-th haptic beat and falls
/// for the rest of the timeline. Horizontal slots are fixed (no randomness),
/// mirrored in RTL.
class _CoinsPainter extends CustomPainter {
  _CoinsPainter({
    required this.t,
    required this.beats,
    required this.fill,
    required this.edge,
    required this.rtl,
  });

  final double t;
  final List<int> beats;
  final Color fill;
  final Color edge;
  final bool rtl;

  static const _slots = [0.18, 0.78, 0.34, 0.64, 0.5];
  static const _radius = 9.0;
  static const _fallMs = 700.0;

  @override
  void paint(Canvas canvas, Size size) {
    final nowMs = t * kPaydayCoinsDuration.inMilliseconds;
    for (var i = 0; i < beats.length; i++) {
      final p = (nowMs - beats[i]) / _fallMs;
      if (p < 0 || p > 1) continue;
      final slot = _slots[i % _slots.length];
      final x = (rtl ? 1 - slot : slot) * size.width;
      final y = -_radius + Curves.easeIn.transform(p) * (size.height);
      final opacity = p > 0.8 ? (1 - p) / 0.2 : 1.0;
      final center = Offset(x, y);
      canvas.drawCircle(
        center,
        _radius,
        Paint()..color = fill.withValues(alpha: opacity),
      );
      canvas.drawCircle(
        center,
        _radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = edge.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_CoinsPainter old) => old.t != t;
}
