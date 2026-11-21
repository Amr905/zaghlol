// S-67 "Export & import" (mockup 32 export half): CSV or Excel export of
// the user's transactions, plus the way into the import flow.
//
// States: loading preview, preview table (Free: preview only, a Gold banner,
// the Export button opens the paywall), empty ("no transactions"), preparing,
// ready/saved, error, and Gold with the "not encrypted" notice (FR-EXP-05).
// Gold gating goes through the entitlement providers; the Free path asks
// [ExportService] for the preview and never gets file bytes.
//
// Amounts in the preview follow hide-amounts (D-67). The exported file is
// exact and user-initiated.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/l10n/money_format.dart' show kAmountMask;
import '../../../core/settings/settings_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../../../core/ui/z_hide_amounts_button.dart';
import '../../gold/application/gating.dart';
import '../../transactions/domain/transaction.dart';
import '../application/export.dart';
import 'export_ports.dart';
import 'import_source_screen.dart' show ImportRoundButton;

enum _Phase { idle, preparing, saved, failed }

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key, required this.onOpenImport});

  /// Opens the import flow (the "Import" section's row).
  final VoidCallback onOpenImport;

  @override
  ConsumerState<ExportScreen> createState() => _ExportState();
}

class _ExportState extends ConsumerState<ExportScreen> {
  ExportFormat _format = ExportFormat.csv;
  _Phase _phase = _Phase.idle;
  Future<ExportOutcome?>? _preview;

  Future<ExportOutcome?> _loadPreview() async {
    final svc = await ref.read(exportServiceProvider.future);
    // The preview is the Free path: it never builds file bytes.
    return svc.export(
      entitlement: EntitlementState.free,
      filter: const TransactionFilter(),
      format: _format,
      destination: _NoDestination(),
      warningAcknowledged: false,
    );
  }

