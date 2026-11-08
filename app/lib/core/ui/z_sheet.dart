import 'package:flutter/material.dart';

import '../theme/z_tokens.dart';

/// Shows a C-17 bottom sheet: drag handle, title, content and an optional
/// sticky action bar. Keyboard-aware; 300 ms motion.
Future<T?> showZSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  Widget? actions,
  bool fullHeight = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: const AnimationStyle(
      duration: ZMotion.sheet,
      curve: ZMotion.curve,
    ),
    builder: (ctx) =>
        ZSheetBody(
          title: title,
          actions: actions,
          fullHeight: fullHeight,
          child: builder(ctx),
        ),
  );
}

/// Sheet content, public so goldens can render it without a route.
class ZSheetBody extends StatelessWidget {
  const ZSheetBody({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.fullHeight = false,
  });

  final String title;
  final Widget child;
  final Widget? actions;
  final bool fullHeight;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final body = Column(
      mainAxisSize: fullHeight ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            ZSpacing.xl,
            ZSpacing.sm,
            ZSpacing.xl,
            ZSpacing.md,
          ),
          child: Semantics(
            header: true,
            child: Text(title, style: ZType.title.copyWith(color: c.text)),
          ),
        ),
        Flexible(
          fit: fullHeight ? FlexFit.tight : FlexFit.loose,
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: ZSpacing.xl,
            ),
            child: child,
          ),
        ),
        if (actions != null)
          Padding(
            padding: const EdgeInsetsDirectional.all(ZSpacing.lg),
            child: actions,
          ),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: body,
    );
  }
}
