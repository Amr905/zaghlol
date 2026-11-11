// T-021: typed, allow-listed diagnostic fields. There is no field that takes
// free text: keys are the [DiagKey] enum, values are ints, durations, or one
// of a few strings checked against a strict, length-capped shape.
//
// Accepted residual: a short token that matches a shape (for example an
// institution code) is accepted. Counts are plain ints; never pass an amount
// (`*_minor`, `Money.toStorage()`) as a count.

import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

import 'diag_code.dart';

/// What a [DiagKey] holds.
enum DiagKind {
  count,
  durationMs,
  httpStatus,
  version,
  institution,
  templateId,
  errorCode,
}

/// The field names that may appear in a diagnostic event.
enum DiagKey {
  rows('rows', DiagKind.count),
  messages('messages', DiagKind.count),
  parsed('parsed', DiagKind.count),
  skipped('skipped', DiagKind.count),
  retries('retries', DiagKind.count),
  queued('queued', DiagKind.count),
  durationMs('duration_ms', DiagKind.durationMs),
  httpStatus('http_status', DiagKind.httpStatus),
  appVersion('app_version', DiagKind.version),
  registryVersion('registry_version', DiagKind.version),
  catalogVersion('catalog_version', DiagKind.version),
  schemaVersion('schema_version', DiagKind.version),
  institution('institution', DiagKind.institution),
  templateId('template_id', DiagKind.templateId),
  errorCode('error_code', DiagKind.errorCode);

  const DiagKey(this.wire, this.kind);

  /// The name in the stored JSON and in the exported text.
  final String wire;
  final DiagKind kind;

  static DiagKey? fromWire(String wire) {
    for (final k in values) {
      if (k.wire == wire) {
        return k;
      }
    }
    return null;
  }
}

/// Thrown for a field value of the wrong shape. The message is the constant
/// code; the rejected value is never kept or echoed.
final class DiagFieldException extends SafeException {
  DiagFieldException(super.code);

  static const String badValue = 'DIAG_FIELD_BAD_VALUE';
  static const String badKey = 'DIAG_FIELD_BAD_KEY';
}

/// One allow-listed field of a [DiagEvent](diag_event.dart).
final class DiagField {
  const DiagField._(this.key, this.value);

  /// A non-negative count of things (rows, messages, retries ...).
  factory DiagField.count(DiagKey key, int n) {
    _expect(key, DiagKind.count);
    if (n < 0 || n > _maxCount) {
      throw DiagFieldException(DiagFieldException.badValue);
    }
    return DiagField._(key, n);
  }

  /// A duration, stored in whole milliseconds.
  factory DiagField.duration(Duration d) {
    final ms = d.inMilliseconds;
    if (ms < 0 || ms > _maxCount) {
      throw DiagFieldException(DiagFieldException.badValue);
    }
    return DiagField._(DiagKey.durationMs, ms);
  }

  factory DiagField.httpStatus(int status) {
    if (status < 100 || status > 599) {
      throw DiagFieldException(DiagFieldException.badValue);
    }
    return DiagField._(DiagKey.httpStatus, status);
  }

  /// An app, registry, catalog or schema version such as `1.4.2+17`.
  factory DiagField.version(DiagKey key, String v) {
    _expect(key, DiagKind.version);
    return DiagField._(key, _checked(v, _versionShape));
  }

  /// An institution code such as `CIB` or `BANK_MISR`.
  factory DiagField.institution(String code) =>
      DiagField._(DiagKey.institution, _checked(code, _institutionShape));

  /// A parser template id such as `cib_debit_v2`.
  factory DiagField.templateId(String id) => DiagField._(
    DiagKey.templateId,
    _checked(id, _templateShape, rejectLongRun: true),
  );

  /// The code of an error (a registry code or a [SafeException] code).
  factory DiagField.errorCode(DiagCode code) =>
      DiagField._(DiagKey.errorCode, code.value);

  /// Re-validates a stored `key: value` pair (export). `null` when the key is
  /// unknown or the value does not have the shape the key requires.
  static DiagField? tryFromStored(String wireKey, Object? raw) {
    final key = DiagKey.fromWire(wireKey);
    if (key == null) {
      return null;
    }
    final ok = switch (key.kind) {
      DiagKind.count ||
      DiagKind.durationMs => raw is int && raw >= 0 && raw <= _maxCount,
      DiagKind.httpStatus => raw is int && raw >= 100 && raw <= 599,
      DiagKind.version => raw is String && _versionShape.hasMatch(raw),
      DiagKind.institution => raw is String && _institutionShape.hasMatch(raw),
      DiagKind.templateId => raw is String && _isTemplate(raw),
      DiagKind.errorCode => DiagCode.tryFromStored(raw) != null,
    };
    return ok ? DiagField._(key, raw!) : null;
  }

  static const int _maxCount = 1000000000;
  static final RegExp _versionShape = RegExp(
    r'^[0-9]{1,6}(\.[0-9]{1,6}){0,3}([+-][0-9A-Za-z.]{1,16})?$',
  );
  static final RegExp _institutionShape = RegExp(r'^[A-Z][A-Z0-9_]{1,15}$');
  static final RegExp _templateShape = RegExp(r'^[a-z][a-z0-9_.-]{1,39}$');
  // A template id is made of short words; a long unbroken run looks like a
  // token or key, so it is refused.
  static final RegExp _longRun = RegExp(r'[a-z0-9]{13,}');

  static void _expect(DiagKey key, DiagKind kind) {
    if (key.kind != kind) throw DiagFieldException(DiagFieldException.badKey);
  }

  static bool _isTemplate(String v) =>
      _templateShape.hasMatch(v) && !_longRun.hasMatch(v);

  static String _checked(String v, RegExp shape, {bool rejectLongRun = false}) {
    if (!shape.hasMatch(v) || (rejectLongRun && _longRun.hasMatch(v))) {
      throw DiagFieldException(DiagFieldException.badValue);
    }
    return v;
  }

  final DiagKey key;

  /// An `int` or a shape-checked `String`.
  final Object value;
}
