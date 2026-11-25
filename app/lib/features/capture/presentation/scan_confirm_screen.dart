// T-161: S-32 Scan a screenshot (FR-ING-I-04/08). Reads an image (or shared
// text) on the phone, shows what it found in the editor (amount, currency,
// merchant, date, account) and saves nothing until the user taps Save. The
// image and its text are never kept or logged; the OCR host deletes the file.
//
// States: choose, reading, found (the S-13 editor, prefilled, source `ocr`),
// no text read, text read but no total (T-260: manual entry prefilled), and
// "not available on this phone" (no OCR host, FR-ING-I-08).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ocr/ocr_port.dart' show OcrException, OcrFailureCode;
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/presentation/edit/transaction_edit_screen.dart';
import '../../transactions/presentation/edit/txn_form.dart' show TxnEditType;
import '../../transactions/presentation/list/txn_list_providers.dart';
import '../application/scan_providers.dart';
import '../application/scan_service.dart';
import '../domain/scan_draft.dart';

/// What S-32 should read.
sealed class ScanRequest {
  const ScanRequest();
}

/// The Scan tile: the user chooses an image.
final class ScanPick extends ScanRequest {
  const ScanPick();
}

/// An image already in the OCR host's spool (a shared screenshot).
final class ScanImagePath extends ScanRequest {
  const ScanImagePath(this.path);
  final String? path;

  @override
  String toString() => 'ScanImagePath(<redacted>)';
}

/// Shared text, parsed like a pasted message.
final class ScanSharedText extends ScanRequest {
  const ScanSharedText(this.text);
  final String text;

  @override
  String toString() => 'ScanSharedText(<redacted>)';
}

/// Opens S-32 full screen. Completes when it is closed.
Future<void> showScanScreen(
  BuildContext context, {
  ScanRequest request = const ScanPick(),
}) => Navigator.of(context, rootNavigator: true).push<void>(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => ScanConfirmScreen(request: request),
  ),
);

enum _Phase { choose, reading, found, noText, noTotal, unavailable }

class ScanConfirmScreen extends ConsumerStatefulWidget {
  const ScanConfirmScreen({super.key, this.request = const ScanPick()});

  final ScanRequest request;

  @override
  ConsumerState<ScanConfirmScreen> createState() => _ScanState();
}

class _ScanState extends ConsumerState<ScanConfirmScreen> {
  _Phase _phase = _Phase.reading;
  TxnPrefill? _prefill;
  bool _fromShare = false;
  ScanOrigin _origin = ScanOrigin.image;
  ScanNoTotal? _noTotal;

  @override
  void initState() {
    super.initState();
    _fromShare = widget.request is! ScanPick;
    unawaited(_start());
  }

  Future<void> _start() async {
    final service = ref.read(scanServiceProvider);
    switch (widget.request) {
      case ScanPick():
        _set(await service.isAvailable() ? _Phase.choose : _Phase.unavailable);
      case ScanImagePath(:final path):
        if (path == null) {
          // No OCR path for this share (Android until its host lands).
          _set(_Phase.unavailable);
        } else {
          await _apply(await service.scanImage(path));
        }
      case ScanSharedText(:final text):
        await _apply(service.scanText(text));
    }
  }

  void _set(_Phase p) {
    if (mounted) setState(() => _phase = p);
  }

  Future<void> _choose() async {
    final picker = ref.read(scanImagePickerProvider);
    if (picker == null) {
      _set(_Phase.unavailable);
      return;
    }
    final String? path;
    try {
      path = await picker();
    } on OcrException catch (e) {
      _set(
        e.code == OcrFailureCode.notAvailable
            ? _Phase.unavailable
            : _Phase.noText,
      );
      return;
    } on Object {
      _set(_Phase.noText);
      return;
    }
    if (path == null || !mounted) return;
    _set(_Phase.reading);
    await _apply(await ref.read(scanServiceProvider).scanImage(path));
  }

  Future<void> _apply(ScanOutcome outcome) async {
    switch (outcome) {
      case ScanFound(:final draft):
        final prefill = await _prefillFor(draft);
        if (!mounted) return;
        setState(() {
          _prefill = prefill;
          _origin = draft.origin;
          _phase = _Phase.found;
        });
      case ScanNoText() || ScanFailed():
        _set(_Phase.noText);
      case final ScanNoTotal n:
        if (!mounted) return;
        setState(() {
          _noTotal = n;
          _phase = _Phase.noTotal;
        });
      case ScanUnavailable():
        _set(_Phase.unavailable);
    }
  }

