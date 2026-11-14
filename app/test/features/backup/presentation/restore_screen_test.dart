import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/l10n/generated/app_localizations.dart';
import 'package:zaghlol/features/backup/crypto/backup_crypto_exception.dart';
import 'package:zaghlol/features/backup/data/drive_backup_exception.dart';
import 'package:zaghlol/features/backup/presentation/backup_ports.dart';
import 'package:zaghlol/features/backup/presentation/restore_screen.dart';
import 'package:zaghlol/features/mascot/presentation/zaghlol_avatar.dart';

import 'backup_fakes.dart';

void main() {
  for (final lang in ['ar', 'en']) {
    group('S-04 ($lang)', () {
      late FakeGateway gw;
      late FakeEffects fx;
      var fresh = 0;
      bool? regrant;

      Future<AppLocalizations> pump(
        WidgetTester t, {
        bool icloud = false,
        bool replaces = false,
        bool hasData = false,
      }) async {
        await t.binding.setSurfaceSize(const Size(360, 780));
        addTearDown(() => t.binding.setSurfaceSize(null));
        fresh = 0;
        regrant = null;
        await t.pumpWidget(
          ProviderScope(
            overrides: baseOverrides(
              lang: lang,
              gateway: gw,
              effects: fx,
              holdsLocalData: hasData,
            ),
            child: host(
              RestoreScreen(
                iCloudAvailable: icloud,
                replacesExistingData: replaces,
                onStartFresh: () => fresh++,
                onUpdateApp: () {},
                onRestored: ({required bool regrantDue}) =>
                    regrant = regrantDue,
              ),
              lang: lang,
              scale: 1.3,
            ),
          ),
        );
        await t.pumpAndSettle();
        return AppLocalizations.of(t.element(find.byType(RestoreScreen)));
      }

      setUp(() {
        gw = FakeGateway()..entries = [entry(DateTime.utc(2026, 10, 31))];
        fx = FakeEffects();
      });

      testWidgets('choose provider; iCloud only when offered', (t) async {
        final l = await pump(t);
        expect(find.text(l.backupRestoreOptionDrive), findsOneWidget);
        expect(find.text(l.backupRestoreOptionICloud), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        final l2 = await pump(t, icloud: true);
        expect(find.text(l2.backupRestoreOptionICloud), findsOneWidget);
      });

      testWidgets('found, wrong passphrase, then success with re-grant', (
        t,
      ) async {
        final l = await pump(t);
        await t.tap(find.text(l.commonActionContinue));
        await t.pumpAndSettle();
        expect(find.text(l.backupRestoreFoundTitle), findsOneWidget);
        // Empty passphrase is refused.
        await t.tap(find.text(l.backupRestoreRestore));
        await t.pumpAndSettle();
        expect(find.text(l.backupRestorePassphraseRequired), findsOneWidget);
        expect(gw.calls, isNot(contains('restore')));
        // Wrong, with unlimited retries.
        gw.restoreError = BackupCryptoException(
          BackupCryptoErrorCode.wrongPassphrase,
        );
        await t.enterText(find.byType(TextField), 'wrong passphrase');
        await t.tap(find.text(l.backupRestoreRestore));
        await t.pumpAndSettle();
        expect(find.text(l.backupRestorePassphraseWrong), findsOneWidget);
        // Right.
        gw.restoreError = null;
        fx.flags = const RestoreDueFlags(regrantDue: true);
        await t.enterText(find.byType(TextField), 'right passphrase');
        await t.tap(find.text(l.backupRestoreRestore));
        await t.pumpAndSettle();
        expect(find.text(l.backupRestoreDoneBanner), findsOneWidget);
        await t.tap(find.text(l.backupRestoreDoneAction));
        expect(regrant, isTrue);
        expect(t.takeException(), isNull);
      });

      testWidgets('replacesExistingData: confirm gates the restore', (t) async {
        final l = await pump(t, replaces: true);
        await t.tap(find.text(l.commonActionContinue));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), 'right passphrase');
        await t.tap(find.text(l.backupRestoreRestore));
        await t.pumpAndSettle();
        expect(find.text(l.backupRestoreReplaceConfirm), findsOneWidget);
        expect(gw.calls, isNot(contains('restore')));
        await t.tap(find.text(l.commonActionCancel));
        await t.pumpAndSettle();
        expect(gw.calls, isNot(contains('restore')));
        expect(find.text(l.backupRestoreFoundTitle), findsOneWidget);
        await t.enterText(find.byType(TextField), 'right passphrase');
        await t.tap(find.text(l.backupRestoreRestore));
        await t.pumpAndSettle();
        await t.tap(find.text(l.backupRestoreReplaceAction));
        await t.pumpAndSettle();
        expect(gw.calls.where((c) => c == 'restore'), hasLength(1));
      });

      testWidgets('phone holds data (Welcome path): confirm gates', (t) async {
        final l = await pump(t, hasData: true);
        await t.tap(find.text(l.commonActionContinue));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), 'right passphrase');
        await t.tap(find.text(l.backupRestoreRestore));
        await t.pumpAndSettle();
        expect(find.text(l.backupRestoreReplaceConfirm), findsOneWidget);
        expect(gw.calls, isNot(contains('restore')));
      });

      testWidgets('no replacesExistingData: restores directly', (t) async {
        final l = await pump(t);
        await t.tap(find.text(l.commonActionContinue));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), 'right passphrase');
        await t.tap(find.text(l.backupRestoreRestore));
        await t.pumpAndSettle();
        expect(find.text(l.backupRestoreReplaceConfirm), findsNothing);
        expect(gw.calls, contains('restore'));
      });

      testWidgets('restoring: counting mascot, no way out', (t) async {
        gw.restoreGate = Completer<bool>();
        final l = await pump(t);
        await t.tap(find.text(l.commonActionContinue));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), 'right passphrase');
        await t.tap(find.text(l.backupRestoreRestore));
        await t.pump();
        expect(find.text(l.backupRestoreRestoring), findsOneWidget);
        expect(find.text(l.backupRestoreKeepOpen), findsOneWidget);
        expect(find.byType(BackButton), findsNothing);
        final avatar = t.widget<ZaghlolAvatar>(find.byType(ZaghlolAvatar));
        expect(avatar.moment, ZaghlolMoment.counting);
        gw.restoreGate!.complete(true);
        await t.pumpAndSettle();
        expect(find.text(l.backupRestoreDoneBanner), findsOneWidget);
      });

      testWidgets('empty: try another account and start fresh', (t) async {
        gw.entries = [];
        final l = await pump(t);
        await t.tap(find.text(l.commonActionContinue));
        await t.pumpAndSettle();
        expect(find.text(l.backupRestoreEmptyTitle), findsOneWidget);
        await t.tap(find.text(l.backupRestoreStartFresh));
        expect(fresh, 1);
        await t.tap(find.text(l.backupRestoreTryAnotherAccount));
        await t.pumpAndSettle();
        expect(find.text(l.backupRestoreWhereTitle), findsOneWidget);
      });

      testWidgets('network error then retry', (t) async {
        gw.listError = DriveBackupException(DriveBackupErrorCode.network);
        final l = await pump(t);
        await t.tap(find.text(l.commonActionContinue));
        await t.pumpAndSettle();
        expect(
          find.text(l.backupRestoreErrorNetwork(l.backupRestoreOptionDrive)),
          findsOneWidget,
        );
        gw.listError = null;
        await t.tap(find.text(l.commonActionTryAgain));
        await t.pumpAndSettle();
        expect(find.text(l.backupRestoreFoundTitle), findsOneWidget);
      });

      testWidgets('newer version offers the update', (t) async {
        gw.restoreError = BackupCryptoException(
          BackupCryptoErrorCode.newerSchema,
        );
        final l = await pump(t);
        await t.tap(find.text(l.commonActionContinue));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField), 'right passphrase');
        await t.tap(find.text(l.backupRestoreRestore));
        await t.pumpAndSettle();
        expect(find.text(l.backupRestoreErrorNewer), findsOneWidget);
        expect(find.text(l.backupRestoreUpdate), findsOneWidget);
      });

      testWidgets('corrupted: older backup when there is one, else fresh', (
        t,
      ) async {
        gw.entries = [
          entry(DateTime.utc(2026, 10, 31)),
          entry(DateTime.utc(2026, 10, 24)),
        ];
        gw.restoreError = BackupCryptoException(
          BackupCryptoErrorCode.corruptData,
        );
        final l = await pump(t);
        await t.tap(find.text(l.commonActionContinue));
        await t.pumpAndSettle();
        expect(find.text(l.backupRestoreVersionsTitle), findsOneWidget);
        expect(
          find.textContaining(l.backupRestoreVersionNewest),
          findsOneWidget,
        );
        await t.enterText(find.byType(TextField), 'right passphrase');
        await t.tap(find.text(l.backupRestoreRestore));
        await t.pumpAndSettle();
        expect(find.text(l.backupRestoreErrorCorrupted), findsOneWidget);
        await t.tap(find.text(l.backupRestoreTryOlder));
        await t.pumpAndSettle();
        expect(find.text(l.backupRestoreVersionsTitle), findsOneWidget);
        expect(find.text(l.backupRestoreRestore), findsOneWidget);
      });

      testWidgets('forgot passphrase explains it cannot be recovered', (
        t,
      ) async {
        final l = await pump(t);
        await t.tap(find.text(l.commonActionContinue));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text(l.backupRestoreForgotLink));
        await t.tap(find.text(l.backupRestoreForgotLink));
        await t.pumpAndSettle();
        expect(find.text(l.backupRestoreForgotBody), findsOneWidget);
      });
    });
  }
}
