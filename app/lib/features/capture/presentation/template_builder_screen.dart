// T-164: S-65 Custom message template (Gold; FR-PAR-07). Paste or pick a
// message, tap the parts and say what they are, test on the sender's
// history, save. The message stays on the phone (copy says so) and is held
// in memory only while this screen is open.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../gold/application/gating.dart';
import '../../settings/presentation/settings_widgets.dart' show localDigits;
import '../application/template_builder.dart';

const int _maxSampleField = 1000;

class TemplateBuilderScreen extends ConsumerStatefulWidget {
  const TemplateBuilderScreen({super.key});

  @override
  ConsumerState<TemplateBuilderScreen> createState() => _State();
}

class _State extends ConsumerState<TemplateBuilderScreen> {
  final _paste = TextEditingController();
  final _sender = TextEditingController();

  @override
  void dispose() {
    _paste.dispose();
    _sender.dispose();
    super.dispose();
  }

  String _tagLabel(AppLocalizations t, CustomTag tag) => switch (tag) {
    CustomTag.amount => t.templatesBuilderTagAmount,
    CustomTag.currency => t.templatesBuilderTagCurrency,
    CustomTag.merchant => t.templatesBuilderTagMerchant,
    CustomTag.last4 => t.templatesBuilderTagLast4,
    CustomTag.balance => t.templatesBuilderTagBalance,
    CustomTag.date => t.templatesBuilderTagDate,
  };

