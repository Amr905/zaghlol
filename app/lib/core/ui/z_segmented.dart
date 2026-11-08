import 'package:flutter/material.dart';

import '../theme/z_tokens.dart';

/// One segment of a [ZSegmentedControl].
class ZSegment<T> {
  const ZSegment({required this.value, required this.label});
  final T value;
  final String label;
}

/// Segmented control: a pill track (`surfaceAlt`) with the selected segment
/// raised on `primaryContainer`. Order follows the reading direction.
class ZSegmentedControl<T> extends StatelessWidget {
  const ZSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<ZSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(ZRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(ZSpacing.xs),
          child: Row(
            children: [
              for (final s in segments)
                Expanded(
                  child: _Segment(
                    label: s.label,
                    selected: s.value == selected,
                    onTap: () => onChanged(s.value),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final shape = BorderRadius.circular(ZRadius.pill);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: ZMotion.standard,
        curve: ZMotion.curve,
        decoration: BoxDecoration(
          color: selected ? c.primaryContainer : Colors.transparent,
          borderRadius: shape,
        ),
        child: InkWell(
          borderRadius: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: ZSpacing.minTarget),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: ZSpacing.sm,
                vertical: ZSpacing.sm,
              ),
              child: Center(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: ZType.label.copyWith(
                    color: selected ? c.onPrimaryContainer : c.textMuted,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
