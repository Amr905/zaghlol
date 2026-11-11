// T-018: probes of the FTS5 tables' shadow tables (`_config`, `_data`),
// shared by the host and device tests of FTS5 secure-delete (T-017 review
// S-2). They return booleans and numbers only; nothing is printed.

import 'dart:typed_data';

import 'package:zaghlol/core/db/app_database.dart';

/// The `secure-delete` value of [table] (null: never set).
Future<int?> secureDeleteOf(AppDatabase db, String table) async {
  final row = await db
      .customSelect("SELECT v FROM ${table}_config WHERE k = 'secure-delete'")
      .getSingleOrNull();
  return row?.read<int>('v');
}

/// Whether any `_data` blob of [table] still holds [needle]'s bytes.
Future<bool> dataHolds(AppDatabase db, String table, String needle) async {
  final bytes = needle.codeUnits;
  for (final r
      in await db.customSelect('SELECT block FROM ${table}_data').get()) {
    final block = r.read<Uint8List?>('block');
    if (block == null) continue;
    for (var i = 0; i + bytes.length <= block.length; i++) {
      var hit = true;
      for (var j = 0; j < bytes.length; j++) {
        if (block[i + j] != bytes[j]) {
          hit = false;
          break;
        }
      }
      if (hit) return true;
    }
  }
  return false;
}
