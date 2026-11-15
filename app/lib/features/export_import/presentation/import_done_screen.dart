// T-158 / S-67 import flow, step 3 (mockup 34): what was added, with Captain
// Zaghlol celebrating. Stat tiles and "most spent on" show only when the
// source can say (the Zaghlol CSV keeps the categories it was exported
// with, so it reports a count only).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../../mascot/presentation/zaghlol_avatar.dart';
import 'import_ports.dart';
import 'import_source_screen.dart' show ImportRoundButton;

class ImportDoneScreen extends ConsumerWidget {
  const ImportDoneScreen({
    super.key,
    required this.outcome,
    this.cardName,
    this.onReview,
    this.onOpenCard,
  });

  final ImportOutcome outcome;
  final String? cardName;
  final VoidCallback? onReview;
  final VoidCallback? onOpenCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    String n(int v) => digits.render('$v');
    final o = outcome;
    final range = o.earliest != null && o.latest != null
        ? l.importFlowSummaryRange(
            ZDateFormat.monthYear(o.earliest!, lang, digits),
            ZDateFormat.monthYear(o.latest!, lang, digits),
          )
        : null;
    final card = o.cardName ?? cardName;
    final sub = [card ?? l.importFlowDoneFromFile, ?range].join(' · ');
    final review = o.needReview ?? 0;
    void close() {
      Navigator.of(context).maybePop();
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(
            ZSpacing.screen,
            ZSpacing.sm,
            ZSpacing.screen,
            ZSpacing.xl,
          ),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ImportRoundButton(
                icon: Icons.close,
                label: l.commonActionClose,
                onTap: close,
              ),
            ),
            Center(
              child: ZaghlolAvatar(
                moment: ZaghlolMoment.saved,
                size: 200,
                semanticLabel: l.importFlowDoneTitle(o.imported, n(o.imported)),
              ),
            ),
            const SizedBox(height: ZSpacing.lg),
            Semantics(
              header: true,
              child: Text(
                l.importFlowDoneTitle(o.imported, n(o.imported)),
                textAlign: TextAlign.center,
                style: ZType.headline.copyWith(color: c.text),
              ),
            ),
            const SizedBox(height: ZSpacing.xs),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: ZType.body.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: ZSpacing.lg),
            if (o.autoCategorised != null && o.needReview != null)
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      value: n(o.autoCategorised!),
                      label: l.importFlowDoneAuto,
                      color: c.primary,
                    ),
                  ),
                  const SizedBox(width: ZSpacing.md),
                  Expanded(
                    child: _Stat(
                      value: n(o.needReview!),
                      label: l.importFlowDoneReview,
                      color: c.warningText,
                    ),
                  ),
                ],
              ),
            if (o.topCategories.isNotEmpty) ...[
              const SizedBox(height: ZSpacing.lg),
              Semantics(
                header: true,
                child: Text(
                  l.importFlowDoneTop,
                  style: ZType.titleSmall.copyWith(color: c.text),
                ),
              ),
              const SizedBox(height: ZSpacing.sm),
              ZCard(
                padding: EdgeInsetsDirectional.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < o.topCategories.length; i++)
                      ZListRow(
                        title: o.topCategories[i].name,
                        leading: ZCategoryGlyph(
                          categoryId: o.topCategories[i].categoryId,
                        ),
                        trailing: Text(
                          MoneyFormat.format(
                            o.topCategories[i].total,
                            languageCode: lang,
                            digits: digits,
                            dropZeroFraction: true,
                          ),
                          style: ZType.titleSmall.copyWith(color: c.text),
                        ),
                        showDivider: i < o.topCategories.length - 1,
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: ZSpacing.lg),
            ZMascotBubble(message: l.importFlowDoneBubble),
            const SizedBox(height: ZSpacing.lg),
            if (review > 0 && onReview != null) ...[
              ZButton(
                expand: true,
                label: l.importFlowDoneReviewButton(review, n(review)),
                onPressed: onReview,
              ),
              const SizedBox(height: ZSpacing.sm),
            ],
            if (onOpenCard != null)
              ZButton(
                expand: true,
                label: l.importFlowDoneOpenCard,
                variant: ZButtonVariant.text,
                onPressed: onOpenCard,
              )
            else
              ZButton(
                expand: true,
                label: l.commonActionDone,
                variant: review > 0 && onReview != null
                    ? ZButtonVariant.text
                    : ZButtonVariant.primary,
                onPressed: close,
              ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return ZCard(
      child: Semantics(
        container: true,
        label: '$value $label',
        excludeSemantics: true,
        child: Column(
          children: [
            Text(value, style: ZType.headline.copyWith(color: color)),
            Text(
              label,
              textAlign: TextAlign.center,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
