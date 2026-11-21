// T-024 / T-203: the app shell around the four tab branches
// (03-navigation.md section 7, 04-design-system C-02, D-77, D-78). One bar,
// identical on Android and iOS: a solid docked bar with five equal slots
// (Home, Insights, Add, Money, Zaghlol) and the Add circle raised above it.
// The first tab is on the right in Arabic; everything uses start/end.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../theme/z_tokens.dart';
import '../z_haptics.dart';

class _Destination {
  const _Destination(this.icon, this.selectedIcon);
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = <_Destination>[
  _Destination(Icons.home_outlined, Icons.home),
  _Destination(Icons.area_chart_outlined, Icons.area_chart),
  _Destination(Icons.account_balance_outlined, Icons.account_balance),
  _Destination(Icons.chat_outlined, Icons.chat),
];

List<String> _labels(AppLocalizations l10n) => [
  l10n.commonNavHome,
  l10n.commonNavInsights,
  l10n.commonNavMoney,
  l10n.commonNavZaghlol,
];

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  void _selectTab(int index) {
    // N-01: re-tapping the active tab pops it to its root.
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  void _openAdd(BuildContext context) {
    context.push(AppRoutes.add);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // N-02: on a tab root, back goes to Home first, then exits.
    final body = PopScope(
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(0);
      },
      child: shell,
    );
    return ShellScaffold(
      body: body,
      selected: shell.currentIndex,
      onSelect: _selectTab,
      onAdd: () => _openAdd(context),
      labels: _labels(l10n),
      addLabel: l10n.commonNavAddA11y,
      addCaption: l10n.commonNavAddLabel,
    );
  }
}

/// The shell frame: body plus the shared bottom bar (C-02). Public so widget
/// tests and design shots can render it without a router.
class ShellScaffold extends StatelessWidget {
  const ShellScaffold({
    super.key,
    required this.body,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
    required this.labels,
    required this.addLabel,
    this.addCaption,
    this.badges = const {},
  });

  final Widget body;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  /// The four tab labels, in logical order (Home, Insights, Money, Zaghlol).
  final List<String> labels;

  /// Screen-reader label of the Add button.
  final String addLabel;

  /// Visible caption under Add; defaults to [addLabel].
  final String? addCaption;

  /// Badge counts by tab index (max shown "9+"); empty unless S-51's flag is on.
  final Map<int, int> badges;

  @override
  Widget build(BuildContext context) {
    void select(int i) {
      ZHaptics.selection();
      onSelect(i);
    }

    void add() {
      ZHaptics.medium();
      onAdd();
    }

    final c = ZColors.of(context);
    final mq = MediaQuery.of(context);
    // The bar hides while the keyboard is open.
    final keyboardOpen = mq.viewInsets.bottom > 0;
    final barVisible = !keyboardOpen;
    final content = barVisible
        ? MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: body,
          )
        : body;
    return Scaffold(
      body: CustomMultiChildLayout(
        delegate: _ShellLayout(barVisible: barVisible),
        children: [
          LayoutId(id: _ShellSlot.body, child: content),
          if (barVisible)
            LayoutId(
              id: _ShellSlot.bar,
              child: ZBottomBar(
                labels: labels,
                addCaption: addCaption ?? addLabel,
                selected: selected,
                onSelect: select,
                onAdd: add,
                badges: badges,
              ),
            ),
          if (barVisible)
            LayoutId(
              id: _ShellSlot.add,
              child: _RingedAdd(
                label: addLabel,
                ringColor: c.surface,
                onTap: add,
              ),
            ),
        ],
      ),
    );
  }
}

enum _ShellSlot { body, bar, add }

/// Body above the bar (nothing scrolls under it); the Add circle is centred
/// on the bar and raised [ZSpacing.addRaise] above its top edge.
class _ShellLayout extends MultiChildLayoutDelegate {
  _ShellLayout({required this.barVisible});
  final bool barVisible;

