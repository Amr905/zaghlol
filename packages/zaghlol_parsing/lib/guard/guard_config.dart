import 'dart:convert';

import 'package:zaghlol_domain/zaghlol_domain.dart' show SafeException;

import '../normalize/text_normalizer.dart';
import '../registry/guard_export.dart'
    show guardConfigVersion, maxGuardConfigBytes;
import '../registry/portable_regex.dart';
import 'guard_policy.dart';
import 'guard_types.dart';

/// User config schema version (platform-channels §1.1).
const int guardUserConfigVersion = 1;

/// Size and count caps of the user part (platform-channels §1.1).
const int maxGuardUserConfigBytes = 64 * 1024;
const int maxGuardIgnoreRules = 1000;
const int maxGuardUserSenders = 200;

/// Caps on the base part beyond its byte size: a corrupted or hostile file
/// can not make the reader allocate or compile without bound.
const int maxGuardBaseBytes = maxGuardConfigBytes;
const int maxGuardBaseListLength = 5000;
const int maxGuardPatternLength = 600;
const int maxGuardValueLength = 256;

/// What went wrong reading a config part. Carries a code and a JSON path
/// only, never a value: the user part holds institution + last-4 pairs,
/// which are financial data (T-035 §8).
final class GuardConfigError {
  const GuardConfigError(this.code, this.path);

  final GuardConfigErrorCode code;

  /// JSON path such as `ignore[3].last4`. Built from fixed key names and
  /// indexes only.
  final String path;

  @override
  String toString() => 'GuardConfigError(${code.name} at $path)';
}

enum GuardConfigErrorCode {
  tooLarge,
  invalidUtf8,
  invalidJson,
  wrongType,
  unknownKey,
  missingKey,
  badValue,
  badVersion,
  badRegex,
  tooMany,
}

/// Which parts of the config the Guard runs with.
enum GuardConfigMode {
  /// Base and user parts.
  full,

  /// Base only: the user part is absent (fresh install; normal) or unusable
  /// (diag `CONFIG_INVALID`, PO Q1).
  baseOnly,

  /// The base part is unusable: every message is dropped `config_invalid`.
  invalid,
}

/// One ignore rule `(inst, last4|null, ch)`.
typedef GuardIgnoreKey = (String inst, String? last4, GuardIgnoreChannel ch);

/// A parsed, compiled Guard config. Immutable.
final class GuardConfig {
  GuardConfig._({
    required this.registryVersion,
    required this.exactSenders,
    required this.senderRegexes,
    required this.packages,
    required this.wallet,
    required this.globalDrop,
    required this.dropByInst,
    required this.last4ByInst,
    required this.last4Any,
    required this.senderHints,
    required this.bodyHints,
    required this.alwaysCapture,
    required this.shortcutKeywords,
    required this.perSenderPerMin,
    required this.ignore,
    required this.userSenders,
  });

  final int registryVersion;

  /// Folded sender id to institution code.
  final Map<String, String> exactSenders;
  final List<(RegExp, String)> senderRegexes;

  /// Trimmed package name to institution code.
  final Map<String, String> packages;

  /// Folded wallet card name and institution code, in file order.
  final List<(String, String)> wallet;
  final List<RegExp> globalDrop;
  final Map<String, List<RegExp>> dropByInst;
  final Map<String, List<RegExp>> last4ByInst;
  final List<RegExp> last4Any;
  final List<RegExp> senderHints;
  final List<RegExp> bodyHints;
  final Set<String> alwaysCapture;
  final List<String> shortcutKeywords;
  final int perSenderPerMin;

  /// User part (empty in `baseOnly` mode).
  final Set<GuardIgnoreKey> ignore;

  /// `(channel wire, source key)` of user senders.
  final Set<(String, String)> userSenders;

  GuardConfig _withUser(_UserPart user) => GuardConfig._(
    registryVersion: registryVersion,
    exactSenders: exactSenders,
    senderRegexes: senderRegexes,
    packages: packages,
    wallet: wallet,
    globalDrop: globalDrop,
    dropByInst: dropByInst,
    last4ByInst: last4ByInst,
    last4Any: last4Any,
    senderHints: senderHints,
    bodyHints: bodyHints,
    alwaysCapture: alwaysCapture,
    shortcutKeywords: shortcutKeywords,
    perSenderPerMin: perSenderPerMin,
    ignore: user.ignore,
    userSenders: user.senders,
  );
}

/// The outcome of [parseGuardConfig].
final class GuardConfigLoad {
  const GuardConfigLoad(
    this.mode,
    this.config, {
    this.baseError,
    this.userError,
  });

