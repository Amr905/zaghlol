// T-148: KEK_pass = Argon2id(P, salt, m, t, p, tag 32, v0x13, no secret, no
// associated data) via `package:hashlib` (design note §1, §3, §5). Runs only
// in the foreground, always in `Isolate.run` so the UI keeps animating. The
// bounds are checked again here so no caller can run the KDF with hostile
// parameters.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:hashlib/hashlib.dart';

import 'backup_crypto_exception.dart';
import 'backup_format.dart';
import 'secret_bytes.dart';

/// Derives KEK_pass. Tests inject a fast fake; the app uses [Argon2idKdf].
abstract interface class PassphraseKdf {
  /// Derives a 32-byte key from [password] (P). The caller still owns and
  /// zeroes [password]. Throws BackupCryptoException(unsupportedKdf,
  /// kdfOutOfMemory, io).
  Future<SecretBytes> derive(Uint8List password, KdfParams params);
}

final class Argon2idKdf implements PassphraseKdf {
  const Argon2idKdf({this.runInIsolate = true});

  /// False only in tests that measure the raw cost.
  final bool runInIsolate;

  @override
  Future<SecretBytes> derive(Uint8List password, KdfParams params) async {
    if (!params.withinBounds) {
      throw BackupCryptoException(BackupCryptoErrorCode.unsupportedKdf);
    }
    final pw = Uint8List.fromList(password);
    final salt = Uint8List.fromList(params.salt);
    final m = params.memoryKiB;
    final t = params.iterations;
    final p = params.parallelism;
    try {
      final Uint8List out;
      if (runInIsolate) {
        out = await Isolate.run(() => argon2idRaw(pw, salt, m, t, p));
      } else {
        out = argon2idRaw(pw, salt, m, t, p);
      }
      return SecretBytes.adopt(out);
    } on OutOfMemoryError {
      throw BackupCryptoException(BackupCryptoErrorCode.kdfOutOfMemory);
    } on BackupCryptoException {
      rethrow;
    } on Object {
      throw BackupCryptoException(BackupCryptoErrorCode.io);
    } finally {
      wipe(pw);
    }
  }
}

/// Argon2id v1.3, 32-byte tag. No bounds check: callers check first. Zeroes
/// its own copy of the password (inside an isolate that is the isolate's
/// copy).
Uint8List argon2idRaw(
  Uint8List password,
  Uint8List salt,
  int memoryKiB,
  int iterations,
  int parallelism, {
  List<int>? secret,
  List<int>? associatedData,
  int tagLength = keyLength,
}) {
  try {
    final digest = Argon2(
      type: Argon2Type.argon2id,
      version: Argon2Version.v13,
      parallelism: parallelism,
      memorySizeKB: memoryKiB,
      iterations: iterations,
      hashLength: tagLength,
      salt: salt,
      key: secret,
      personalization: associatedData,
    ).convert(password);
    return Uint8List.fromList(digest.bytes);
  } finally {
    wipe(password);
  }
}
