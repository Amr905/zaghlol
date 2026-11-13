// T-023: locale date formats. Stored times are UTC; they are shown in the
// device's local zone, with digits per [DigitsMode].

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'digits_mode.dart';

/// Loads intl's date symbols for the app's languages; call once at startup
/// (tests call it too).
Future<void> initDateFormatting() async {
  await initializeDateFormatting('ar');
  await initializeDateFormatting('en');
}

abstract final class ZDateFormat {
  static String _fmt(DateFormat f, DateTime when, DigitsMode digits) {
    final raw = f.format(when.toLocal());
    // intl's `ar` emits Arabic-Indic digits; normalize then re-render.
    final ascii = raw.replaceAllMapped(
      RegExp('[٠-٩]'),
      (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0x0660 + 0x30),
    );
    return digits.render(ascii);
  }

  /// `13 Nov 2026` / `١٣ نوفمبر ٢٠٢٦`.
  static String date(DateTime when, String languageCode, DigitsMode digits) =>
      _fmt(DateFormat.yMMMd(languageCode), when, digits);

  /// `Nov 2026`.
  static String monthYear(
    DateTime when,
    String languageCode,
    DigitsMode digits,
  ) => _fmt(DateFormat.yMMM(languageCode), when, digits);

  static String time(DateTime when, String languageCode, DigitsMode digits) =>
      _fmt(DateFormat.jm(languageCode), when, digits);
}
