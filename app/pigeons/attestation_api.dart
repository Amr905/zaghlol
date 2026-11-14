// Pigeon contract: device attestation for restore (T-178). Contract:
// docs/03-technical/platform-channels.md §4a (D-45/D-46, FR-GOLD-09, R2-1,
// R4-1(3)). Regenerate with app/tool/generate_pigeon.sh; CI fails when the
// generated files are stale.
//
// Rules for the native side (both platforms): native code never builds or
// alters the hash and never sees the install ID; it signs exactly the 32
// bytes Dart passes. Proofs, tokens and key IDs are never logged. Errors
// cross the boundary as code-only `ATTEST_TRANSIENT`,
// `ATTEST_PLAY_SERVICES_OUTDATED` or `ATTEST_UNAVAILABLE` (§6).
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/attestation_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut: 'android/app/src/main/kotlin/app/zaghlol/platform/attestation/AttestationApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.attestation',
      errorClassName: 'AttestationApiError',
    ),
    swiftOut: 'ios/Runner/Platform/AttestationApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'AttestationApiError'),
  ),
)
/// The proof that goes into the restore body's `attestation` object.
class AttestationProof {
  /// 'play_integrity' | 'app_attest'
  late String type;

  /// Android: the Play Integrity standard token.
  String? token;

  /// iOS: the App Attest key ID (base64, as DCAppAttestService returns it).
  String? keyId;

  /// iOS: the assertion over clientDataHash (base64).
  String? assertion;

  /// iOS: base64, only for a newly generated key.
  String? attestationObject;
}

@HostApi()
abstract class AttestationHostApi {
  /// Android: Play Integrity StandardIntegrityManager.prepareIntegrityToken
  /// (cached provider). iOS: no-op.
  @async
  void prepare();

  /// Android: requestHash = base64url(bodyHash) (unpadded) →
  /// StandardIntegrityTokenProvider.request → token. iOS: clientDataHash =
  /// bodyHash for DCAppAttestService.generateAssertion, and for attestKey on
  /// a new key (forceNewKey, a missing key or an invalidKey error).
  @async
  AttestationProof attest(Uint8List bodyHash, bool forceNewKey);
}
