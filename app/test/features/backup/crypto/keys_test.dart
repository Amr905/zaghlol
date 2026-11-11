// T-148 §3 and §9 "Keys": setup, automatic-backup load, passphrase change
// (rotation), crash between secret and slot writes, recovery, unavailable
// stores, the broken-generator rule and two concurrent actors.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/crypto/secret_store.dart';
import 'package:zaghlol/features/backup/crypto/backup_cipher.dart';
import 'package:zaghlol/features/backup/crypto/backup_crypto_exception.dart';
import 'package:zaghlol/features/backup/crypto/backup_format.dart';
import 'package:zaghlol/features/backup/crypto/backup_keys.dart';
import 'package:zaghlol/features/backup/crypto/secret_bytes.dart';

import 'backup_test_support.dart';

const String oldPass = 'the old passphrase';
const String newPass = 'the new passphrase';

Future<void> opens(Rig rig, Uint8List file, String pass) async {
  final s = await rig.cipher.open(streamOf(file), pass, maxSchemaVersion: 3);
  await collect(s.plaintext);
  (await s.done).keys.zeroize();
}

void main() {
  late Rig rig;
  setUp(() => rig = Rig());

  test('createKey stores K_bk and the slot; loadKeys pairs them', () async {
    expect(await rig.cipher.loadKeys(), isNull, reason: 'never set up');
    final keys = await rig.cipher.createKey(oldPass);
    final stored = rig.store.values[SecretSlot.backupKey]!;
    expect(keys.sameKeyAs(SecretBytes.copyOf(stored)), isTrue);
    expect(KeySlot.fromCbor(rig.slots.stored!).sameAs(keys.slot), isTrue);
    expect(rig.store.values.containsKey(SecretSlot.dbKey), isFalse);
    final loaded = (await rig.cipher.loadKeys())!;
    expect(loaded.slot.sameAs(keys.slot), isTrue);
    // Automatic backups need no KDF.
    final kdf = rig.kdf as FastKdf;
    final before = kdf.calls;
    final file = await rig.write(loaded, payload(100));
    expect(kdf.calls, before);
    await opens(rig, file, oldPass);
    // The lease was taken and released.
    expect(rig.store.calls.where((c) => c == 'acquire').length, 1);
    final calls = rig.store.calls;
    expect(calls.where((c) => c == 'release').length, 1);
    expect(
      calls.indexOf('release'),
      greaterThan(calls.lastIndexOf('create:backupKey')),
    );
    // Order under the lease: delete, create, read back.
    final createIdx = calls.indexOf('create:backupKey');
    expect(calls.indexOf('delete:backupKey'), lessThan(createIdx));
    expect(calls.indexOf('read:backupKey', createIdx), greaterThan(createIdx));
  });

  test('changePassphrase rotates K_bk: new kbkId, old file opens with the '
      'old passphrase only, new file with the new one only', () async {
    final k1 = await rig.cipher.createKey(oldPass);
    final oldFile = await rig.write(k1, payload(1000));
    final k2 = await rig.cipher.changePassphrase(newPass);
    expect(k2.slot.kbkId, isNot(equals(k1.slot.kbkId)));
    expect(k2.sameKeyAs(k1.exportKey()), isFalse);
    final newFile = await rig.write(
      (await rig.cipher.loadKeys())!,
      payload(1000),
    );

    await opens(rig, oldFile, oldPass);
    await expectLater(
      rig.cipher.open(streamOf(oldFile), newPass, maxSchemaVersion: 3),
      throwsCode(BackupCryptoErrorCode.wrongPassphrase),
    );
    await opens(rig, newFile, newPass);
    await expectLater(
      rig.cipher.open(streamOf(newFile), oldPass, maxSchemaVersion: 3),
      throwsCode(BackupCryptoErrorCode.wrongPassphrase),
    );
    // The old keys can't verify the new file (different slot).
    await expectLater(
      rig.cipher.verifyFile(streamOf(newFile), k1),
      throwsCode(BackupCryptoErrorCode.keyMismatch),
    );
  });

  test(
    'a too-short new passphrase is refused before anything is written',
    () async {
      await expectLater(
        rig.cipher.createKey('short'),
        throwsCode(BackupCryptoErrorCode.passphraseTooShort),
      );
      expect(rig.store.calls, isEmpty);
      expect(rig.slots.writes, 0);
    },
  );

  test(
    'crash between secret write and slot write → keyMismatch, then the old '
    'passphrase recovers the pairing; nothing written with a wrong pair',
    () async {
      await rig.cipher.createKey(oldPass);
      final oldSlot = Uint8List.fromList(rig.slots.stored!);
      rig.slots.beforeWrite = () => throw StateError('process killed');
      await expectLater(
        rig.cipher.changePassphrase(newPass),
        throwsCode(BackupCryptoErrorCode.keyUnavailable),
      );
      rig.slots.beforeWrite = null;
      expect(rig.slots.stored, oldSlot, reason: 'slot unchanged');
      // The new secret is stored but does not match the old slot.
      await expectLater(
        rig.cipher.loadKeys(),
        throwsCode(BackupCryptoErrorCode.keyMismatch),
      );
      // The new passphrase can't unwrap the old slot.
      await expectLater(
        rig.cipher.recoverWithPassphrase(newPass),
        throwsCode(BackupCryptoErrorCode.wrongPassphrase),
      );
      final recovered = await rig.cipher.recoverWithPassphrase(oldPass);
      final loaded = (await rig.cipher.loadKeys())!;
      expect(loaded.slot.sameAs(recovered.slot), isTrue);
      expect(rig.slots.stored, oldSlot);
    },
  );

  test('secret lost (Keystore invalidated) while the slot exists: keyMismatch, '
      'then recovery restores the same K_bk (no rotation)', () async {
    final k = await rig.cipher.createKey(oldPass);
    final file = await rig.write(k, payload(50));
    for (final status in [SecretStatus.notFound, SecretStatus.unusable]) {
      if (status == SecretStatus.notFound) {
        rig.store.values.remove(SecretSlot.backupKey);
      } else {
        rig.store.forced[SecretSlot.backupKey] = SecretStatus.unusable;
      }
      await expectLater(
        rig.cipher.loadKeys(),
        throwsCode(BackupCryptoErrorCode.keyMismatch),
        reason: status.name,
      );
      final r = await rig.cipher.recoverWithPassphrase(oldPass);
      expect(r.slot.sameAs(k.slot), isTrue);
      final loaded = (await rig.cipher.loadKeys())!;
      expect(await rig.cipher.verifyFile(streamOf(file), loaded), 1);
    }
  });

  test('backupKey unavailable → keyUnavailable, nothing rewritten', () async {
    await rig.cipher.createKey(oldPass);
    rig.store.forced[SecretSlot.backupKey] = SecretStatus.unavailable;
    rig.store.calls.clear();
    final slotWrites = rig.slots.writes;
    await expectLater(
      rig.cipher.loadKeys(),
      throwsCode(BackupCryptoErrorCode.keyUnavailable),
    );
    await expectLater(
      rig.cipher.recoverWithPassphrase(oldPass),
      throwsCode(BackupCryptoErrorCode.keyUnavailable),
    );
    expect(rig.store.writesTo(SecretSlot.backupKey), 0);
    expect(rig.slots.writes, slotWrites);
  });

  test('slot store errors are keyUnavailable, never "not set up"', () async {
    await rig.cipher.createKey(oldPass);
    rig.slots.failRead = true;
    await expectLater(
      rig.cipher.loadKeys(),
      throwsCode(BackupCryptoErrorCode.keyUnavailable),
    );
    await expectLater(
      rig.cipher.recoverWithPassphrase(oldPass),
      throwsCode(BackupCryptoErrorCode.keyUnavailable),
    );
  });

  test(
    'a corrupt stored slot is keyMismatch (set the passphrase up again)',
    () async {
      await rig.cipher.createKey(oldPass);
      rig.slots.stored = Uint8List.fromList([0xa3, 0x01]);
      await expectLater(
        rig.cipher.loadKeys(),
        throwsCode(BackupCryptoErrorCode.keyMismatch),
      );
      final k = await rig.cipher.createKey(newPass);
      expect((await rig.cipher.loadKeys())!.slot.sameAs(k.slot), isTrue);
    },
  );

  test('lease problems are keyUnavailable and write nothing', () async {
    rig.store.failAcquire = SecretStoreErrorCode.leaseTimeout;
    await expectLater(
      rig.cipher.createKey(oldPass),
      throwsCode(BackupCryptoErrorCode.keyUnavailable),
    );
    expect(rig.store.writesTo(SecretSlot.backupKey), 0);
    rig.store.failAcquire = null;
    rig.store.renewFails = true;
    await expectLater(
      rig.cipher.createKey(oldPass),
      throwsCode(BackupCryptoErrorCode.keyUnavailable),
    );
    expect(rig.store.writesTo(SecretSlot.backupKey), 0);
    expect(rig.slots.writes, 0);
  });

  test('a broken generator (all-equal K_bk) is refused', () async {
    final random = ScriptedRandom([
      List.filled(saltLength, 9),
      List.filled(keyLength, 0x42),
    ]);
    final r = Rig(random: random);
    await expectLater(
      r.cipher.createKey(oldPass),
      throwsCode(BackupCryptoErrorCode.io),
    );
    expect(r.store.calls, isEmpty);
  });

  test(
    'two concurrent passphrase changes: the stored pair always matches',
    () async {
      await rig.cipher.createKey(oldPass);
      final results = await Future.wait([
        rig.cipher
            .changePassphrase('first concurrent pass')
            .then<Object>((k) => k, onError: (Object e) => e),
        rig.cipher
            .changePassphrase('second concurrent pass')
            .then<Object>((k) => k, onError: (Object e) => e),
      ]);
      final winners = results.whereType<BackupKeys>().toList();
      expect(winners, isNotEmpty);
      // Whatever happened, the stored secret and slot are a valid pair, and it
      // is the pair of the last actor that completed.
      final loaded = (await rig.cipher.loadKeys())!;
      expect(winners.any((w) => w.slot.sameAs(loaded.slot)), isTrue);
    },
  );

  test('recovery re-checks the slot under the lease (ownership)', () async {
    await rig.cipher.createKey(oldPass);
    rig.store.values.remove(SecretSlot.backupKey);
    // Another actor changes the passphrase while recovery runs its KDF: the
    // slot recovery unwrapped is no longer current, so it must not store the
    // old key next to the new slot.
    final other = Rig();
    final newKeys = await other.cipher.createKey(newPass);
    var swapped = false;
    final kdf = _HookKdf(() {
      if (swapped) return;
      swapped = true;
      rig.slots.stored = newKeys.slot.toCbor();
      rig.store.values[SecretSlot.backupKey] = Uint8List.fromList(
        newKeys.exportKey().bytes,
      );
    });
    final r2 = BackupCipher(
      secretStore: rig.store,
      slotStore: rig.slots,
      normalizer: rig.nfc,
      kdf: kdf,
    );
    await expectLater(
      r2.recoverWithPassphrase(oldPass),
      throwsCode(BackupCryptoErrorCode.keyMismatch),
    );
    final loaded = (await rig.cipher.loadKeys())!;
    expect(loaded.slot.sameAs(newKeys.slot), isTrue);
  });
}

/// FastKdf that runs [hook] before deriving.
final class _HookKdf extends FastKdf {
  _HookKdf(this.hook);
  final void Function() hook;

  @override
  Future<SecretBytes> derive(Uint8List password, KdfParams params) {
    hook();
    return super.derive(password, params);
  }
}
