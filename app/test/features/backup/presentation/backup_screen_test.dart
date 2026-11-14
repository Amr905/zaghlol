import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/backup/crypto/backup_crypto_exception.dart';
import 'package:zaghlol/features/backup/data/drive_backup_exception.dart';
import 'package:zaghlol/features/backup/presentation/backup_screen.dart';
import 'package:zaghlol/features/gold/application/gating.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';

import 'backup_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14);
  for (final lang in ['ar', 'en']) {
    group('S-66 ($lang)', () {
      late FakeActions actions;
      late FakeGateway gw;
      late ProviderContainer container;
      var restoreOpened = 0;
      var paywall = 0;

      Future<AppLocalizations> pump(
        WidgetTester t, {
        DateTime? last,
        bool gold = false,
        bool icloud = false,
      }) async {
        await t.binding.setSurfaceSize(const Size(360, 900));
        addTearDown(() => t.binding.setSurfaceSize(null));
        restoreOpened = 0;
        paywall = 0;
        container = ProviderContainer(
          overrides: [
            ...baseOverrides(
              lang: lang,
              actions: actions,
              gateway: gw,
              last: last,
            ),
            paywallTriggerProvider.overrideWithValue((_) => paywall++),
          ],
        );
        addTearDown(container.dispose);
        if (gold) {
          container
              .read(entitlementStateProvider.notifier)
              .applyVerified(verified: true, status: 'active');
        }
        await t.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: host(
              BackupScreen(
                iCloudAvailable: icloud,
                now: () => now,
                onOpenRestore: () => restoreOpened++,
              ),
              lang: lang,
              scale: 1.3,
            ),
          ),
        );
        await t.pumpAndSettle();
        return AppLocalizations.of(t.element(find.byType(BackupScreen)));
      }

      setUp(() {
        actions = FakeActions();
        gw = FakeGateway()
          ..entries = [
            entry(now),
            entry(now.subtract(const Duration(days: 7))),
          ];
      });

      testWidgets('never backed up: nudge, locked Gold rows open the paywall', (
        t,
      ) async {
        final l = await pump(t);
        expect(find.text(l.backupSettingsNever), findsOneWidget);
        expect(find.text(l.backupSettingsFreeNudge), findsOneWidget);
        expect(find.text(l.backupSettingsAutoLocked), findsOneWidget);
        expect(find.text(l.backupSettingsVersionsLocked), findsOneWidget);
        await t.tap(find.text(l.backupSettingsAutoLocked));
        expect(paywall, 1);
        expect(t.takeException(), isNull);
      });

      testWidgets('free with a backup shows the replace note', (t) async {
        final l = await pump(t, last: now.subtract(const Duration(days: 3)));
        expect(find.text(l.backupSettingsFreeReplaces), findsOneWidget);
        expect(gw.calls, everyElement('list-passive'));
      });

      testWidgets('stale free backup shows the reminder banner', (t) async {
        final l = await pump(t, last: now.subtract(const Duration(days: 40)));
        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
        expect(l.backupSettingsStale(40, '40'), isNotEmpty);
      });

      testWidgets('first backup asks for a passphrase, then backs up', (
        t,
      ) async {
        actions.key = false;
        final l = await pump(t);
        await t.tap(find.text(l.backupSettingsNow));
        await t.pumpAndSettle();
        expect(find.text(l.backupPassphraseWarning), findsOneWidget);
        final f = find.byType(TextField);
        await t.ensureVisible(f.at(0));
        await t.enterText(f.at(0), 'abcdefghijkl');
        await t.ensureVisible(f.at(1));
        await t.enterText(f.at(1), 'abcdefghijkl');
        await t.ensureVisible(find.byType(Checkbox));
        await t.tap(find.byType(Checkbox));
        final save = find.text(l.backupPassphraseSave);
        await t.ensureVisible(save);
        await t.tap(save);
        await t.pumpAndSettle();
        expect(actions.calls, [
          'hasKey',
          'createKey:abcdefghijkl',
          'backup:drive',
        ]);
        expect(find.text(l.backupSettingsDone), findsOneWidget);
      });

      testWidgets('running shows the counting mascot', (t) async {
        actions.backupGate = Completer<void>();
        final l = await pump(t);
        await t.tap(find.text(l.backupSettingsNow));
        await t.pump();
        await t.pump();
        expect(find.text(l.backupSettingsRunning), findsWidgets);
        expect(
          t.widget<ZaghlolAvatar>(find.byType(ZaghlolAvatar)).moment,
          ZaghlolMoment.counting,
        );
        actions.backupGate!.complete();
        await t.pumpAndSettle();
        expect(find.byType(ZaghlolAvatar), findsNothing);
      });

      final errors = <String, Object>{
        'network': DriveBackupException(DriveBackupErrorCode.network),
        'quota': DriveBackupException(DriveBackupErrorCode.quotaExceeded),
        'auth': DriveBackupException(DriveBackupErrorCode.signInRequired),
        'other': StateError('x'),
      };
      for (final e in errors.entries) {
        testWidgets('error ${e.key}: Try again, last backup untouched', (
          t,
        ) async {
          actions.backupError = e.value;
          final l = await pump(t, last: now);
          await t.tap(find.text(l.backupSettingsNow));
          await t.pumpAndSettle();
          expect(find.text(l.commonActionTryAgain), findsOneWidget);
          actions.backupError = null;
          await t.tap(find.text(l.commonActionTryAgain));
          await t.pumpAndSettle();
          expect(find.text(l.backupSettingsDone), findsOneWidget);
        });
      }

      testWidgets('key mismatch asks for the passphrase and continues', (
        t,
      ) async {
        actions.hasKeyError = BackupCryptoException(
          BackupCryptoErrorCode.keyMismatch,
        );
        final l = await pump(t);
        await t.tap(find.text(l.backupSettingsNow));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), 'abcdefghijkl');
        await t.tap(find.text(l.commonActionSave));
        await t.pumpAndSettle();
        expect(actions.calls, contains('recover:abcdefghijkl'));
        expect(actions.calls, contains('backup:drive'));
      });

      testWidgets('gold: schedule control and versions list', (t) async {
        final l = await pump(t, gold: true, last: now);
        expect(find.text(l.backupSettingsAutoWeekly), findsOneWidget);
        await t.tap(find.text(l.backupSettingsAutoWeekly));
        await t.pumpAndSettle();
        expect(actions.calls, contains('schedule:weekly'));
        await t.scrollUntilVisible(
          find.text(l.backupSettingsRestore),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(l.backupSettingsVersions), findsOneWidget);
        expect(find.text(l.backupSettingsAutoLocked), findsNothing);
        await t.tap(find.text(l.backupSettingsRestore));
        expect(restoreOpened, 1);
      });

      testWidgets('iCloud choice only on iPhone', (t) async {
        final l = await pump(t, icloud: true);
        expect(find.text(l.backupRestoreOptionICloud), findsOneWidget);
        await t.tap(find.text(l.backupRestoreOptionICloud));
        await t.pumpAndSettle();
        await t.tap(find.text(l.backupSettingsNow));
        await t.pumpAndSettle();
        expect(actions.calls, contains('backup:icloud'));
      });

      testWidgets('change passphrase asks current and new', (t) async {
        final l = await pump(t);
        await t.scrollUntilVisible(
          find.text(l.backupSettingsPassphraseChange),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await t.tap(find.text(l.backupSettingsPassphraseChange));
        await t.pumpAndSettle();
        final f = find.byType(TextField);
        expect(f, findsNWidgets(3));
        await t.ensureVisible(f.at(0));
        await t.enterText(f.at(0), 'oldoldoldold');
        await t.ensureVisible(f.at(1));
        await t.enterText(f.at(1), 'newnewnewnew');
        await t.ensureVisible(f.at(2));
        await t.enterText(f.at(2), 'newnewnewnew');
        await t.ensureVisible(find.byType(Checkbox));
        await t.tap(find.byType(Checkbox));
        final save = find.text(l.commonActionSave);
        await t.ensureVisible(save);
        await t.tap(save);
        await t.pumpAndSettle();
        expect(actions.calls, contains('change:oldoldoldold>newnewnewnew'));
      });
    });
  }
}