  final GuardConfigMode mode;

  /// Null exactly when [mode] is [GuardConfigMode.invalid].
  final GuardConfig? config;
  final GuardConfigError? baseError;

  /// Set when a user part was given but could not be used. The caller
  /// reports diag `CONFIG_INVALID` (code only).
  final GuardConfigError? userError;
}

/// The source key the Guard compares on [channel]: the trimmed source for
/// `notification` (package names are case-sensitive identifiers), the
/// `foldKey` of the source otherwise.
String guardSourceKey(GuardChannel channel, String source) =>
    channel == GuardChannel.notification ? source.trim() : foldKey(source);

/// Parses the base part and the optional user part (both raw bytes as read
/// from disk / decrypted). Pure; never throws.
///
/// - Base unusable → [GuardConfigMode.invalid].
/// - User absent → [GuardConfigMode.baseOnly].
/// - User unusable → per [kGuardUserConfigFailure] (PO Q1): `baseOnly` with
///   [GuardConfigLoad.userError] set, or `invalid`.
GuardConfigLoad parseGuardConfig(List<int> baseBytes, [List<int>? userBytes]) {
  GuardConfig? base;
  try {
    base = _parseBase(baseBytes);
  } on _ConfigFailure catch (f) {
    return GuardConfigLoad(GuardConfigMode.invalid, null, baseError: f.error);
  } on Object {
    return const GuardConfigLoad(
      GuardConfigMode.invalid,
      null,
      baseError: GuardConfigError(GuardConfigErrorCode.badValue, r'$'),
    );
  }
  if (userBytes == null) {
    return GuardConfigLoad(GuardConfigMode.baseOnly, base);
  }
  GuardConfigError userError;
  try {
    final user = _parseUser(userBytes);
    return GuardConfigLoad(GuardConfigMode.full, base._withUser(user));
  } on _ConfigFailure catch (f) {
    userError = f.error;
  } on Object {
    userError = const GuardConfigError(GuardConfigErrorCode.badValue, r'$');
  }
  return switch (kGuardUserConfigFailure) {
    GuardUserConfigFailure.keepWithBase => GuardConfigLoad(
      GuardConfigMode.baseOnly,
      base,
      userError: userError,
    ),
    GuardUserConfigFailure.dropAll => GuardConfigLoad(
      GuardConfigMode.invalid,
      null,
      userError: userError,
    ),
  };
}

/// Internal control flow only: caught in this file and turned into a
/// [GuardConfigError]. Carries an error code and a JSON path, never content.
final class _ConfigFailure extends SafeException {
  _ConfigFailure(this.error) : super('GUARD_CONFIG_INVALID');
  final GuardConfigError error;
}

Never _fail(GuardConfigErrorCode code, String path) =>
    throw _ConfigFailure(GuardConfigError(code, path));

Map<String, Object?> _decode(List<int> bytes, int maxBytes) {
  if (bytes.length > maxBytes) {
    _fail(GuardConfigErrorCode.tooLarge, r'$');
  }
  final String text;
  try {
    text = const Utf8Decoder(allowMalformed: false).convert(bytes);
  } on FormatException {
    _fail(GuardConfigErrorCode.invalidUtf8, r'$');
  }
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    _fail(GuardConfigErrorCode.invalidJson, r'$');
  }
  if (json is! Map<String, Object?>) {
    _fail(GuardConfigErrorCode.wrongType, r'$');
  }
  return json;
}

/// Strict object reader: every key must be read, unknown keys fail.
final class _Obj {
  _Obj(this.path, this.map);

  final String path;
  final Map<String, Object?> map;
  final Set<String> _read = {};

  Object? _get(String key) {
    _read.add(key);
    if (!map.containsKey(key)) {
      _fail(GuardConfigErrorCode.missingKey, '$path.$key');
    }
    return map[key];
  }

  int integer(String key, {int min = 0, int max = 1 << 30}) {
    final v = _get(key);
    if (v is! int) {
      _fail(GuardConfigErrorCode.wrongType, '$path.$key');
    }
    if (v < min || v > max) {
      _fail(GuardConfigErrorCode.badValue, '$path.$key');
    }
    return v;
  }

  String string(String key, {int maxLength = maxGuardValueLength}) {
    final v = _get(key);
    if (v is! String) {
      _fail(GuardConfigErrorCode.wrongType, '$path.$key');
    }
    if (v.isEmpty || v.length > maxLength) {
      _fail(GuardConfigErrorCode.badValue, '$path.$key');
    }
    return v;
  }

