// T-153: locale-aware labels shared by S-66 and S-04.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/date_format.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_providers.dart';

/// `30 Oct 2026` in the current language and digit mode.
String backupDate(BuildContext context, WidgetRef ref, DateTime when) {
  final lang = Localizations.localeOf(context).languageCode;
  return ZDateFormat.date(when, lang, ref.watch(digitsModeProvider(lang)));
}

/// File size from bytes: KB below 1 MB, else MB (one decimal), digits per mode.
String backupSize(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
  int bytes,
) {
  final lang = Localizations.localeOf(context).languageCode;
  final digits = ref.watch(digitsModeProvider(lang));
  if (bytes < 1024 * 1024) {
    final kb = (bytes / 1024).ceil().clamp(1, 1023);
    return l10n.commonFileSizeKb(digits.render('$kb'));
  }
  final tenths = (bytes * 10 / (1024 * 1024)).round();
  final text = '${tenths ~/ 10}.${tenths % 10}';
  return l10n.commonFileSizeMb(digits.render(text));
}

String backupProviderName(AppLocalizations l10n, bool icloud) =>
    icloud ? l10n.backupRestoreOptionICloud : l10n.backupRestoreOptionDrive;
