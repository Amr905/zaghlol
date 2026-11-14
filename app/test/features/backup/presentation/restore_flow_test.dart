import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/backup/application/backup_snapshot_exception.dart';
import 'package:zaghlol/features/backup/crypto/backup_crypto_exception.dart';
import 'package:zaghlol/features/backup/data/drive_backup_exception.dart';
import 'package:zaghlol/features/backup/presentation/backup_ports.dart';
import 'package:zaghlol/features/backup/presentation/restore_flow.dart';

import 'backup_fakes.dart';

void main() {
  late FakeGateway gw;
  late FakeEffects fx;
  late ProviderContainer c;

  setUp(() {
    gw = FakeGateway()..entries = [entry(DateTime.utc(2026, 10, 31))];
    fx = FakeEffects();
    c = ProviderContainer(
      overrides: [
        backupRestoreGatewayProvider.overrideWithValue(gw),
        restoreSideEffectsProvider.overrideWithValue(fx),
      ],
    );
    addTearDown(c.dispose);
    c.listen(restoreFlowProvider, (_, _) {});
  });

  RestoreFlow flow() => c.read(restoreFlowProvider.notifier);
  RestoreState st() => c.read(restoreFlowProvider);

  test('search: found, empty and failure states', () async {
    await flow().search();
    expect(st().phase, RestorePhase.found);
    gw.entries = [];
    await flow().search();
    expect(st().phase, RestorePhase.empty);
    gw.listError = DriveBackupException(DriveBackupErrorCode.network);
    await flow().search();
    expect(st().phase, RestorePhase.error);
    expect(st().error, RestoreFailureKind.network);
  });

  test('success: pause, restore, flags, resync, clear, resume', () async {
    fx.flags = const RestoreDueFlags(regrantDue: true, catalogResyncDue: true);
    await flow().search();
    await flow().restore('correct horse');
    expect(st().phase, RestorePhase.done);
    expect(st().regrantDue, isTrue);
    expect(fx.calls, [
      'pause',
      'flags',
      'resync',
      'clear:$resyncKey',
      'clear:$regrantKey',
      'resume',
    ]);
    expect(gw.calls, contains('restore'));
    expect(gw.calls, isNot(contains('recover')));
  });

  test('a failed resync leaves its flag for the next run', () async {
    fx.flags = const RestoreDueFlags(catalogResyncDue: true);
    fx.resyncError = StateError('x');
    await flow().search();
    await flow().restore('abcdefghij');
    expect(st().phase, RestorePhase.done);
    expect(fx.calls, isNot(contains('clear:$resyncKey')));
  });

  test(
    'keyStored false: the key is recovered with the same passphrase',
    () async {
      gw.keyStored = false;
      await flow().search();
      await flow().restore('abcdefghij');
      expect(gw.calls, containsAllInOrder(['restore', 'recover']));
      expect(st().needsKeyLater, isFalse);
      gw.recoverError = BackupCryptoException(BackupCryptoErrorCode.io);
      await flow().search();
      await flow().restore('abcdefghij');
      expect(st().phase, RestorePhase.done);
      expect(st().needsKeyLater, isTrue);
    },
  );

  test(
    'wrong passphrase stays on the found screen, retries unlimited',
    () async {
      gw.restoreError = BackupCryptoException(
        BackupCryptoErrorCode.wrongPassphrase,
      );
      await flow().search();
      for (var i = 0; i < 4; i++) {
        await flow().restore('nope');
        expect(st().phase, RestorePhase.found);
        expect(st().wrongPassphrase, isTrue);
      }
      expect(fx.calls.where((e) => e == 'resume').length, 4);
    },
  );

  test('newer version and corrupted map to their errors', () async {
    gw.restoreError = BackupCryptoException(BackupCryptoErrorCode.newerSchema);
    await flow().search();
    await flow().restore('x');
    expect(st().error, RestoreFailureKind.newer);
    gw.restoreError = BackupSnapshotException(
      BackupSnapshotErrorCode.corruptContents,
    );
    await flow().search();
    await flow().restore('x');
    expect(st().error, RestoreFailureKind.corrupted);
  });

  test('tryOlder moves to the next backup', () async {
    gw.entries = [
      entry(DateTime.utc(2026, 10, 31)),
      entry(DateTime.utc(2026, 10, 24)),
    ];
    await flow().search();
    gw.restoreError = BackupCryptoException(BackupCryptoErrorCode.corruptData);
    await flow().restore('x');
    flow().tryOlder();
    expect(st().phase, RestorePhase.found);
    expect(st().selected, 1);
  });

  test('error mapping', () {
    expect(
      restoreFailureKindOf(
        DriveBackupException(DriveBackupErrorCode.signInRequired),
      ),
      RestoreFailureKind.signIn,
    );
    expect(restoreFailureKindOf(StateError('x')), RestoreFailureKind.other);
  });
}
