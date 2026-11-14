// T-117 S-73 Share studio. User-initiated export: the card is rendered in
// memory, staged in a temp file only for the share call, then deleted.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_banner.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_chip.dart';
import '../../../core/ui/z_currency_switcher.dart';
import '../../insights/presentation/charts/charts_providers.dart';
import '../application/share_providers.dart';
import '../domain/share_figures.dart';
import 'share_card.dart';

class ShareStudioScreen extends ConsumerStatefulWidget {
  const ShareStudioScreen({super.key});

  @override
  ConsumerState<ShareStudioScreen> createState() => _ShareStudioScreenState();
}

class _ShareStudioScreenState extends ConsumerState<ShareStudioScreen> {
  final _boundaryKey = GlobalKey();
  ShareTemplate? _template;
  bool _showAmounts = false; // FR-SHR-02: off for every new card.
  bool _busy = false;
  bool _failed = false;

  Future<void> _share() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final boundary =
          _boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('render');
      await ref.read(shareSheetProvider).sharePng(data.buffer.asUint8List());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final currencies = ref.watch(chartsCurrenciesProvider);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(l.shareStudioTitle),
        leading: IconButton(
          tooltip: l.shareStudioCloseA11y,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: currencies.when(
        loading: () => Center(
          child: Semantics(
            label: l.shareStudioRendering,
            child: const CircularProgressIndicator(),
          ),
        ),
        error: (_, _) => _Message(
          title: l.shareStudioRenderFailed,
          action: l.commonActionTryAgain,
          onAction: () => ref.invalidate(chartsCurrenciesProvider),
        ),
        data: (list) {
          if (list.isEmpty) return _empty(l);
          final codes = [for (final x in list) x.code];
          final picked = ref.watch(chartsCurrencyProvider);
          final code = codes.contains(picked) ? picked! : codes.first;
          return _body(l, c, codes, code);
        },
      ),
    );
  }

  Widget _empty(AppLocalizations l) =>
      _Message(title: l.shareStudioEmptyTitle, body: l.shareStudioEmptyBody);

  Widget _body(AppLocalizations l, ZColors c, List<String> codes, String code) {
    final figures = ref.watch(shareFiguresProvider(code));
    return figures.when(
      loading: () => Center(
        child: Semantics(
          label: l.shareStudioRendering,
          child: const CircularProgressIndicator(),
        ),
      ),
      error: (_, _) => _Message(
        title: l.shareStudioRenderFailed,
        action: l.commonActionTryAgain,
        onAction: () => ref.invalidate(shareFiguresProvider(code)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
                child: ZCurrencySwitcher(
                  codes: codes,
                  selected: code,
                  onSelected: (v) =>
                      ref.read(chartsCurrencyProvider.notifier).select(v),
                ),
              ),
              Expanded(child: _empty(l)),
            ],
          );
        }
        final figure = list.firstWhere(
          (f) => f.template == _template,
          orElse: () => list.first,
        );
        return ListView(
          padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
          children: [
            ZCurrencySwitcher(
              codes: codes,
              selected: code,
              onSelected: (v) =>
                  ref.read(chartsCurrencyProvider.notifier).select(v),
            ),
            const SizedBox(height: ZSpacing.md),
            RepaintBoundary(
              key: _boundaryKey,
              child: ShareCard(figure: figure, showAmounts: _showAmounts),
            ),
            const SizedBox(height: ZSpacing.lg),
            Wrap(
              spacing: ZSpacing.sm,
              runSpacing: ZSpacing.sm,
              children: [
                for (final f in list)
                  ZChip(
                    label: _templateLabel(l, f.template),
                    selected: f.template == figure.template,
                    onTap: () => setState(() => _template = f.template),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsetsDirectional.zero,
              title: Text(l.shareStudioShowAmounts),
              subtitle: Text(l.shareStudioShowAmountsHint),
              value: _showAmounts,
              onChanged: (v) => setState(() => _showAmounts = v),
            ),
            ZBanner(
              message: l.shareStudioUnencrypted,
              tone: ZBannerTone.warning,
            ),
            if (_failed) ...[
              const SizedBox(height: ZSpacing.sm),
              ZBanner(
                message: l.shareStudioRenderFailed,
                tone: ZBannerTone.error,
              ),
            ],
            const SizedBox(height: ZSpacing.lg),
            ZButton(
              label: l.shareStudioShare,
              expand: true,
              loading: _busy,
              onPressed: _share,
            ),
          ],
        );
      },
    );
  }

  String _templateLabel(AppLocalizations l, ShareTemplate t) => switch (t) {
    ShareTemplate.savings => l.shareStudioTemplateSavings,
    ShareTemplate.delivery => l.shareStudioTemplateDelivery,
    ShareTemplate.budget => l.shareStudioTemplateBudget,
  };
}

class _Message extends StatelessWidget {
  const _Message({required this.title, this.body, this.action, this.onAction});
  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(ZSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: ZType.title.copyWith(color: c.text)),
            if (body != null) ...[
              const SizedBox(height: ZSpacing.sm),
              Text(body!, style: ZType.body.copyWith(color: c.textMuted)),
            ],
            if (action != null) ...[
              const SizedBox(height: ZSpacing.lg),
              ZButton(label: action!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}
