// T-148: the device-leg constants (integration_test/db_backup_crypto_tests
// .dart) equal case 0 and the NFC rows of the committed vectors.

import 'package:flutter_test/flutter_test.dart';

import '../../../../integration_test/db_backup_crypto_tests.dart';
import 'backup_test_support.dart';

void main() {
  test('DeviceVector equals vectors case 0', () {
    final v = vectorCases().first;
    expect(DeviceVector.passphrase, v['passphrase']);
    expect(DeviceVector.saltHex, v['saltHex']);
    expect(DeviceVector.kbkHex, v['kbkHex']);
    expect(DeviceVector.wrapNonceHex, v['wrapNonceHex']);
    expect(DeviceVector.fileIdHex, v['fileIdHex']);
    expect(DeviceVector.noncePrefixHex, v['noncePrefixHex']);
    expect(DeviceVector.createdAtMs, v['createdAtMs']);
    expect(DeviceVector.pHex, v['pHex']);
    expect(DeviceVector.kekHex, v['kekHex']);
    expect(DeviceVector.wrapCtHex, v['wrapCtHex']);
    expect(DeviceVector.kbkIdHex, v['kbkIdHex']);
    expect(DeviceVector.kChunkHex, v['kChunkHex']);
    expect(DeviceVector.kSnapHex, v['kSnapHex']);
    expect(DeviceVector.fileSha256, v['fileSha256']);
    expect(DeviceVector.payloadLength, v['payloadLength']);
    expect(DeviceVector.chunkSize, v['chunkSize']);
    expect(DeviceVector.seq, v['seq']);
    expect(DeviceVector.schemaVersion, v['schemaVersion']);
    expect(DeviceVector.appVersion, v['appVersion']);
    expect(v['platform'], 'android');
    final rows = (loadVectors()['nfc']! as List).cast<Map<String, Object?>>();
    expect(DeviceVector.nfcRows, [
      for (final r in rows) (r['input']! as String, r['nfc']! as String),
    ]);
  });
}
