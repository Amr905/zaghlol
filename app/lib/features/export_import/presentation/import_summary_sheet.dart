// T-158 / S-67 import flow, step 2 (mockup 33): what the file holds before
// anything is written. Counts only; nothing the file contains is shown
// except its name.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import 'import_ports.dart';

/// True when the user confirms the import.
Future<bool?> showImportSummarySheet(
  BuildContext context, {
  required ImportPreview preview,
  String? targetCardName,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: ZColors.of(context).surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadiusDirectional.vertical(
      top: Radius.circular(ZRadius.hero),
    ),
  ),
  sheetAnimationStyle: const AnimationStyle(
    duration: ZMotion.sheet,
    curve: ZMotion.curve,
  ),
  builder: (_) =>
      ImportSummarySheet(preview: preview, targetCardName: targetCardName),
);

class ImportSummarySheet extends ConsumerWidget {
  const ImportSummarySheet({
    super.key,
    required this.preview,
    this.targetCardName,
  });

  final ImportPreview preview;
  final String? targetCardName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    String n(int v) => digits.render('$v');
    final p = preview;
    final empty = p.found == 0;
    final nothingNew = !empty && p.newCount == 0;
    final range = p.earliest != null && p.latest != null
        ? l.importFlowSummaryRange(
            ZDateFormat.date(p.earliest!, lang, digits),
            ZDateFormat.date(p.latest!, lang, digits),
          )
        : null;
    final card = p.targetCardName ?? targetCardName;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(
          ZSpacing.lg,
          ZSpacing.sm,
          ZSpacing.lg,
          ZSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.primaryContainer,
                    ),
                    child: Icon(
                      Icons.insert_drive_file_outlined,
                      color: c.primary,
                    ),
                  ),
                ),
                const SizedBox(width: ZSpacing.md),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          style: ZType.titleSmall.copyWith(color: c.text),
                        ),
                        if (range != null)
                          Text(
                            range,
                            style: ZType.bodySmall.copyWith(color: c.textMuted),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ZSpacing.lg),
            if (empty)
              ZBanner(
                tone: ZBannerTone.warning,
                message: l.exportsImportEmptyTitle,
              )
            else ...[
              ZCard(
                padding: EdgeInsetsDirectional.zero,
                child: Column(
                  children: [
                    _Row(label: l.importFlowRowFound, value: n(p.found)),
                    if (p.duplicates > 0)
                      _Row(
                        label: l.importFlowRowDup,
                        value: l.importFlowSkipped(n(p.duplicates)),
                        muted: true,
                      ),
                    if (p.untracked > 0)
                      _Row(
                        label: l.importFlowRowUntracked,
                        value: l.importFlowSkipped(n(p.untracked)),
                        muted: true,
                      ),
                    if (p.unreadable > 0)
                      _Row(
                        label: l.importFlowRowUnreadable,
                        value: l.importFlowSkipped(n(p.unreadable)),
                        muted: true,
                      ),
                    _Row(
                      label: l.importFlowRowNew,
                      value: n(p.newCount),
                      highlight: true,
                    ),
                  ],
                ),
              ),
              if (nothingNew) ...[
                const SizedBox(height: ZSpacing.md),
                ZBanner(
                  tone: ZBannerTone.info,
                  message: l.exportsImportNothingNew,
                ),
              ],
              if (card != null) ...[
                const SizedBox(height: ZSpacing.md),
                ZCard(
                  child: Text(
                    l.importFlowTarget(card),
                    style: ZType.titleSmall.copyWith(color: c.text),
                  ),
                ),
              ],
            ],
            const SizedBox(height: ZSpacing.lg),
            ZButton(
              expand: true,
              label: l.importFlowConfirm(p.newCount, n(p.newCount)),
              onPressed: empty || nothingNew
                  ? null
                  : () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.muted = false,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool muted;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final color = highlight
        ? c.onPrimaryContainer
        : muted
        ? c.textMuted
        : c.text;
    final row = Container(
      constraints: const BoxConstraints(minHeight: ZSpacing.minTarget + 8),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: ZSpacing.lg,
        vertical: ZSpacing.sm,
      ),
      decoration: highlight
          ? BoxDecoration(
              color: c.primaryContainer,
              borderRadius: const BorderRadiusDirectional.vertical(
                bottom: Radius.circular(ZRadius.card),
              ),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: (highlight ? ZType.titleSmall : ZType.body).copyWith(
                color: color,
              ),
            ),
          ),
          const SizedBox(width: ZSpacing.md),
          Text(
            value,
            style: (highlight ? ZType.titleSmall : ZType.body).copyWith(
              color: color,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      child: highlight
          ? row
          : Column(
              children: [
                row,
                Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: ZSpacing.lg,
                  ),
                  child: Divider(height: 1, color: c.outline),
                ),
              ],
            ),
    );
  }
}