  Future<void> _pickFromReview() async {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    List<TemplateSample> items;
    try {
      items = await ref.read(templateBuilderStoreProvider).reviewSamples();
    } on Object {
      items = const [];
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<TemplateSample>(
      context: context,
      backgroundColor: c.surface,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: items.isEmpty
            ? Padding(
                padding: const EdgeInsetsDirectional.all(ZSpacing.xl),
                child: Text(
                  t.templatesBuilderEmpty,
                  style: ZType.body.copyWith(color: c.text),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final s in items)
                    ListTile(
                      title: Text(
                        s.sender,
                        style: ZType.body.copyWith(color: c.text),
                      ),
                      subtitle: Text(
                        s.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ZType.bodySmall.copyWith(color: c.textMuted),
                      ),
                      onTap: () => Navigator.of(ctx).pop(s),
                    ),
                ],
              ),
      ),
    );
    if (picked == null || !mounted) return;
    _paste.text = picked.body;
    _sender.text = picked.sender;
    await ref.read(templateBuilderProvider.notifier).useReviewSample(picked);
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final ok = await ref.read(templateBuilderProvider.notifier).save();
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t.templatesBuilderSaved)));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final gold = ref.watch(entitlementStateProvider).isGold;
    final s = ref.watch(templateBuilderProvider);
    final ctl = ref.read(templateBuilderProvider.notifier);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: c.text,
        title: Text(
          t.templatesBuilderTitle,
          style: ZType.title.copyWith(color: c.text),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
          children: [
            if (!gold) ...[
              Container(
                padding: const EdgeInsetsDirectional.all(ZSpacing.md),
                decoration: BoxDecoration(
                  color: c.accentLight,
                  borderRadius: BorderRadius.circular(ZRadius.md),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: c.onAccent),
                    const SizedBox(width: ZSpacing.sm),
                    Expanded(
                      child: Text(
                        t.templatesBuilderLockedBody,
                        style: ZType.body.copyWith(color: c.onAccent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: ZSpacing.md),
              ZButton(
                label: t.commonGoldUnlock,
                variant: ZButtonVariant.gold,
                expand: true,
                onPressed: () => ref.read(paywallTriggerProvider)(
                  GoldCapability.customSmsRegex,
                ),
              ),
              const SizedBox(height: ZSpacing.lg),
            ],
            // 1. Paste or pick.
            Text(
              t.templatesBuilderPickTitle,
              style: ZType.titleSmall.copyWith(color: c.text),
            ),
            const SizedBox(height: ZSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ZButton(
                label: t.templatesBuilderFromReview,
                variant: ZButtonVariant.secondary,
                size: ZButtonSize.small,
                onPressed: gold ? _pickFromReview : null,
              ),
            ),
            const SizedBox(height: ZSpacing.sm),
            TextField(
              controller: _paste,
              enabled: gold,
              minLines: 3,
              maxLines: 6,
              maxLength: _maxSampleField,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: t.templatesBuilderPaste,
                border: const OutlineInputBorder(),
              ),
              onChanged: ctl.setSample,
            ),
            Text(
              t.templatesBuilderPrivate,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: ZSpacing.lg),
            if (!s.hasSample)
              Text(
                t.templatesBuilderEmpty,
                style: ZType.body.copyWith(color: c.textMuted),
              )
            else ...[
              // 2. Tag the parts.
              Text(
                t.templatesBuilderTagTitle,
                style: ZType.titleSmall.copyWith(color: c.text),
              ),
              const SizedBox(height: ZSpacing.xs),
              Text(
                t.templatesBuilderTapHint,
                style: ZType.bodySmall.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: ZSpacing.sm),
              _Tokens(state: s, onTap: gold ? ctl.tapToken : null),
              const SizedBox(height: ZSpacing.md),
              Wrap(
                spacing: ZSpacing.sm,
                runSpacing: ZSpacing.sm,
                children: [
                  for (final tag in CustomTag.values)
                    FilterChip(
                      key: ValueKey('tag_${tag.group}'),
                      label: Text(_tagLabel(t, tag)),
                      selected: s.spans.containsKey(tag),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: !gold
                          ? null
                          : (_) {
                              final now = ref.read(templateBuilderProvider);
                              if (now.selection != null) {
                                ctl.assign(tag);
                              } else if (now.spans.containsKey(tag)) {
                                ctl.removeTag(tag);
                              }
                            },
                    ),
                ],
              ),
              if (s.error == TemplateSaveError.amount)
                _Error(t.templatesBuilderErrorAmount),
              const SizedBox(height: ZSpacing.md),
              Text(
                t.templatesBuilderDirection,
                style: ZType.titleSmall.copyWith(color: c.text),
              ),
              const SizedBox(height: ZSpacing.sm),
              SegmentedButton<TemplateDirection>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: TemplateDirection.expense,
                    label: Text(t.commonTxnTypeExpense),
                  ),
                  ButtonSegment(
                    value: TemplateDirection.income,
                    label: Text(t.commonTxnTypeIncome),
                  ),
                ],
                selected: {s.direction},
                onSelectionChanged: gold
                    ? (v) => ctl.setDirection(v.first)
                    : null,
              ),
              const SizedBox(height: ZSpacing.md),
              TextField(
                controller: _sender,
                enabled: gold,
                maxLength: 128,
                decoration: InputDecoration(
                  labelText: t.templatesBuilderSender,
                  helperText: t.templatesBuilderSenderHint,
                  border: const OutlineInputBorder(),
                ),
                onChanged: ctl.setSender,
              ),
              if (s.error == TemplateSaveError.sender)
                _Error(t.templatesBuilderErrorSender),
              const SizedBox(height: ZSpacing.lg),
              // 3. Test.
              Text(
                t.templatesBuilderTestTitle,
                style: ZType.titleSmall.copyWith(color: c.text),
              ),
              const SizedBox(height: ZSpacing.sm),
              _TestResult(state: s),
              if (s.error == TemplateSaveError.selfParse)
                _Error(t.templatesBuilderErrorSelfParse),
              if (s.error == TemplateSaveError.failed)
                _Error(t.commonErrorLoadFailed),
              const SizedBox(height: ZSpacing.lg),
              Semantics(
                button: true,
                label: gold
                    ? t.templatesBuilderSave
                    : '${t.templatesBuilderSave}, ${t.commonGoldBadge}',
                child: ZButton(
                  label: t.templatesBuilderSave,
                  expand: true,
                  loading: s.saving,
                  onPressed: gold ? _save : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
      child: Text(text, style: ZType.bodySmall.copyWith(color: c.dangerText)),
    );
  }
}

/// The sample as tappable words. Tagged words are tinted; the picked range
/// has an outline.
class _Tokens extends StatelessWidget {
  const _Tokens({required this.state, required this.onTap});

  final TemplateBuilderState state;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    final sel = state.selection;
    return Wrap(
      spacing: ZSpacing.xs,
      runSpacing: ZSpacing.xs,
      children: [
        for (var i = 0; i < state.tokens.length; i++)
          Builder(
            builder: (_) {
              final tok = state.tokens[i];
              final tagged = state.spans.values.any(
                (sp) => sp.start <= tok.start && tok.end <= sp.end,
              );
              final picked = sel != null && i >= sel.$1 && i <= sel.$2;
              return Semantics(
                button: true,
                selected: picked,
                child: InkWell(
                  key: ValueKey('token_$i'),
                  borderRadius: BorderRadius.circular(ZRadius.sm),
                  onTap: onTap == null ? null : () => onTap!(i),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Container(
                      alignment: AlignmentDirectional.center,
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: ZSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: tagged ? c.primaryContainer : c.surface,
                        borderRadius: BorderRadius.circular(ZRadius.sm),
                        border: Border.all(
                          color: picked ? c.primary : c.outline,
                          width: picked ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        state.sample.substring(tok.start, tok.end),
                        style: ZType.body.copyWith(
                          color: tagged ? c.onPrimaryContainer : c.text,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// "Matches N of M" and the first miss with its reason.
class _TestResult extends ConsumerWidget {
  const _TestResult({required this.state});

  final TemplateBuilderState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final r = state.report;
    if (r == null) {
      return Text(
        t.templatesBuilderTapHint,
        style: ZType.bodySmall.copyWith(color: c.textMuted),
      );
    }
    final miss = r.failures.isEmpty ? null : r.failures.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.templatesBuilderTestResult(
            localDigits(ref, context, '${r.matched}'),
            localDigits(ref, context, '${r.total}'),
          ),
          style: ZType.body.copyWith(color: c.text),
        ),
        if (miss != null) ...[
          const SizedBox(height: ZSpacing.sm),
          Text(
            t.templatesBuilderTestFailTitle,
            style: ZType.titleSmall.copyWith(color: c.text),
          ),
          Text(
            state.history[miss.$1],
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: ZType.bodySmall.copyWith(color: c.textMuted),
          ),
          Text(
            t.templatesBuilderTestFailReason(miss.\$2.name),
            style: ZType.bodySmall.copyWith(color: c.text),
          ),
        ],
      ],
    );
  }
}
