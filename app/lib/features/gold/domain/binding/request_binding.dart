// T-183: restore / sign-in / verify binding hashes (backend-api §4.3,
// ADR-012 Part B (d), D-55). Pure Dart, no I/O, never logs. Byte layouts are
// fixed by the shared vectors in
// backend/tests/Zaghlol.Contract.Tests/vectors/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;

import 'binding_exceptions.dart';
import 'jcs.dart';
import 'strict_json.dart';

const String restorePrefix = 'zaghlol-restore-v1';
const String restoreAttestPrefix = 'zaghlol-restore-attest-v1';
const String seatPrefix = 'zaghlol-seat-v1';

/// Length of a raw X9.63 uncompressed P-256 point.
const int seatPublicKeyLength = 65;

enum SeatOp { verify, restore, signin }

final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

Uint8List sha256Bytes(List<int> data) =>
    Uint8List.fromList(c.sha256.convert(data).bytes);

String _checkedInstallId(String installId) {
  if (!_uuid.hasMatch(installId)) {
    throw const BindingException(BindingFailure.invalidInstallId);
  }
  return installId;
}

Uint8List _join(List<List<int>> parts) {
  final b = BytesBuilder(copy: false);
  for (final p in parts) {
    b.add(p);
  }
  return b.toBytes();
}

const List<int> _nul = [0];

/// bodyHash = SHA-256("zaghlol-restore-v1" 00 installId 00
/// JCS(body without top-level "attestation")). Private: only the strict
/// parse path ([restoreBodyHashFromJson]) is public.
Uint8List _restoreBodyHashOfMap(String installId, Map<String, Object?> body) {
  final id = _checkedInstallId(installId);
  final stripped = Map<String, Object?>.of(body)..remove('attestation');
  return sha256Bytes(
    _join([
      utf8.encode(restorePrefix),
      _nul,
      utf8.encode(id),
      _nul,
      utf8.encode(jcsCanonicalize(stripped)),
    ]),
  );
}

/// Strict-parses the exact body text about to be sent (rejecting duplicates
/// and lone surrogates) and only then hashes it.
Uint8List restoreBodyHashFromJson(String installId, String rawBody) {
  final v = parseStrictJson(rawBody);
  if (v is! Map<String, Object?>) {
    throw const BindingException(BindingFailure.malformedJson);
  }
  return _restoreBodyHashOfMap(installId, v);
}

/// JCS text of the body without "attestation" (for tests and diagnostics).
String restoreCanonicalBody(Map<String, Object?> body) =>
    jcsCanonicalize(Map<String, Object?>.of(body)..remove('attestation'));

/// SHA-256 of the concatenated raw 65-byte points, in order; SHA-256 of the
/// empty string when there are none.
Uint8List seatKeysDigest(List<Uint8List> publicKeys) {
  for (final k in publicKeys) {
    if (k.length != seatPublicKeyLength) {
      throw const BindingException(BindingFailure.invalidInput);
    }
  }
  return sha256Bytes(_join(publicKeys));
}

/// App Attest clientDataHash = SHA-256("zaghlol-restore-attest-v1" 00
/// bodyHash seatKeysDigest).
Uint8List restoreClientDataHash(
  Uint8List bodyHash,
  List<Uint8List> publicKeys,
) {
  if (bodyHash.length != 32) {
    throw const BindingException(BindingFailure.invalidInput);
  }
  return sha256Bytes(
    _join([
      utf8.encode(restoreAttestPrefix),
      _nul,
      bodyHash,
      seatKeysDigest(publicKeys),
    ]),
  );
}

/// Seat-proof message: "zaghlol-seat-v1" 00 op 00 installId 00 challenge.
/// [challenge] is 32 bytes: verify = SHA-256(signedTransaction),
/// restore = bodyHash, signin = SHA-256(raw nonce); see the helpers below.
Uint8List seatMessage(SeatOp op, String installId, Uint8List challenge) {
  if (challenge.length != 32) {
    throw const BindingException(BindingFailure.invalidInput);
  }
  return _join([
    utf8.encode(seatPrefix),
    _nul,
    utf8.encode(op.name),
    _nul,
    utf8.encode(_checkedInstallId(installId)),
    _nul,
    challenge,
  ]);
}

Uint8List verifySeatChallenge(String signedTransaction) =>
    sha256Bytes(utf8.encode(signedTransaction));

Uint8List signinSeatChallenge(String rawNonce) =>
    sha256Bytes(utf8.encode(rawNonce));