  @override
  void performLayout(Size size) {
    var barHeight = 0.0;
    if (hasChild(_ShellSlot.bar)) {
      final bar = layoutChild(
        _ShellSlot.bar,
        BoxConstraints.tightFor(width: size.width),
      );
      barHeight = bar.height;
      positionChild(_ShellSlot.bar, Offset(0, size.height - barHeight));
    }
    layoutChild(
      _ShellSlot.body,
      BoxConstraints.tight(Size(size.width, size.height - barHeight)),
    );
    positionChild(_ShellSlot.body, Offset.zero);
    if (hasChild(_ShellSlot.add)) {
      final add = layoutChild(_ShellSlot.add, const BoxConstraints());
      positionChild(
        _ShellSlot.add,
        Offset(
          (size.width - add.width) / 2,
          size.height - barHeight - ZSpacing.addRaise,
        ),
      );
    }
  }

  @override
  bool shouldRelayout(_ShellLayout old) => old.barVisible != barVisible;
}

class _RingedAdd extends StatelessWidget {
  const _RingedAdd({
    required this.label,
    required this.ringColor,
    required this.onTap,
  });

  final String label;
  final Color ringColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: ringColor, shape: BoxShape.circle),
    child: Padding(
      padding: const EdgeInsets.all(ZSpacing.addRing),
      child: ZAddButton(label: label, onTap: onTap),
    ),
  );
}

/// The apricot Add circle (C-02): 62 dp, `accent` gradient, on-accent plus.
class ZAddButton extends StatelessWidget {
  const ZAddButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    const shape = CircleBorder();
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          // No shadows or glows in dark.
          shadows: c.brightness == Brightness.dark
              ? null
              : [
                  BoxShadow(
                    color: c.accentDark.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [c.accentLight, c.accentDark],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: SizedBox(
              width: ZSpacing.fabSize,
              height: ZSpacing.fabSize,
              child: Icon(Icons.add, size: 32, color: c.onAccent, weight: 300),
            ),
          ),
        ),
      ),
    );
  }
}

/// C-02: solid docked bar. [labels] are the four tabs in logical order; the
/// Add slot sits between the second and third.
class ZBottomBar extends StatelessWidget {
  const ZBottomBar({
    super.key,
    required this.labels,
    required this.addCaption,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
    this.badges = const {},
  });

  final List<String> labels;
  final String addCaption;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final Map<int, int> badges;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final inset = MediaQuery.of(context).padding.bottom;
    Widget tab(int i) => Expanded(
      child: _BarTab(
        label: labels[i],
        destination: _destinations[i],
        selected: i == selected,
        badge: badges[i],
        onTap: () => onSelect(i),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.outline)),
        // Soft upward shadow in light only (c.shadow is clear in dark).
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.barHeight),
          // The tallest tab (wrapped labels at 1.3x) sets the bar height.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                tab(0),
                tab(1),
                Expanded(
                  child: _AddSlot(caption: addCaption, onTap: onAdd),
                ),
                tab(2),
                tab(3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddSlot extends StatelessWidget {
  const _AddSlot({required this.caption, required this.onTap});
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    // The circle itself is the raised, labelled button; this slot carries the
    // caption (and forwards taps on it) and keeps the slot width.
    return ExcludeSemantics(
      child: InkWell(
        onTap: onTap,
        child: Align(
          alignment: AlignmentDirectional.bottomCenter,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(bottom: ZSpacing.sm),
            child: Text(
              caption,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: ZType.caption.copyWith(
                color: c.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarTab extends StatelessWidget {
  const _BarTab({
    required this.label,
    required this.destination,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final _Destination destination;
  final bool selected;
  final int? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final color = selected ? c.primary : c.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              vertical: ZSpacing.sm,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: AlignmentDirectional.center,
                  children: [
                    Container(
                      width: ZSpacing.pillWidth,
                      height: ZSpacing.pillHeight,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? c.primaryContainer : null,
                        borderRadius: BorderRadius.circular(ZRadius.pill),
                      ),
                      child: Icon(
                        selected ? destination.selectedIcon : destination.icon,
                        size: 24,
                        color: color,
                      ),
                    ),
                    if (badge != null && badge! > 0)
                      PositionedDirectional(
                        top: -2,
                        end: 0,
                        child: _Badge(count: badge!),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                // Labels always shown; at 1.3x they wrap to two lines and the
                // bar grows.
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: ZType.caption.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});
  final int count;

  /// Max "9+", digits per locale.
  String _text(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return count > 9 ? l10n.commonNavBadgeMax : l10n.commonNavBadgeCount(count);
  }

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(ZRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 5),
        child: Text(
          _text(context),
          style: ZType.caption.copyWith(
            color: c.onAccent,
            fontSize: 10,
            height: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
