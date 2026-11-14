// T-166: the "Delete everything" confirmation — EC-69 seat warning on
// Android (ar + en, RTL), none without a seat or on iOS, and cancel deletes
// nothing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/gold/application/restore.dart';
import 'package:zaghlol/features/settings/presentation/privacy_screen.dart';
import 'package:zaghlol/features/settings/presentation/settings_ports.dart';

import 'settings_harness.dart';

const _seatKey = ValueKey('privacyDeleteSeatWarning');

Finder _inDialog(String label) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

Future<AppLocalizations> _openDialog(
  WidgetTester tester,
  SettingsHarness h, {
  required String platform,
  Locale locale = const Locale('en'),
  DeleteEverythingWarning? warning,
  void Function()? onWipe,
  Future<void> Function()? wipe,
}) async {
  await tester.pumpWidget(
    h.app(
      PrivacyScreen(platform: platform),
      locale: locale,
      scale: 1.3,
      overrides: [
        deleteSeatWarningProvider.overrideWith((ref) async => warning),
        wipeEverythingProvider.overrideWithValue(
          wipe ?? () async => onWipe?.call(),
        ),
      ],
    ),
  );
  await settle(tester);
  final t = AppLocalizations.of(tester.element(find.byType(PrivacyScreen)));
  await tester.scrollUntilVisible(
    find.text(t.privacyDeleteRow),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text(t.privacyDeleteRow));
  await settle(tester);
  return t;
}

void main() {
  for (final locale in const [Locale('ar'), Locale('en')]) {
    group('EC-69 seat warning (${locale.languageCode})', () {
      testWidgets('Android, seat held, no cooldown: "counts as the move"', (
        tester,
      ) async {
        final h = SettingsHarness();
        addTearDown(h.db.close);
        final t = await _openDialog(
          tester,
          h,
          platform: 'android',
          locale: locale,
          warning: const DeleteEverythingWarning(holdsSeat: true),
        );
        expect(find.byKey(_seatKey), findsOneWidget);
        expect(find.text(t.goldSeatDeleteWarning('other', '')), findsOneWidget);
        expect(
          Directionality.of(tester.element(find.byKey(_seatKey))),
          locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('Android, seat held, cooldown: shows the date', (
        tester,
      ) async {
        final h = SettingsHarness();
        addTearDown(h.db.close);
        final next = DateTime.now().toUtc().add(const Duration(days: 12));
        await _openDialog(
          tester,
          h,
          platform: 'android',
          locale: locale,
          warning: DeleteEverythingWarning(holdsSeat: true, nextMoveAt: next),
        );
        final text = tester.widget<Text>(find.byKey(_seatKey)).data!;
        final t = AppLocalizations.of(tester.element(find.byKey(_seatKey)));
        expect(text, isNot(t.goldSeatDeleteWarning('other', '')));
        // The cooldown variant carries the (localized) date.
        expect(
          text.length,
          greaterThan(t.goldSeatDeleteWarning('cooldown', '').length),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('Android without a seat: no warning', (tester) async {
        final h = SettingsHarness();
        addTearDown(h.db.close);
        await _openDialog(
          tester,
          h,
          platform: 'android',
          locale: locale,
          warning: const DeleteEverythingWarning(holdsSeat: false),
        );
        expect(find.byKey(_seatKey), findsNothing);
      });
    });
  }

  testWidgets('iOS never shows the move warning (seat keys are kept)', (
    tester,
  ) async {
    final h = SettingsHarness();
    addTearDown(h.db.close);
    final t = await _openDialog(
      tester,
      h,
      platform: 'ios',
      warning: const DeleteEverythingWarning(holdsSeat: true),
    );
    expect(find.byKey(_seatKey), findsNothing);
    expect(find.text(t.privacyDeleteIosKeys), findsOneWidget);
  });

  testWidgets('a failed seat lookup shows no warning and still confirms', (
    tester,
  ) async {
    final h = SettingsHarness();
    addTearDown(h.db.close);
    await tester.pumpWidget(
      h.app(
        const PrivacyScreen(platform: 'android'),
        overrides: [
          deleteSeatWarningProvider.overrideWith(
            (ref) async => throw StateError('no db'),
          ),
        ],
      ),
    );
    await settle(tester);
    final t = AppLocalizations.of(tester.element(find.byType(PrivacyScreen)));
    await tester.ensureVisible(find.text(t.privacyDeleteRow));
    await tester.tap(find.text(t.privacyDeleteRow));
    await settle(tester);
    expect(find.text(t.privacyDeleteTitle), findsOneWidget);
    expect(find.byKey(_seatKey), findsNothing);
  });

  testWidgets('negative proof: Cancel at the confirm deletes nothing, even '
      'with the right word typed', (tester) async {
    final h = SettingsHarness();
    addTearDown(h.db.close);
    var wiped = 0;
    final t = await _openDialog(
      tester,
      h,
      platform: 'android',
      onWipe: () => wiped++,
    );
    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.tap(_inDialog(t.commonActionCancel));
    await settle(tester);
    expect(find.text(t.privacyDeleteTitle), findsNothing);
    expect(find.text(t.privacyDeleteWorking), findsNothing);
    expect(wiped, 0);

    // Dismissing by tapping outside deletes nothing either.
    await tester.ensureVisible(find.text(t.privacyDeleteRow));
    await tester.tap(find.text(t.privacyDeleteRow));
    await settle(tester);
    await tester.tapAt(const Offset(2, 2));
    await settle(tester);
    expect(wiped, 0);
  });

  for (final locale in const [Locale('ar'), Locale('en')]) {
    testWidgets(
      'confirm says the cloud backups stay (${locale.languageCode})',
      (tester) async {
        final h = SettingsHarness();
        addTearDown(h.db.close);
        final t = await _openDialog(
          tester,
          h,
          platform: 'android',
          locale: locale,
        );
        expect(find.text(t.privacyDeleteBackupsKept), findsOneWidget);
      },
    );

    testWidgets('a wipe that fails closes the progress and says so '
        '(${locale.languageCode})', (tester) async {
      final h = SettingsHarness();
      addTearDown(h.db.close);
      final t = await _openDialog(
        tester,
        h,
        platform: 'android',
        locale: locale,
        wipe: () async => throw StateError('wipe'),
      );
      await tester.enterText(
        find.byType(TextField),
        locale.languageCode == 'ar' ? 'احذف' : 'DELETE',
      );
      await tester.tap(_inDialog(t.privacyDeleteConfirm));
      await settle(tester);
      expect(find.text(t.privacyDeleteWorking), findsNothing);
      expect(find.text(t.privacyDeleteFailed), findsOneWidget);
    });
  }
}
