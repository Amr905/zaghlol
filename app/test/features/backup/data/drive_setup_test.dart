// T-270 (US-P09): a build without the Google client ID is detected before
// the backup starts, and the failure maps to its own kind, not the generic
// error or a sign-in problem.

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/google_sign_in_gate.dart';
import 'package:zaghlol/features/backup/application/schedule.dart'
    show BackupRunFailure;
import 'package:zaghlol/features/backup/data/drive_auth.dart';
import 'package:zaghlol/features/backup/data/drive_backup_exception.dart';
import 'package:zaghlol/features/backup/presentation/backup_ports.dart';

void main() {
  group('driveBackupSetupOf', () {
    DriveBackupSetup of({
      required bool ios,
      String? flavor,
      String iosId = '',
      String serverId = '',
    }) => driveBackupSetupOf(
      isIos: ios,
      flavor: flavor,
      iosClientId: iosId,
      serverClientId: serverId,
    );

    test('Android needs the server client ID', () {
      expect(of(ios: false, serverId: 'x'), DriveBackupSetup.ready);
      // The iOS ID alone does not make Android ready.
      expect(
        of(ios: false, flavor: 'prodSms', iosId: 'x'),
        DriveBackupSetup.missingInRelease,
      );
    });

    test('iPhone needs the iOS client ID', () {
      expect(of(ios: true, iosId: 'x'), DriveBackupSetup.ready);
      expect(
        of(ios: true, flavor: 'prod', serverId: 'x'),
        DriveBackupSetup.missingInRelease,
      );
    });

    test('dev and staging flavours get the build details; prod and no '
        'flavour get the user wording', () {
      for (final f in ['devSms', 'devNoSms', 'stagingSms', 'stagingNoSms']) {
        expect(of(ios: false, flavor: f), DriveBackupSetup.missingInDevBuild);
      }
      for (final f in ['prodSms', 'prodNoSms', 'prod', null, '']) {
        expect(of(ios: false, flavor: f), DriveBackupSetup.missingInRelease);
      }
    });

    test('the authorizer refuses with notConfigured before calling Google', () {
      final auth = GoogleSignInDriveAuthorizer(
        isIos: false,
        serverClientId: '',
        gate: GoogleSignInGate(),
      );
      expect(
        auth.accessToken(interactive: true),
        throwsA(
          isA<DriveBackupException>().having(
            (e) => e.reason,
            'reason',
            DriveBackupErrorCode.notConfigured,
          ),
        ),
      );
    });
  });

  test('backupErrorKindOf: DRIVE_NOT_CONFIGURED has its own kind, also when '
      'wrapped by the schedule service', () {
    final direct = DriveBackupException(DriveBackupErrorCode.notConfigured);
    expect(backupErrorKindOf(direct), BackupErrorKind.notConfigured);
    expect(
      backupErrorKindOf(BackupRunFailure(direct.code)),
      BackupErrorKind.notConfigured,
    );
    expect(
      backupErrorKindOf(
        BackupRunFailure(DriveBackupErrorCode.signInCancelled.safeCode),
      ),
      BackupErrorKind.auth,
    );
  });
}
