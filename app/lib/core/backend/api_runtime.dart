// T-141: the checks the generated DTOs (generated/api_models.g.dart) call.
// Hand-written, so it is analyzed and linted; the generator only emits calls.
//
// Every failure is one code-only [ApiModelException]: the rejected value is
// never kept, printed or echoed (self-check §3, §5).

import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

/// A request DTO broke a contract constraint, or a response body did not
/// match its schema. Code only.
final class ApiModelException extends SafeException {
  ApiModelException(super.code);

  /// A request value breaks its schema (nothing was sent).
  static const String invalid = 'API_REQUEST_INVALID';

  /// A response body does not match its schema.
  static const String malformed = 'API_RESPONSE_MALFORMED';
}

/// Most items any decoded array may hold when the schema sets no maximum.
const int apiMaxItems = 10000;

Never _bad() => throw ApiModelException(ApiModelException.malformed);
Never _invalid() => throw ApiModelException(ApiModelException.invalid);

bool _lengthOk(String s, int? minLength, int? maxLength) {
  // JSON Schema counts code points, not UTF-16 units.
  if (minLength == null && maxLength == null) return true;
  final n = s.runes.length;
  return (minLength == null || n >= minLength) &&
      (maxLength == null || n <= maxLength);
}

// ---- decoding (responses) ---------------------------------------------------

Map<String, Object?> apiObject(Object? json) {
  if (json is! Map) _bad();
  final out = <String, Object?>{};
  for (final e in json.entries) {
    final k = e.key;
    if (k is! String) _bad();
    out[k] = e.value;
  }
  return out;
}

/// The value of a required member; absence is malformed.
Object? apiRequired(Map<String, Object?> m, String key) {
  if (!m.containsKey(key)) _bad();
  return m[key];
}

T? apiNullable<T>(Object? v, T Function(Object v) decode) =>
    v == null ? null : decode(v);

void apiConst(Object? v, String expected) {
  if (v != expected) _bad();
}

String apiString(Object? v, {RegExp? pattern, int? minLength, int? maxLength}) {
  if (v is! String) _bad();
  if (!_lengthOk(v, minLength, maxLength)) _bad();
  if (pattern != null && !pattern.hasMatch(v)) _bad();
  return v;
}

int apiInt(Object? v, {int? min, int? max}) {
  // A JSON number with a fraction or exponent decodes as a double: refused.
  if (v is! int) _bad();
  if ((min != null && v < min) || (max != null && v > max)) _bad();
  return v;
}

bool apiBool(Object? v) => v is bool ? v : _bad();

List<Object?> apiList(Object? v, {int? minItems, int? maxItems}) {
  if (v is! List) _bad();
  final cap = maxItems ?? apiMaxItems;
  if (v.length > cap || (minItems != null && v.length < minItems)) _bad();
  return v;
}

// ---- encoding checks (requests) --------------------------------------------

String apiCheckString(
  String v, {
  RegExp? pattern,
  int? minLength,
  int? maxLength,
}) {
  if (!_lengthOk(v, minLength, maxLength)) _invalid();
  if (pattern != null && !pattern.hasMatch(v)) _invalid();
  return v;
}

int apiCheckInt(int v, {int? min, int? max}) {
  if ((min != null && v < min) || (max != null && v > max)) _invalid();
  return v;
}

/// The wire value of an enum; `unknown` (no wire value) is never sent.
String apiCheckEnum(String? wire) => wire ?? _invalid();

List<T> apiCheckList<T>(List<T> v, {int? minItems, int? maxItems}) {
  if ((minItems != null && v.length < minItems) ||
      (maxItems != null && v.length > maxItems)) {
    _invalid();
  }
  return v;
}
