// T-030: the catalog_build command line.
//
//   dart run catalog_build --input data/catalog_curated.csv \
//     --out ../../app/assets/catalog --csv-out data/catalog_seed.csv \
//     [--version 1] [--key dev/dev_signing_key.json] [--check]
//
// Writes catalog_seed.json.gz (the canonical seed JSON, gzip) and
// catalog_seed.json.sig (the `Zaghlol-Signature` header over the JSON bytes),
// and the normalized CSV for the backend import (T-125). With --check it
// writes nothing and exits 1 when a committed output differs from a rebuild.
// Signing is deterministic, so an unchanged input gives identical output.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:zaghlol_catalog/zaghlol_catalog.dart';

import 'builder.dart';

const String seedGzName = 'catalog_seed.json.gz';
const String seedSigName = 'catalog_seed.json.sig';

/// Runs the CLI; returns the exit code (0 ok, 1 build failed or --check
/// differs, 2 usage).
Future<int> runCatalogBuild(
  List<String> args,
  StringSink out,
  StringSink err,
) async {
  String? input;
  String? outDir;
  String? csvOut;
  String? keyFile;
  var version = 1;
  var check = false;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String? value() => i + 1 < args.length ? args[++i] : null;
    switch (a) {
      case '--input':
        input = value();
      case '--out':
        outDir = value();
      case '--csv-out':
        csvOut = value();
      case '--key':
        keyFile = value();
      case '--version':
        version = int.tryParse(value() ?? '') ?? -1;
      case '--check':
        check = true;
      default:
        err.writeln('unknown argument: $a');
        return 2;
    }
  }
  if (input == null || outDir == null || keyFile == null || version < 1) {
    err.writeln(
      'usage: catalog_build --input <curated.csv> --out <dir> '
      '--key <key.json> [--csv-out <file>] [--version <n>] [--check]',
    );
    return 2;
  }

  final BuiltCatalog built;
  final SeedSigner signer;
  try {
    built = buildCatalog(File(input).readAsStringSync(), version: version);
    final jwk = jsonDecode(File(keyFile).readAsStringSync());
    final kid = jwk['kid'] as String;
    // Never read a production key from a file: only dev kids (S-1).
    if (!RegExp(r'^s0000[a-z]$').hasMatch(kid)) {
      err.writeln('--key accepts only a dev key (kid s0000x)');
      return 1;
    }
    signer = SeedSigner(
      kid: kid,
      d: Uint8List.fromList(
        base64Url.decode(base64Url.normalize(jwk['d'] as String)),
      ),
    );
  } on CatalogBuildException catch (e) {
    err.writeln(e.message);
    return 1;
  } on Object {
    err.writeln('could not read the input or the key file');
    return 1;
  }

  final json = built.seed.encode();
  final header = signer.sign(json);
  final outputs = <String, List<int>>{
    '$outDir/$seedGzName': gzip.encode(json),
    '$outDir/$seedSigName': ascii.encode('$header\n'),
    ?csvOut: utf8.encode(built.normalizedCsv),
  };

  if (check) {
    var stale = false;
    for (final MapEntry(key: path, value: bytes) in outputs.entries) {
      final f = File(path);
      final same =
          f.existsSync() && _sameContent(path, f.readAsBytesSync(), bytes);
      if (!same) {
        err.writeln('out of date: $path');
        stale = true;
      }
    }
    return stale ? 1 : 0;
  }

  Directory(outDir).createSync(recursive: true);
  for (final MapEntry(key: path, value: bytes) in outputs.entries) {
    File(path).writeAsBytesSync(bytes);
  }
  out.writeln(
    'seed v$version: ${built.seed.categories.length} categories, '
    '${built.seed.merchants.length} merchants, '
    '${built.seed.aliases.length} aliases, '
    '${built.seed.keywords.length} keywords (${json.length} bytes)',
  );
  return 0;
}

/// gzip bytes depend on the zlib build and the OS byte, so a .gz is compared
/// by its decompressed content.
bool _sameContent(String path, List<int> existing, List<int> expected) {
  if (!path.endsWith('.gz')) {
    return _eq(existing, expected);
  }
  try {
    return _eq(gzip.decode(existing), gzip.decode(expected));
  } on Object {
    return false;
  }
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
