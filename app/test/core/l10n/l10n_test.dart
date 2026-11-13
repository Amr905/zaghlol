import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/date_format.dart';
import 'package:zaghlol/core/l10n/digits_mode.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/core/l10n/locale_providers.dart';
import 'package:zaghlol/core/l10n/money_format.dart';
import 'package:zaghlol/core/settings/settings_keys.dart';
import 'package:zaghlol/core/settings/settings_providers.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

final _fsi = String.fromCharCode(0x2068);
final _pdi = String.fromCharCode(0x2069);

String fmt(String code, int minor, String lang, DigitsMode d) =>
    MoneyFormat.format(
      Money(Currency.of(code), minor),
      languageCode: lang,
      digits: d,
    ).replaceAll(_fsi, '').replaceAll(_pdi, '');

void main() {
  group('DigitsMode.resolve (A-29)', () {
    test('auto follows the language', () {
      expect(DigitsMode.resolve(DigitsPref.auto, 'ar'), DigitsMode.arabicIndic);
      expect(DigitsMode.resolve(DigitsPref.auto, 'en'), DigitsMode.western);
    });
    test('explicit choices win', () {
      expect(DigitsMode.resolve(DigitsPref.western, 'ar'), DigitsMode.western);
      expect(
        DigitsMode.resolve(DigitsPref.arabicIndic, 'en'),
        DigitsMode.arabicIndic,
      );
    });
  });

  group('normalizeDigits', () {
    test('Arabic-Indic, Persian, separators, marks', () {
      expect(normalizeDigits('١٢٣٫٥٠'), '123.50');
      expect(normalizeDigits('۱۲۳'), '123');
      expect(normalizeDigits('١٬٢٣٤٫٥'), '1234.5');
      expect(normalizeDigits('‏١ ٢‎'), '12');
      expect(normalizeDigits('-٠٫٠٥'), '-0.05');
    });
    test('garbage passes through for the strict parser', () {
      expect(normalizeDigits('12a'), '12a');
    });
  });

  group('MoneyFormat', () {
    test('EGP in Arabic and English', () {
      expect(fmt('EGP', 123450, 'ar', DigitsMode.arabicIndic), '١٬٢٣٤٫٥٠ ج.م');
      expect(fmt('EGP', 123450, 'en', DigitsMode.western), 'EGP 1,234.50');
    });
    test('exponent per currency', () {
      expect(fmt('KWD', 1250, 'en', DigitsMode.western), 'KWD 1.250');
      expect(fmt('JPY', 1500, 'en', DigitsMode.western), 'JPY 1,500');
      expect(fmt('USD', 5, 'en', DigitsMode.western), 'USD 0.05');
    });
    test('zero, negative, big', () {
      expect(fmt('EGP', 0, 'en', DigitsMode.western), 'EGP 0.00');
      expect(fmt('EGP', -5, 'en', DigitsMode.western), 'EGP -0.05');
      expect(fmt('EGP', -5, 'ar', DigitsMode.arabicIndic), '-٠٫٠٥ ج.م');
      expect(
        fmt('EGP', 100000000, 'en', DigitsMode.western),
        'EGP 1,000,000.00',
      );
    });
    test('mixed language and digits', () {
      expect(fmt('EGP', 150, 'ar', DigitsMode.western), '1.50 ج.م');
      expect(fmt('EGP', 150, 'en', DigitsMode.arabicIndic), 'EGP ١٫٥٠');
    });
    test('other currency shows its code in Arabic', () {
      expect(fmt('USD', 100, 'ar', DigitsMode.arabicIndic), '١٫٠٠ USD');
    });
    test('result is bidi-isolated', () {
      final s = MoneyFormat.format(
        Money(Currency.of('EGP'), -450),
        languageCode: 'ar',
        digits: DigitsMode.arabicIndic,
      );
      expect(s.startsWith(_fsi), isTrue);
      expect(s.endsWith(_pdi), isTrue);
    });
    test('parseInput accepts Arabic digits, rejects extra decimals', () {
      final egp = Currency.of('EGP');
      expect(MoneyFormat.parseInput('١٢٫٥', egp)?.minor, 1250);
      expect(MoneyFormat.parseInput('1.234', egp), isNull);
      expect(MoneyFormat.parseInput('', egp), isNull);
    });
  });

  group('ZDateFormat', () {
    setUpAll(initDateFormatting);
    final when = DateTime.utc(2026, 11, 13, 12);
    test('digits follow the mode, not the language', () {
      final ar = ZDateFormat.date(when, 'ar', DigitsMode.arabicIndic);
      expect(ar, contains('٢٠٢٦'));
      final arWest = ZDateFormat.date(when, 'ar', DigitsMode.western);
      expect(arWest, contains('2026'));
      final en = ZDateFormat.date(when, 'en', DigitsMode.western);
      expect(en, contains('2026'));
      expect(en, contains('Nov'));
      expect(
        ZDateFormat.date(when, 'en', DigitsMode.arabicIndic),
        contains('٢٠٢٦'),
      );
    });
    test('month boundary uses the local zone', () {
      final d = DateTime.utc(2026, 12, 31, 23).toLocal();
      expect(
        ZDateFormat.monthYear(d, 'en', DigitsMode.western),
        contains(d.year.toString()),
      );
    });
  });

  group('locale providers and direction', () {
    testWidgets('switching the language flips direction without restart', (
      tester,
    ) async {
      final lang = StreamController<LanguagePref>();
      addTearDown(lang.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [languageProvider.overrideWith((ref) => lang.stream)],
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              locale: ref.watch(appLocaleProvider),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                builder: (c) => Text(
                  AppLocalizations.of(c).appName,
                  key: ValueKey(Directionality.of(c)),
                ),
              ),
            ),
          ),
        ),
      );
      lang.add(LanguagePref.ar);
      await tester.pumpAndSettle();
      expect(find.text('زغلول'), findsOneWidget);
      expect(find.byKey(const ValueKey(TextDirection.rtl)), findsOneWidget);

      lang.add(LanguagePref.en);
      await tester.pumpAndSettle();
      expect(find.text('Zaghlol'), findsOneWidget);
      expect(find.byKey(const ValueKey(TextDirection.ltr)), findsOneWidget);
    });

    test('system language gives a null locale; digits mode resolves', () {
      final c = ProviderContainer(
        overrides: [
          languageProvider.overrideWith(
            (ref) => Stream.value(LanguagePref.system),
          ),
          digitsProvider.overrideWith((ref) => Stream.value(DigitsPref.auto)),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(appLocaleProvider), isNull);
      expect(c.read(digitsModeProvider('ar')), DigitsMode.arabicIndic);
    });
  });

  test('GlobalMaterialLocalizations supports ar and en', () {
    for (final l in AppLocalizations.supportedLocales) {
      expect(GlobalMaterialLocalizations.delegate.isSupported(l), isTrue);
    }
  });
}
