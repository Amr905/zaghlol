// T-020: a typed key into the `settings` table (database-schema §2.8).
//
// A key knows its name, its default, how to read its stored text and how to
// write it. A stored value that doesn't decode (corrupt, out of range, from a
// newer app) reads as the default; it is never thrown and never echoed.
// A value that doesn't survive its own round trip is refused on write.
// Nothing here logs.

import 'package:zaghlol_domain/zaghlol_domain.dart';

/// Refusal of a setting write. Code only: never the key's value.
final class SettingsException extends SafeException {
  SettingsException(super.code);

  /// The value is outside the setting's range.
  static const String invalidValue = 'SETTING_INVALID_VALUE';
}

final class SettingKey<T> {
  const SettingKey._(this.name, this.defaultValue, this._decode, this._encode);

  /// The `settings.key` (1–64 of `[a-z0-9_.]`).
  final String name;

  /// What the setting reads as while unset or unreadable.
  final T defaultValue;

  final T? Function(String stored) _decode;
  final String Function(T value) _encode;

  /// The stored text as a value; the default for null, or an invalid text.
  T parse(String? stored) {
    if (stored == null) return defaultValue;
    return _decode(stored) ?? defaultValue;
  }

  /// The text to store for [value]; throws [SettingsException] when [value]
  /// is out of range (it would not read back as itself).
  String format(T value) {
    final text = _encode(value);
    final back = _decode(text);
    if (back == null || _encode(back) != text) {
      throw SettingsException(SettingsException.invalidValue);
    }
    return text;
  }

  static SettingKey<bool> boolean(String name, {required bool byDefault}) =>
      SettingKey._(
        name,
        byDefault,
        (s) => switch (s) {
          '1' => true,
          '0' => false,
          _ => null,
        },
        (v) => v ? '1' : '0',
      );

  static final RegExp _digits = RegExp(r'^(0|[1-9][0-9]{0,14})$');

  static int? _int(String s, int min, int max) {
    if (!_digits.hasMatch(s)) return null;
    final v = int.parse(s);
    return v < min || v > max ? null : v;
  }

  /// An integer in [min]..[max] (non-negative, at most 15 digits).
  static SettingKey<int> integer(
    String name, {
    required int byDefault,
    required int min,
    required int max,
  }) => SettingKey._(name, byDefault, (s) => _int(s, min, max), (v) => '$v');

  /// An integer in [min]..[max], null when unset (writing null unsets).
  static SettingKey<int?> optionalInteger(
    String name, {
    required int min,
    required int max,
  }) => SettingKey._(
    name,
    null,
    (s) => _int(s, min, max),
    (v) => v == null ? '' : '$v',
  );

  static SettingKey<E> enumeration<E extends Enum>(
    String name,
    List<E> values, {
    required E byDefault,
  }) => SettingKey._(name, byDefault, (s) {
    for (final v in values) {
      if (v.name == s) return v;
    }
    return null;
  }, (v) => v.name);

  /// An ISO 4217 currency code.
  static SettingKey<Currency> currency(
    String name, {
    required Currency byDefault,
  }) => SettingKey._(name, byDefault, Currency.tryOf, (v) => v.code);

  /// An amount, null when unset. Stored as `<minor>:<CODE>`.
  static SettingKey<Money?> optionalMoney(String name) =>
      SettingKey._(name, null, (s) {
        final parts = s.split(':');
        if (parts.length != 2) return null;
        final minor = int.tryParse(parts[0]);
        if (minor == null || '$minor' != parts[0]) return null;
        return Money.tryFromStorage(minor, parts[1]);
      }, (v) => v == null ? '' : '${v.minor}:${v.currency.code}');

  /// A set of `[a-z0-9_]` slugs (1–32 each, at most 64), stored sorted and
  /// comma-separated.
  static SettingKey<Set<String>> slugSet(String name) =>
      SettingKey._(name, const <String>{}, (s) {
        if (s.isEmpty) return <String>{};
        final parts = s.split(',');
        if (parts.length > 64 || parts.any((p) => !_slug.hasMatch(p))) {
          return null;
        }
        return parts.toSet();
      }, (v) => (v.toList()..sort()).join(','));

  /// The payday eras (T-051; database-schema §2.8), null when unset.
  static SettingKey<PaydaySchedule?> paydaySchedule(String name) =>
      SettingKey._(
        name,
        null,
        PaydaySchedule.tryFromJson,
        (v) => v == null ? '' : v.toJson(),
      );

  static final RegExp _slug = RegExp(r'^[a-z0-9_]{1,32}$');
}
