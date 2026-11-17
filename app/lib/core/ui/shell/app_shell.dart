// T-024: the app shell around the four tab branches (03-navigation.md section 7).
// iOS: floating glass capsule plus a detached gold Add circle at the trailing
// end. Android: Material 3 NavigationBar plus a gold FAB at bottom-end.
// The first tab is on the right in Arabic; everything uses start/end.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../theme/z_tokens.dart';
import '../z_haptics.dart';

/// Which bar the current platform gets.
bool usesGlassBar(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.iOS || TargetPlatform.macOS => true,
  _ => false,
};

class _Destination {
  const _Destination(this.icon, this.selectedIcon);
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = <_Destination>[
  _Destination(Icons.home_outlined, Icons.home_outlined),
  _Destination(Icons.area_chart_outlined, Icons.area_chart_outlined),
  _Destination(Icons.account_balance_outlined, Icons.account_balance_outlined),
  _Destination(Icons.chat_outlined, Icons.chat_outlined),
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
    final glass = usesGlassBar(context);
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
      glass: glass,
      labels: _labels(l10n),
      addLabel: l10n.commonNavAddA11y,
    );
  }
}

/// The shell frame: body plus the platform's tab bar and Add button. Public
/// so widget tests and design shots can render it without a router.
class ShellScaffold extends StatelessWidget {
  const ShellScaffold({
    super.key,
    required this.body,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
    required this.glass,
    required this.labels,
    required this.addLabel,
  });

  final Widget body;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final bool glass;
  final List<String> labels;
  final String addLabel;

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

    if (glass) {
      return Scaffold(
        extendBody: true,
        body: body,
        bottomNavigationBar: _GlassBar(
          labels: labels,
          addLabel: addLabel,
          selected: selected,
          onSelect: select,
          onAdd: add,
        ),
      );
    }
    final c = ZColors.of(context);
    return Scaffold(
      body: body,
      // FU-246: the Add button is docked at the end of the bar, not floating
      // over the body, so it never hides content or the Ask input.
      bottomNavigationBar: ColoredBox(
        color: Color.alphaBlend(
          c.primaryContainer.withValues(alpha: 0.35),
          c.bg,
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(child: _androidBar(c, select)),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: ZSpacing.lg,
                  start: ZSpacing.sm,
                ),
                child: ZAddButton(label: addLabel, onTap: add),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _androidBar(ZColors c, ValueChanged<int> onSelect) {
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: c.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          ZType.label.copyWith(color: c.text),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? c.primary : c.text,
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: onSelect,
        destinations: [
          for (var i = 0; i < _destinations.length; i++)
            NavigationDestination(
              icon: Icon(_destinations[i].icon),
              selectedIcon: Icon(_destinations[i].selectedIcon),
              label: labels[i],
            ),
        ],
      ),
    );
  }
}

/// The apricot Add button (gradient; mint in dark): a circle on iOS, a
/// rounded square FAB on Android (mockups 03 / 20 / 21).
class ZAddButton extends StatelessWidget {
  const ZAddButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final glass = usesGlassBar(context);
    final size = glass ? 62.0 : 60.0;
    final shape = glass
        ? const CircleBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(22));
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          shadows: [
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
              width: size,
              height: size,
              child: Icon(Icons.add, size: 32, color: c.onAccent, weight: 300),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassBar extends StatelessWidget {
  const _GlassBar({
    required this.labels,
    required this.addLabel,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
  });

  final List<String> labels;
  final String addLabel;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  static const double _barHeight = 64;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          ZSpacing.lg,
          0,
          ZSpacing.lg,
          ZSpacing.sm,
        ),
        // Row start is the right edge in RTL: capsule first, Add at the end
        // (left in Arabic, right in English).
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(ZRadius.pill),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    height: _barHeight,
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: ZSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: c.surface.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(ZRadius.pill),
                      border: Border.all(color: c.outline),
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < labels.length; i++)
                          Expanded(
                            child: _GlassTab(
                              label: labels[i],
                              destination: _destinations[i],
                              selected: i == selected,
                              onTap: () => onSelect(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: ZSpacing.md),
            ZAddButton(label: addLabel, onTap: onAdd),
          ],
        ),
      ),
    );
  }
}

class _GlassTab extends StatelessWidget {
  const _GlassTab({
    required this.label,
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final color = selected ? c.primary : c.text;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(ZRadius.pill),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
          child: Container(
            margin: const EdgeInsetsDirectional.symmetric(
              vertical: ZSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: selected ? c.primaryContainer : null,
              borderRadius: BorderRadius.circular(ZRadius.pill),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 22,
                  color: color,
                ),
                // Shrinks instead of truncating at 320 dp and text scale 1.3.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: ZType.caption.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
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
