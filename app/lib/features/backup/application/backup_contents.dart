// T-149 (design note §1): the plaintext layout inside the encrypted backup
// stream, contents version 1.
//
//   contents = entry(db.snapshot) ‖ entry(settings.json) ‖ entry(manifest.json)
//   entry    = nameLen u8 ‖ name (ASCII) ‖ size u64 BE ‖ bytes
//
// `db.snapshot` is an SQLCipher file keyed with K_snap: the decoder writes
// it to disk only after checking it does not start with the plaintext SQLite
// magic, so no plaintext page is ever written. The two JSON entries are
// small, capped and kept in memory. Every malformation is corruptContents.
// Pure Dart (dart:io for the snapshot file). Nothing here logs.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../crypto/byte_reader.dart';
import 'backup_snapshot_exception.dart';

const String snapshotEntryName = 'db.snapshot';
const String settingsEntryName = 'settings.json';
const String manifestEntryName = 'manifest.json';

/// The entries, in their only allowed order.
const List<String> contentsEntryNames = [
  snapshotEntryName,
  settingsEntryName,
  manifestEntryName,
];

const int minSnapshotBytes = 4096;
const int maxSnapshotBytes = 16 << 30;
const int maxSettingsBytes = 1 << 20;
const int maxManifestBytes = 64 << 10;
const int _maxTables = 256;
const int _maxSettings = 4096;

/// The first 16 bytes of a plaintext SQLite file.
final Uint8List sqlitePlaintextMagic = Uint8List.fromList(
  const AsciiEncoder().convert('SQLite format 3\u0000'),
);

BackupSnapshotException _corrupt() =>
    BackupSnapshotException(BackupSnapshotErrorCode.corruptContents);

final RegExp _tableName = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
final RegExp _settingKey = RegExp(r'^[a-z0-9_.]{1,64}$');

/// `manifest.json`.
final class SnapshotManifest {
  SnapshotManifest({
    required this.contentsVersion,
    required this.schemaVersion,
    required this.snapshotBytes,
    required this.settingsBytes,
    required Map<String, int> tables,
  }) : tables = Map.unmodifiable(tables);

  final int contentsVersion;
  final int schemaVersion;
  final int snapshotBytes;
  final int settingsBytes;

  /// Row count per (non-virtual) table of the snapshot.
  final Map<String, int> tables;

  static const int version = 1;

  Uint8List encode() {
    final sorted = tables.keys.toList()..sort();
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'v': version,
          'contentsVersion': contentsVersion,
          'schemaVersion': schemaVersion,
          'snapshotBytes': snapshotBytes,
          'settingsBytes': settingsBytes,
          'tables': {for (final t in sorted) t: tables[t]},
        }),
      ),
    );
  }

  /// Strict: exactly these keys, integer values, bounded.
  static SnapshotManifest decode(Uint8List bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on Object {
      throw _corrupt();
    }
    if (json is! Map<String, Object?>) throw _corrupt();
    const keys = {
      'v',
      'contentsVersion',
      'schemaVersion',
      'snapshotBytes',
      'settingsBytes',
      'tables',
    };
    if (json.length != keys.length || !json.keys.every(keys.contains)) {
      throw _corrupt();
    }
    int nat(Object? v) => v is int && v >= 0 ? v : throw _corrupt();
    if (json['v'] != version) throw _corrupt();
    final tables = json['tables'];
    if (tables is! Map<String, Object?> || tables.length > _maxTables) {
      throw _corrupt();
    }
    return SnapshotManifest(
      contentsVersion: nat(json['contentsVersion']),
      schemaVersion: nat(json['schemaVersion']),
      snapshotBytes: nat(json['snapshotBytes']),
      settingsBytes: nat(json['settingsBytes']),
      tables: {
        for (final e in tables.entries)
          (_tableName.hasMatch(e.key) ? e.key : throw _corrupt()): nat(e.value),
      },
    );
  }
}

/// `settings.json`: the snapshot's `settings` table (the settings manifest).
Uint8List encodeSettings(Map<String, String> settings) {
  final sorted = settings.keys.toList()..sort();
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'settings': {for (final k in sorted) k: settings[k]},
      }),
    ),
  );
}

/// Strict inverse of [encodeSettings].
Map<String, String> decodeSettings(Uint8List bytes) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw _corrupt();
  }
  if (json is! Map<String, Object?> ||
      json.length != 2 ||
      json['v'] != 1 ||
      json['settings'] is! Map<String, Object?>) {
    throw _corrupt();
  }
  final s = json['settings']! as Map<String, Object?>;
  if (s.length > _maxSettings) throw _corrupt();
  return {
    for (final e in s.entries)
      if (_settingKey.hasMatch(e.key) && e.value is String)
        e.key: e.value! as String
      else
        e.key: throw _corrupt(),
  };
}

