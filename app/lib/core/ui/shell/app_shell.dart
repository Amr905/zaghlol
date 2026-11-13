// T-024: the app shell around the four tab branches (03-navigation.md section 7).
// iOS: floating glass capsule plus a detached gold Add circle at the trailing
// end. Android: Material 3 NavigationBar plus a gold FAB at bottom-end.
// The first tab is on the right in Arabic; everything uses start/end.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../routing/app_routes.dart';
import '../../theme/z_tokens.dart';

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

// Material Symbols Rounded equivalents; the Zaghlol tab uses a bird glyph
// until the mascot glyph asset exists.
const _destinations = <_Destination>[
  _Destination(Icons.home_outlined, Icons.home_rounded),
  _Destination(Icons.bar_chart_outlined, Icons.bar_chart_rounded),
  _Destination(
    Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet_rounded,
  ),
  _Destination(Icons.flutter_dash_outlined, Icons.flutter_dash_rounded),
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
    HapticFeedback.mediumImpact();
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
    if (glass) {
      return Scaffold(
        extendBody: true,
        body: body,
        bottomNavigationBar: _GlassBar(
          labels: _labels(l10n),
          addLabel: l10n.commonNavAddA11y,
          selected: shell.currentIndex,
          onSelect: _selectTab,
          onAdd: () => _openAdd(context),
        ),
      );
    }
    final c = ZColors.of(context);
    final labels = _labels(l10n);
    return Scaffold(
      body: body,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Semantics(
        button: true,
        label: l10n.commonNavAddA11y,
        excludeSemantics: true,
        child: FloatingActionButton(
          heroTag: null,
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          onPressed: () => _openAdd(context),
          child: const Icon(Icons.add_rounded),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _selectTab,
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
  static const double _addSize = 56;

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
                      color: c.surface.withValues(alpha: 0.72),
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
            Semantics(
              button: true,
              label: addLabel,
              excludeSemantics: true,
              child: Material(
                color: c.accent,
                shape: const CircleBorder(),
                elevation: 3,
                shadowColor: c.shadow,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onAdd,
                  child: SizedBox(
                    width: _addSize,
                    height: _addSize,
                    child: Icon(Icons.add_rounded, color: c.onAccent),
                  ),
                ),
              ),
            ),
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
    final color = selected ? c.onPrimaryContainer : c.textMuted;
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
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZType.caption.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