  String? nullableString(String key) {
    final v = _get(key);
    if (v == null) {
      return null;
    }
    if (v is! String) {
      _fail(GuardConfigErrorCode.wrongType, '$path.$key');
    }
    return v;
  }

  List<Object?> list(String key, int maxLength) {
    final v = _get(key);
    if (v is! List<Object?>) {
      _fail(GuardConfigErrorCode.wrongType, '$path.$key');
    }
    if (v.length > maxLength) {
      _fail(GuardConfigErrorCode.tooMany, '$path.$key');
    }
    return v;
  }

  _Obj object(String key) {
    final v = _get(key);
    if (v is! Map<String, Object?>) {
      _fail(GuardConfigErrorCode.wrongType, '$path.$key');
    }
    return _Obj('$path.$key', v);
  }

  List<String> strings(String key, {int maxLength = maxGuardValueLength}) {
    final raw = list(key, maxGuardBaseListLength);
    return [
      for (var i = 0; i < raw.length; i++)
        _stringAt(raw[i], '$path.$key[$i]', maxLength),
    ];
  }

  List<RegExp> patterns(String key) {
    final texts = strings(key, maxLength: maxGuardPatternLength);
    return [
      for (var i = 0; i < texts.length; i++)
        _compile(texts[i], '$path.$key[$i]'),
    ];
  }

  void finish() {
    for (final key in map.keys) {
      if (!_read.contains(key)) {
        // The key name itself is not echoed: it may be anything.
        _fail(GuardConfigErrorCode.unknownKey, path);
      }
    }
  }
}

String _stringAt(Object? v, String path, int maxLength) {
  if (v is! String) {
    _fail(GuardConfigErrorCode.wrongType, path);
  }
  if (v.isEmpty || v.length > maxLength) {
    _fail(GuardConfigErrorCode.badValue, path);
  }
  return v;
}

_Obj _objAt(Object? v, String path) {
  if (v is! Map<String, Object?>) {
    _fail(GuardConfigErrorCode.wrongType, path);
  }
  return _Obj(path, v);
}

RegExp _compile(String text, String path) {
  try {
    return compileGuardPattern(text);
  } on FormatException {
    _fail(GuardConfigErrorCode.badRegex, path);
  }
}

final RegExp _instShape = RegExp(r'^[a-z][a-z0-9_]{1,31}$');
final RegExp _last4Shape = RegExp(r'^[0-9]{4}$');

String _inst(_Obj o, String key) {
  final v = o.string(key);
  if (!_instShape.hasMatch(v)) {
    _fail(GuardConfigErrorCode.badValue, '${o.path}.$key');
  }
  return v;
}