  Future<TxnPrefill> _prefillFor(ScanDraft d) async {
    String? accountId;
    if (d.last4 != null) {
      try {
        final lk = await ref.read(txnLookupsProvider.future);
        for (final a in lk.accounts) {
          if (a.last4 == d.last4) {
            accountId = a.id;
            break;
          }
        }
      } on Object {
        // Lookups unavailable: the editor falls back to the default account.
      }
    }
    return TxnPrefill(
      type: d.direction == TxnDirection.income
          ? TxnEditType.income
          : TxnEditType.expense,
      // ignore: no_unmasked_amount - edit field prefill, the user is editing the number
      amountText: d.amount.toCanonicalString(),
      currency: d.amount.currency,
      merchant: d.party,
      accountId: accountId,
      date: d.date,
      source: d.origin == ScanOrigin.image ? TxnSource.ocr : TxnSource.share,
      checkDuplicate: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_phase == _Phase.found && _prefill != null) {
      return TransactionEditScreen(
        prefill: _prefill,
        title: l.captureScanTitle,
        bannerText: _fromShare
            ? (_origin == ScanOrigin.image
                  ? l.captureScanFromShare
                  : l.transactionsEditFromShared)
            : l.captureScanFound,
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l.commonActionClose,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(l.captureScanTitle),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(ZSpacing.xl),
          child: _body(context, l),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l) {
    final c = ZColors.of(context);
    Widget message(IconData icon, String title, String? body) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 48, color: c.textMuted),
        const SizedBox(height: ZSpacing.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: ZType.title.copyWith(color: c.text),
        ),
        if (body != null) ...[
          const SizedBox(height: ZSpacing.sm),
          Text(
            body,
            textAlign: TextAlign.center,
            style: ZType.body.copyWith(color: c.textMuted),
          ),
        ],
      ],
    );
    switch (_phase) {
      case _Phase.reading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: ZSpacing.lg),
            Text(
              l.captureScanReading,
              style: ZType.body.copyWith(color: c.text),
            ),
            const SizedBox(height: ZSpacing.xs),
            Text(
              l.captureScanOnDevice,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
          ],
        );
      case _Phase.choose:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            message(
              Icons.photo_camera_outlined,
              l.captureScanChoose,
              l.captureScanOnDevice,
            ),
            const SizedBox(height: ZSpacing.lg),
            ZButton(
              key: const Key('scan-choose'),
              label: l.captureScanChoose,
              onPressed: _choose,
            ),
          ],
        );
      case _Phase.noText:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            message(
              Icons.search_off_rounded,
              l.captureScanNoTextTitle,
              l.captureScanNoTextBody,
            ),
            const SizedBox(height: ZSpacing.lg),
            if (widget.request is ScanPick)
              ZButton(
                key: const Key('scan-choose-another'),
                label: l.captureScanChooseAnother,
                variant: ZButtonVariant.secondary,
                onPressed: _choose,
              ),
            ZButton(
              key: const Key('scan-type'),
              label: l.homeQuickAddType,
              variant: ZButtonVariant.text,
              onPressed: _typeInstead,
            ),
          ],
        );
      case _Phase.noTotal:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            message(
              Icons.receipt_long_outlined,
              l.captureScanNoTotalTitle,
              l.captureScanNoTotalBody,
            ),
            const SizedBox(height: ZSpacing.lg),
            ZButton(
              key: const Key('scan-enter-amount'),
              label: l.captureScanEnterAmount,
              onPressed: _enterAmount,
            ),
            if (widget.request is ScanPick)
              ZButton(
                key: const Key('scan-choose-another'),
                label: l.captureScanChooseAnother,
                variant: ZButtonVariant.text,
                onPressed: _choose,
              ),
          ],
        );
      case _Phase.unavailable:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            message(
              Icons.block_flipped,
              l.captureScanUnavailableTitle,
              l.captureScanUnavailableBody,
            ),
            const SizedBox(height: ZSpacing.lg),
            ZButton(
              key: const Key('scan-type'),
              label: l.homeQuickAddType,
              onPressed: _typeInstead,
            ),
          ],
        );
      case _Phase.found:
        return const SizedBox.shrink();
    }
  }

  /// Manual entry prefilled with the merchant and date read from the
  /// receipt. Nothing is saved until the user taps Save.
  void _enterAmount() {
    final n = _noTotal;
    final nav = Navigator.of(context);
    unawaited(
      nav.pushReplacement<void, void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => TransactionEditScreen(
            prefill: TxnPrefill(
              type: TxnEditType.expense,
              merchant: n?.merchant,
              date: n?.date,
              source: TxnSource.ocr,
            ),
          ),
        ),
      ),
    );
  }

  void _typeInstead() {
    final nav = Navigator.of(context);
    unawaited(
      nav.pushReplacement<void, void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const TransactionEditScreen(),
        ),
      ),
    );
  }
}
