// T-021: one diagnostic event. Built only from allow-listed parts, so no
// free-text String can be put into it (`DiagEvent(code: 'x')` does not compile).

import '../db/daos/misc_daos.dart' show DiagLevel;
import 'diag_code.dart';
import 'diag_field.dart';

final class DiagEvent {
  const DiagEvent({
    required this.level,
    required this.code,
    this.fields = const [],
  });

  final DiagLevel level;
  final DiagCode code;
  final List<DiagField> fields;

  /// The stored JSON object, `{wire key: int | shape-checked string}`.
  Map<String, Object?> toFieldsJson() => {
    for (final f in fields) f.key.wire: f.value,
  };
}
