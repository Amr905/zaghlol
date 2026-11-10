// T-016: byte snapshots of a directory's files, for "nothing was touched" and
// "restored byte-identical" assertions (as in T-015).

import 'dart:io';
import 'dart:typed_data';

/// Every file directly in [dir] (name → bytes).
Map<String, Uint8List> snapshotFiles(Directory dir) => {
  for (final e in dir.listSync().whereType<File>())
    e.uri.pathSegments.last: e.readAsBytesSync(),
};

bool sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool sameSnapshot(Map<String, Uint8List> a, Map<String, Uint8List> b) =>
    a.length == b.length &&
    a.keys.every((k) => b.containsKey(k) && sameBytes(a[k]!, b[k]!));
