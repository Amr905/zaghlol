// WIRE-SVC items 2 and 4: the iCloud destination adapter and the app version.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/backup/application/icloud_backup_destination.dart';
import 'package:zaghlol/features/backup/application/icloud_backup_service.dart';
import 'package:zaghlol/features/backup/application/schedule_providers.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/data/icloud_store.dart';
import 'package:zaghlol/features/catalog_sync/application/sync_providers.dart';

import 'snapshot_test_support.dart';

ICloudBackupOutcome _outcome({required bool uploaded}) => ICloudBackupOutcome(
  entry: const ICloudBackupEntry(
    name: 'x',
    sizeBytes: 1,
    createdAtMs: 1,
    isUploaded: true,
    isDownloaded: true,
    quotaExceeded: false,
    uploadFailed: false,
    labelSeq: 1,
    labelCreatedAtMs: 1,
  ),
  uploaded: uploaded,
  prune: const ICloudPruneReport(deleted: 0, skipped: true),
  seqStored: true,
);

void main() {
  test('the backup app version is the build define, not 0.0.0', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(backupAppVersionProvider), kClientAppVersion);
    expect(c.read(backupAppVersionProvider), isNot('0.0.0'));
  });

  test('on a non-iOS host the iCloud destination is null', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(icloudBackupDestinationProvider), isNull);
  });

  test('the adapter passes keep, platform and version; confirmed follows '
      'the upload', () async {
    BackupPlatform? platformSeen;
    String? version;
    int? keepSeen;
    var uploaded = true;
    final d = ICloudBackupDestination(
      (keys, {required keep, required platform, required appVersion}) async {
        keepSeen = keep;
        version = appVersion;
        platformSeen = platform;
        return _outcome(uploaded: uploaded);
      },
      platform: BackupPlatform.ios,
      appVersion: '1.2.3',
    );
    final phone = await Phone.create(seedA, 'wire_icloud');
    addTearDown(phone.dispose);
    final keys = await phone.cipher.createKey('correct horse battery');
    addTearDown(keys.zeroize);
    final ok = await d.backupNow(keys, keep: 5, interactive: false);
    expect(ok.confirmed, isTrue);
    expect((keepSeen, version, platformSeen), (5, '1.2.3', BackupPlatform.ios));
    uploaded = false;
    expect(
      (await d.backupNow(keys, keep: 1, interactive: true)).confirmed,
      isFalse,
    );
  });
}
