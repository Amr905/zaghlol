// T-030: the seed is declared as an app asset and the bundle's copy is the
// one tools/catalog_build wrote (the pubspec lists assets/catalog/).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/catalog/catalog_seed_loader.dart';
import 'package:zaghlol_catalog/zaghlol_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the asset bundle serves the signed seed', () async {
    const source = AssetCatalogSeedSource();
    final gz = await source.readGzip();
    final sig = await source.readSignature();
    expect(gz, File('assets/catalog/catalog_seed.json.gz').readAsBytesSync());
    final json = Uint8List.fromList(gzip.decode(gz));
    expect(verifySeedSignature(json, sig, bundledSeedKeys()), 's0000d');
    expect(CatalogSeed.decode(json).categories.length, 14);
  });
}