Uint8List _entryHeader(String name, int size) {
  final n = ascii.encode(name);
  final out = ByteData(1 + n.length + 8)
    ..setUint8(0, n.length)
    ..setUint64(1 + n.length, size);
  final bytes = out.buffer.asUint8List()..setRange(1, 1 + n.length, n);
  return bytes;
}

/// The contents stream. [snapshot] must hold exactly [snapshotBytes] bytes
/// (checked while streaming; a change is io). Reads the file in 1 MiB
/// pieces.
Stream<List<int>> encodeContents({
  required File snapshot,
  required int snapshotBytes,
  required Uint8List settings,
  required Uint8List manifest,
}) async* {
  yield _entryHeader(snapshotEntryName, snapshotBytes);
  var sent = 0;
  final raf = await snapshot.open();
  try {
    while (true) {
      final piece = await raf.read(1 << 20);
      if (piece.isEmpty) break;
      sent += piece.length;
      if (sent > snapshotBytes) break;
      yield piece;
    }
  } finally {
    await raf.close();
  }
  if (sent != snapshotBytes) {
    throw BackupSnapshotException(BackupSnapshotErrorCode.io);
  }
  yield _entryHeader(settingsEntryName, settings.length);
  yield settings;
  yield _entryHeader(manifestEntryName, manifest.length);
  yield manifest;
}

/// The decoded small entries; the snapshot went to the caller's file.
final class DecodedContents {
  DecodedContents({
    required this.snapshotBytes,
    required this.settingsBytes,
    required this.settings,
    required this.manifestBytes,
  });

  final int snapshotBytes;
  final Uint8List settingsBytes;
  final Map<String, String> settings;
  final Uint8List manifestBytes;
}

/// Reads [plaintext] (untrusted until the decrypt session's `done`) and
/// writes the snapshot entry to [snapshotOut] (created; must not exist).
/// Throws corruptContents on any malformation, io on a file error; a source
/// error surfaces as BackupCryptoException(io): the caller then reports the
/// session's own error. The caller deletes [snapshotOut] on failure.
Future<DecodedContents> decodeContents(
  Stream<List<int>> plaintext,
  File snapshotOut,
) async {
  final reader = ByteReader(plaintext);
  try {
    final snapSize = await _readEntryHeader(
      reader,
      snapshotEntryName,
      minSnapshotBytes,
      maxSnapshotBytes,
    );
    final RandomAccessFile out;
    try {
      out = await snapshotOut.open(mode: FileMode.writeOnly);
    } on FileSystemException {
      throw BackupSnapshotException(BackupSnapshotErrorCode.io);
    }
    try {
      var left = snapSize;
      var first = true;
      while (left > 0) {
        final piece = await reader.read(left < (1 << 20) ? left : 1 << 20);
        if (piece.isEmpty) throw _corrupt();
        if (first) {
          // Never write a plaintext SQLite file (design note §1).
          if (piece.length < sqlitePlaintextMagic.length) throw _corrupt();
          var plain = true;
          for (var i = 0; i < sqlitePlaintextMagic.length; i++) {
            if (piece[i] != sqlitePlaintextMagic[i]) plain = false;
          }
          if (plain) throw _corrupt();
          first = false;
        }
        try {
          await out.writeFrom(piece);
        } on FileSystemException {
          throw BackupSnapshotException(BackupSnapshotErrorCode.io);
        }
        left -= piece.length;
      }
      try {
        await out.flush();
      } on FileSystemException {
        throw BackupSnapshotException(BackupSnapshotErrorCode.io);
      }
    } finally {
      await out.close();
    }
    final settingsSize = await _readEntryHeader(
      reader,
      settingsEntryName,
      2,
      maxSettingsBytes,
    );
    final settingsBytes = await _readExact(reader, settingsSize);
    final manifestSize = await _readEntryHeader(
      reader,
      manifestEntryName,
      2,
      maxManifestBytes,
    );
    final manifestBytes = await _readExact(reader, manifestSize);
    if (!await reader.atEnd) throw _corrupt();
    return DecodedContents(
      snapshotBytes: snapSize,
      settingsBytes: settingsBytes,
      settings: decodeSettings(settingsBytes),
      manifestBytes: manifestBytes,
    );
  } finally {
    await reader.cancel();
  }
}

Future<Uint8List> _readExact(ByteReader reader, int n) async {
  final b = await reader.read(n);
  if (b.length != n) throw _corrupt();
  return b;
}

Future<int> _readEntryHeader(
  ByteReader reader,
  String name,
  int min,
  int max,
) async {
  final len = await _readExact(reader, 1);
  final expected = ascii.encode(name);
  if (len[0] != expected.length) throw _corrupt();
  final got = await _readExact(reader, expected.length);
  for (var i = 0; i < expected.length; i++) {
    if (got[i] != expected[i]) throw _corrupt();
  }
  final size = ByteData.sublistView(await _readExact(reader, 8)).getUint64(0);
  // getUint64 wraps above 2^63 to a negative int: refused by the bounds.
  if (size < min || size > max) throw _corrupt();
  return size;
}