GuardConfig _parseBase(List<int> bytes) {
  final r = _Obj(r'$', _decode(bytes, maxGuardBaseBytes));
  if (r.integer('v') != guardConfigVersion) {
    _fail(GuardConfigErrorCode.badVersion, r'$.v');
  }
  final registryVersion = r.integer('registryVersion');

  final exact = <String, String>{};
  final regexes = <(RegExp, String)>[];
  final senders = r.list('senders', maxGuardBaseListLength);
  for (var i = 0; i < senders.length; i++) {
    final o = _objAt(
      senders[i],
      r'$.senders'
      '[$i]',
    );
    final match = o.string('match');
    final inst = _inst(o, 'inst');
    if (match == 'exact') {
      final key = foldKey(o.string('value'));
      if (key.isEmpty) {
        _fail(GuardConfigErrorCode.badValue, '${o.path}.value');
      }
      exact.putIfAbsent(key, () => inst);
    } else if (match == 'regex') {
      final text = o.string('value', maxLength: maxGuardPatternLength);
      regexes.add((_compile(text, '${o.path}.value'), inst));
    } else {
      _fail(GuardConfigErrorCode.badValue, '${o.path}.match');
    }
    o.finish();
  }

  final packages = <String, String>{};
  final pkgs = r.list('packages', maxGuardBaseListLength);
  for (var i = 0; i < pkgs.length; i++) {
    final o = _objAt(
      pkgs[i],
      r'$.packages'
      '[$i]',
    );
    packages.putIfAbsent(o.string('value').trim(), () => _inst(o, 'inst'));
    o.finish();
  }

  final wallet = <(String, String)>[];
  final cards = r.list('wallet', maxGuardBaseListLength);
  for (var i = 0; i < cards.length; i++) {
    final o = _objAt(
      cards[i],
      r'$.wallet'
      '[$i]',
    );
    final name = foldKey(o.string('name'));
    if (name.isEmpty) {
      _fail(GuardConfigErrorCode.badValue, '${o.path}.name');
    }
    wallet.add((name, _inst(o, 'inst')));
    o.finish();
  }

  final drop = r.object('drop');
  final globalDrop = drop.patterns('global');
  final byInstObj = drop.object('byInst');
  final dropByInst = <String, List<RegExp>>{};
  for (final key in byInstObj.map.keys.toList()) {
    if (!_instShape.hasMatch(key)) {
      _fail(GuardConfigErrorCode.badValue, byInstObj.path);
    }
    dropByInst[key] = byInstObj.patterns(key);
  }
  byInstObj.finish();
  drop.finish();

  final last4Obj = r.object('last4');
  final last4ByInst = <String, List<RegExp>>{};
  var last4Any = <RegExp>[];
  for (final key in last4Obj.map.keys.toList()) {
    if (key == '*') {
      last4Any = last4Obj.patterns(key);
    } else if (_instShape.hasMatch(key)) {
      last4ByInst[key] = last4Obj.patterns(key);
    } else {
      _fail(GuardConfigErrorCode.badValue, last4Obj.path);
    }
  }
  last4Obj.finish();

  final generic = r.object('generic');
  final senderHints = generic.patterns('senderHints');
  final bodyHints = generic.patterns('bodyHints');
  final always = {for (final a in generic.strings('alwaysCapture')) foldKey(a)}
    ..remove('');
  generic.finish();

  final keywords = r.strings('shortcutKeywords');
  final rate = r.object('rate');
  final perMin = rate.integer('perSenderPerMin', min: 1, max: 10000);
  rate.finish();
  r.finish();

  return GuardConfig._(
    registryVersion: registryVersion,
    exactSenders: exact,
    senderRegexes: regexes,
    packages: packages,
    wallet: wallet,
    globalDrop: globalDrop,
    dropByInst: dropByInst,
    last4ByInst: last4ByInst,
    last4Any: last4Any,
    senderHints: senderHints,
    bodyHints: bodyHints,
    alwaysCapture: always,
    shortcutKeywords: keywords,
    perSenderPerMin: perMin,
    ignore: const {},
    userSenders: const {},
  );
}

final class _UserPart {
  const _UserPart(this.ignore, this.senders);
  final Set<GuardIgnoreKey> ignore;
  final Set<(String, String)> senders;
}

/// Channels a user sender may name.
const Set<GuardChannel> guardUserSenderChannels = {
  GuardChannel.sms,
  GuardChannel.notification,
  GuardChannel.shortcutMessage,
  GuardChannel.applePay,
};

_UserPart _parseUser(List<int> bytes) {
  final r = _Obj(r'$', _decode(bytes, maxGuardUserConfigBytes));
  if (r.integer('v') != guardUserConfigVersion) {
    _fail(GuardConfigErrorCode.badVersion, r'$.v');
  }
  r.integer('baseRegistryVersion');
  final ignore = <GuardIgnoreKey>{};
  final rules = r.list('ignore', maxGuardIgnoreRules);
  for (var i = 0; i < rules.length; i++) {
    final o = _objAt(
      rules[i],
      r'$.ignore'
      '[$i]',
    );
    final inst = _inst(o, 'inst');
    final last4 = o.nullableString('last4');
    if (last4 != null && !_last4Shape.hasMatch(last4)) {
      _fail(GuardConfigErrorCode.badValue, '${o.path}.last4');
    }
    final ch = GuardIgnoreChannel.fromWire(o.string('ch'));
    if (ch == null) {
      _fail(GuardConfigErrorCode.badValue, '${o.path}.ch');
    }
    o.finish();
    ignore.add((inst, last4, ch));
  }
  final senders = <(String, String)>{};
  final list = r.list('userSenders', maxGuardUserSenders);
  for (var i = 0; i < list.length; i++) {
    final o = _objAt(
      list[i],
      r'$.userSenders'
      '[$i]',
    );
    final value = o.string('value');
    final ch = GuardChannel.fromWire(o.string('ch'));
    if (ch == null || !guardUserSenderChannels.contains(ch)) {
      _fail(GuardConfigErrorCode.badValue, '${o.path}.ch');
    }
    o.finish();
    final key = guardSourceKey(ch, value);
    if (key.isEmpty) {
      _fail(GuardConfigErrorCode.badValue, '${o.path}.value');
    }
    senders.add((ch.wire, key));
  }
  r.finish();
  return _UserPart(ignore, senders);
}
