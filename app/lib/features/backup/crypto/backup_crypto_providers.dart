// T-148: Riverpod wiring (design note §8). BackupCipher is stateless and
// never caches keys; no provider here holds key bytes.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database_providers.dart';
import '../../../core/db/db_key_providers.dart';
import '../../../core/platform/pigeon_text_normalizer.dart';
import '../data/secure_state_key_slot_store.dart';
import 'backup_cipher.dart';
import 'passphrase.dart';

/// Unicode NFC through the platform. Overridden with a fake in tests.
final textNormalizerProvider = Provider<TextNormalizer>(
  (ref) => PigeonTextNormalizer(),
  name: 'textNormalizerProvider',
);

/// The key slot store: `secure_state` `backup.key_slot.v1` (T-149, FU-099
/// item 2).
final backupKeySlotStoreProvider = Provider<BackupKeySlotStore>(
  (ref) => SecureStateKeySlotStore(() => ref.read(appDatabaseProvider.future)),
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
