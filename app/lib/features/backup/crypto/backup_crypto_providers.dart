// T-148: Riverpod wiring (design note §8). BackupCipher is stateless and
// never caches keys; no provider here holds key bytes.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/db_key_providers.dart';
import '../../../core/platform/pigeon_text_normalizer.dart';
import 'backup_cipher.dart';
import 'passphrase.dart';

/// Unicode NFC through the platform. Overridden with a fake in tests.
final textNormalizerProvider = Provider<TextNormalizer>(
  (ref) => PigeonTextNormalizer(),
  name: 'textNormalizerProvider',
);

/// The key slot store. Its DB adapter lands with the `secure_state` table
/// (T-019); until then the app must override this provider before use.
final backupKeySlotStoreProvider = Provider<BackupKeySlotStore>(
  (ref) => throw UnimplementedError('BACKUP_KEY_SLOT_STORE_NOT_CONFIGURED'),
  name: 'backupKeySlotStoreProvider',
);

final backupCipherProvider = Provider<BackupCipher>(
  (ref) => BackupCipher(
    secretStore: ref.watch(secretStoreProvider),
    slotStore: ref.watch(backupKeySlotStoreProvider),
    normalizer: ref.watch(textNormalizerProvider),
  ),
  name: 'backupCipherProvider',
);
