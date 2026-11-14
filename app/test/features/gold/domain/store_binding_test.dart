// T-145: StoreBindingRef against the shared vectors
// (backend/tests/Zaghlol.Contract.Tests/vectors/store-binding-v1.json).
// A missing vector file fails the test; it is never skipped.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/gold/domain/store_binding.dart';

Map<String, dynamic> _vectors() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final f = File(
      '${dir.path}/backend/tests/Zaghlol.Contract.Tests/vectors/'
      'store-binding-v1.json',
    );
    if (f.existsSync()) {
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    }
    dir = dir.parent;
  }
  fail('store-binding-v1.json not found');
}

void main() {
  test('reproduces every shared vector', () {
    final v = (_vectors()['vectors'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(v, isNotEmpty);
    for (final x in v) {
      expect(
        storeBindingRef(x['installId'] as String),
        x['storeBindingRef'],
        reason: x['installId'] as String,
      );
    }
  });

  test('rejects anything but a lower-case UUID, without echoing it', () {
    for (final bad in [
      '',
      'not-an-id',
      '0193F2C4-7A10-4C52-9D3E-5B1F8A2C6E77',
      '0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e7',
    ]) {
      expect(
        () => storeBindingRef(bad),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '$e',
            'text',
            isNot(contains(bad.isEmpty ? '#' : bad)),
          ),
        ),
      );
    }
  });
}
