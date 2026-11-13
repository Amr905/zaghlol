// T-093: small pieces shared by the S-15 / S-16 sheets.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_components.dart';
import 'transfers_format.dart';

/// Locale-aware formatter for the current language and digit setting.
TransfersFmt transfersFmtOf(BuildContext context, WidgetRef ref) {
  final lang = Localizations.localeOf(context).languageCode;
  return TransfersFmt(lang, ref.watch(digitsModeProvider(lang)));
}

/// Loading skeleton, shown while a sheet's data is read.
class SheetSkeleton extends StatelessWidget {
  const SheetSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    Widget bar(double h) => Container(
      height: h,
      margin: const EdgeInsetsDirectional.only(bottom: ZSpacing.md),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(ZRadius.md),
      ),
    );
    return Column(children: [bar(24), bar(56), bar(56), bar(56)]);
  }
}

/// Error state: message and Try again (C-29).
class SheetError extends StatelessWidget {
  const SheetError({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      children: [
        ZBanner(message: l.commonErrorLoadFailed, tone: ZBannerTone.error),
        const SizedBox(height: ZSpacing.md),
        ZButton(
          label: l.commonActionTryAgain,
          variant: ZButtonVariant.secondary,
          onPressed: onRetry,
        ),
      ],
    );
  }
}

/// Section label.
class SheetLabel extends StatelessWidget {
  const SheetLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        top: ZSpacing.lg,
        bottom: ZSpacing.sm,
      ),
      child: Semantics(
        header: true,
        child: Text(text, style: ZType.label.copyWith(color: c.textMuted)),
      ),
    );
  }
}

/// An amount text field: numeric keypad, any digit script accepted.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.semanticsLabel,
    required this.onChanged,
    this.errorText,
    this.width = 120,
  });

  final TextEditingController controller;
  final String semanticsLabel;
  final ValueChanged<String> onChanged;
  final String? errorText;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Semantics(
        label: semanticsLabel,
        textField: true,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.end,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            isDense: false,
            errorText: errorText,
            errorMaxLines: 3,
          ),
        ),
      ),
    );
  }
}
