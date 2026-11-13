// Pigeon contract: seat keys (T-179; platform-channels §4b, D-55, D-62).
// iOS only: there is deliberately no kotlinOut, so an Android build carries no
// seat-key code (D-55). Regenerate with app/tool/generate_pigeon.sh; CI fails
// when the generated files are stale.
//
// Errors are code-only: `SEAT_KEY_UNAVAILABLE` when the Keychain state can't
// be read or written (for example before the first unlock). No message or
// details are ever set.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/seat_key_api.g.dart',
    dartPackageName: 'zaghlol',
    swiftOut: 'ios/Runner/Platform/SeatKeyApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'SeatKeyApiError'),
  ),
)
@HostApi() // iOS only; Android has no implementation (D-55)
abstract class SeatKeyHostApi {
  /// Ensures this install has a seat key (creates one in the Secure Enclave on
  /// first call) and returns [own, earlier…] public keys (X9.63, 65 bytes),
  /// newest first, at most 5. Empty list when the Secure Enclave is
  /// unavailable.
  List<Uint8List> publicKeys();

  /// Signs `message` (built in Dart: "zaghlol-seat-v1" ‖ 0 ‖ op ‖ 0 ‖
  /// installId ‖ 0 ‖ challenge) with every key, same order. Returns IEEE P1363
  /// r‖s signatures (64 bytes). A key that can't be used is dropped from the
  /// Keychain and from the result.
  List<SeatSignature> sign(Uint8List message);

  /// Called once when a new install is created: the current key becomes an
  /// "earlier" key; a new one is made lazily.
  void rotateForNewInstall();
}

class SeatSignature {
  SeatSignature({required this.publicKey, required this.signature});

  Uint8List publicKey;
  Uint8List signature;
}