  Future<void> _export() async {
    final gold = ref.read(entitlementStateProvider);
    if (GoldGate.exportPreviewOnly(gold)) {
      ref.read(paywallTriggerProvider)(GoldCapability.csvExport);
      return;
    }
    setState(() => _phase = _Phase.preparing);
    try {
      final svc = await ref.read(exportServiceProvider.future);
      final dest = ref.read(exportDestinationFactoryProvider)();
      // The "not encrypted" notice is on screen above the button, so the
      // tap is the acknowledgement (FR-EXP-05).
      final out = await svc.export(
        entitlement: gold,
        filter: const TransactionFilter(),
        format: _format,
        destination: dest,
        warningAcknowledged: true,
      );
      if (!mounted) return;
      final ok = out is ExportWritten;
      final backedOut = dest is SystemExportDestination && !dest.saved;
      setState(
        () => _phase = !ok
            ? _Phase.failed
            : backedOut
            ? _Phase.idle
            : _Phase.saved,
      );
    } on Object {
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final gold = ref.watch(entitlementStateProvider).isGold;
    final preview = _preview ??= _loadPreview();
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
            Row(
              children: [
                ImportRoundButton(
                  icon: Icons.chevron_left,
                  label: l.commonActionBackA11y,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
                const ZHideAmountsButton(),
              ],
            ),
            const SizedBox(height: ZSpacing.lg),
            Semantics(
              header: true,
              child: Text(
                l.exportsMainTitle,
                style: ZType.display.copyWith(color: c.text),
              ),
            ),
            const SizedBox(height: ZSpacing.lg),
            Semantics(
              header: true,
              child: Text(
                l.exportsMainExportSection,
                style: ZType.titleSmall.copyWith(color: c.text),
              ),
            ),
            const SizedBox(height: ZSpacing.sm),
            Text(
              l.exportsMainFormat,
              style: ZType.label.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: ZSpacing.xs),
            ZSegmentedControl<ExportFormat>(
              segments: [
                ZSegment(
                  value: ExportFormat.csv,
                  label: l.exportsMainFormatCsv,
                ),
                ZSegment(
                  value: ExportFormat.xlsx,
                  label: l.exportsMainFormatExcel,
                ),
              ],
              selected: _format,
              onChanged: (f) => setState(() {
                _format = f;
                _phase = _Phase.idle;
              }),
            ),
            const SizedBox(height: ZSpacing.md),
            Text(
              l.exportsMainCurrencyNote,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: ZSpacing.lg),
            if (!gold) ...[
              ZBanner(
                tone: ZBannerTone.info,
                icon: Icons.workspace_premium_outlined,
                message: l.exportsMainFreePreview,
              ),
              const SizedBox(height: ZSpacing.md),
            ] else ...[
              ZBanner(
                tone: ZBannerTone.warning,
                message: l.exportsMainUnencrypted,
              ),
              const SizedBox(height: ZSpacing.md),
            ],
            Text(
              l.exportsMainPreview,
              style: ZType.titleSmall.copyWith(color: c.text),
            ),
            const SizedBox(height: ZSpacing.sm),
            _PreviewTable(future: preview),
            const SizedBox(height: ZSpacing.lg),
            if (_phase == _Phase.failed) ...[
              ZBanner(tone: ZBannerTone.error, message: l.exportsMainFailed),
              const SizedBox(height: ZSpacing.md),
            ],
            if (_phase == _Phase.saved) ...[
              ZBanner(tone: ZBannerTone.success, message: l.exportsMainReady),
              const SizedBox(height: ZSpacing.md),
            ],
            Semantics(
              liveRegion: _phase == _Phase.preparing,
              child: ZButton(
                key: const ValueKey('exportButton'),
                expand: true,
                label: _phase == _Phase.preparing
                    ? l.exportsMainPreparing
                    : _phase == _Phase.failed
                    ? l.exportsMainSave
                    : l.exportsMainExport,
                icon: gold ? null : Icons.lock_outline,
                loading: _phase == _Phase.preparing,
                onPressed: _phase == _Phase.preparing ? null : _export,
              ),
            ),
            const SizedBox(height: ZSpacing.xl),
            Semantics(
              header: true,
              child: Text(
                l.exportsImportSection,
                style: ZType.titleSmall.copyWith(color: c.text),
              ),
            ),
            const SizedBox(height: ZSpacing.sm),
            ZCard(
              padding: EdgeInsetsDirectional.zero,
              child: ZListRow(
                key: const ValueKey('exportOpenImport'),
                title: l.importFlowTitle,
                subtitle: l.importFlowSub,
                leading: const Icon(Icons.file_download_outlined),
                showChevron: true,
                onTap: widget.onOpenImport,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The preview never writes; this backs the Free-only call.
class _NoDestination implements ExportDestination {
  @override
  Future<void> write(String suggestedName, Uint8List bytes) async {
    throw StateError('preview never writes');
  }
}

class _PreviewTable extends ConsumerWidget {
  const _PreviewTable({required this.future});
  final Future<ExportOutcome?> future;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final digits = ref.watch(digitsModeProvider(lang));
    final hidden = ref.watch(hideAmountsProvider);
    return FutureBuilder<ExportOutcome?>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Semantics(
            liveRegion: true,
            label: l.exportsMainPreparing,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        final out = snap.data;
        if (snap.hasError || out is! ExportPreview) {
          return ZBanner(tone: ZBannerTone.error, message: l.exportsMainFailed);
        }
        if (out.rows.isEmpty) {
          return ZCard(
            child: Text(
              l.exportsMainPreviewEmpty,
              style: ZType.body.copyWith(color: c.textMuted),
            ),
          );
        }
        final iDate = exportColDate;
        final iMerchant = exportColMerchant;
        final iAmount = exportColAmount;
        final iCur = exportColCurrency;
        return ZCard(
          padding: EdgeInsetsDirectional.zero,
          child: Column(
            key: const ValueKey('exportPreviewRows'),
            children: [
              for (final r in out.rows)
                Container(
                  constraints: const BoxConstraints(
                    minHeight: ZSpacing.minTarget,
                  ),
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: ZSpacing.lg,
                    vertical: ZSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          r[iMerchant].isEmpty
                              ? digits.render(r[iDate].substring(0, 10))
                              : r[iMerchant],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZType.body.copyWith(color: c.text),
                        ),
                      ),
                      const SizedBox(width: ZSpacing.md),
                      Text(
                        hidden
                            ? kAmountMask
                            : '${digits.render(r[iAmount])} ${r[iCur]}',
                        textDirection: TextDirection.ltr,
                        style: ZType.body.copyWith(color: c.text),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
