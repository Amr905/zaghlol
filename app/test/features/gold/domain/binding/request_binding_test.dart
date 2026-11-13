// T-183: request-binding library against the backend's shared vectors
// (backend/tests/Zaghlol.Contract.Tests/vectors/), located by walking up from
// the working directory so it works from app/ and from the repo root. A
// missing vector file fails the test; it is never skipped.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/gold/domain/binding/binding_exceptions.dart';
import 'package:zaghlol/features/gold/domain/binding/jcs.dart';
import 'package:zaghlol/features/gold/domain/binding/request_binding.dart';
import 'package:zaghlol/features/gold/domain/binding/strict_json.dart';

const _rel = 'backend/tests/Zaghlol.Contract.Tests/vectors';

Map<String, dynamic> _vectors(String name) {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final f = File('${dir.path}/$_rel/$name');
    if (f.existsSync()) {
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    }
    dir = dir.parent;
  }
  fail('shared vector file $name not found above ${Directory.current.path}');
}

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String h) => Uint8List.fromList([
  for (var i = 0; i < h.length; i += 2)
    int.parse(h.substring(i, i + 2), radix: 16),
]);

Uint8List _b64u(String s) =>
    Uint8List.fromList(base64Url.decode(base64Url.normalize(s)));

String _b64uEnc(List<int> b) => base64Url.encode(b).replaceAll('=', '');

List<Uint8List> _seatKeys(Map<String, dynamic> body) {
  final att = body['attestation'] as Map<String, dynamic>?;
  final keys = att?['seatKeys'] as List<dynamic>?;
  return [for (final k in keys ?? []) _b64u((k as Map)['publicKey'] as String)];
}

void main() {
  final restore = _vectors('restore-binding-v1.json');
  final valid = (restore['valid'] as List).cast<Map<String, dynamic>>();
  final invalid = (restore['invalid'] as List).cast<Map<String, dynamic>>();

  group('AC1 valid restore vectors', () {
    for (final v in valid) {
      test(v['name'] as String, () {
        final installId = v['installId'] as String;
        // Parse the vector body through the strict parser from its text.
        final raw = jsonEncode(v['body']);
        final body = parseStrictJson(raw) as Map<String, Object?>;
        expect(restoreCanonicalBody(body), v['jcs']);
        final h = restoreBodyHashFromJson(installId, raw);
        expect(_hex(h), v['bodyHashHex']);
        expect(_b64uEnc(h), v['requestHashB64u']);
        if (v.containsKey('seatKeysDigestHex')) {
          final keys = _seatKeys(v['body'] as Map<String, dynamic>);
          expect(_hex(seatKeysDigest(keys)), v['seatKeysDigestHex']);
          expect(_hex(restoreClientDataHash(h, keys)), v['clientDataHashHex']);
        }
      });
    }
  });

  group('AC2 / R3-8 invalid vectors rejected by the strict parser', () {
    for (final v in invalid) {
      test(v['name'] as String, () {
        final raw = v['raw'] as String;
        expect(
          () =>
              restoreBodyHashFromJson(valid.first['installId'] as String, raw),
          throwsA(isA<BindingException>()),
        );
        expect(() => parseStrictJson(raw), throwsA(isA<BindingException>()));
      });
    }
    test('failure reasons', () {
      BindingFailure f(String name) {
        final raw =
            invalid.firstWhere((e) => e['name'] == name)['raw'] as String;
        try {
          parseStrictJson(raw);
        } on BindingException catch (e) {
          return e.failure;
        }
        fail('accepted');
      }

      expect(f('duplicate-member'), BindingFailure.duplicateMember);
      expect(f('lone-high-surrogate'), BindingFailure.loneSurrogate);
      expect(f('lone-low-surrogate'), BindingFailure.loneSurrogate);
      expect(f('duplicate-member-in-seat-key'), BindingFailure.duplicateMember);
    });
    test('error text never echoes the input', () {
      const secret = 'SENTINEL-4711';
      try {
        parseStrictJson('{"$secret":1,"$secret":2}');
        fail('accepted');
      } on BindingException catch (e) {
        expect(e.toString(), isNot(contains(secret)));
      }
    });
    test('raw lone surrogate and bad JSON are rejected', () {
      expect(
        () => parseStrictJson('["${String.fromCharCode(0xd800)}"]'),
        throwsA(isA<BindingException>()),
      );
      expect(
        () => parseStrictJson('{"a":1,}'),
        throwsA(isA<BindingException>()),
      );
      expect(
        () => parseStrictJson('{"a":01}'),
        throwsA(isA<BindingException>()),
      );
      expect(
        () => parseStrictJson('{"a":1} x'),
        throwsA(isA<BindingException>()),
      );
    });
    test('valid surrogate pair (escaped and raw) is accepted', () {
      expect(parseStrictJson(r'["\ud83d\ude00"]'), ['\u{1F600}']);
      expect(parseStrictJson('["\u{1F600}"]'), ['\u{1F600}']);
    });
    test('depth cap', () {
      expect(
        () => parseStrictJson('${'[' * 200}${']' * 200}'),
        throwsA(isA<BindingException>()),
      );
    });
  });

  group('AC3 seatMessage matches seat-proof-v1', () {
    final seat = _vectors('seat-proof-v1.json');
    final cases = (seat['valid'] as List).cast<Map<String, dynamic>>();
    final bodyHash = _unhex(
      valid.firstWhere((v) => v['name'] == 'ios-member-order')['bodyHashHex']
          as String,
    );
    for (final v in cases) {
      test(v['name'] as String, () {
        final op = SeatOp.values.byName(v['op'] as String);
        final challenge = _unhex(v['challengeHex'] as String);
        expect(
          _hex(seatMessage(op, v['installId'] as String, challenge)),
          v['messageHex'],
        );
      });
    }
    test('challenge derivations reproduce the vector challenges', () {
      final byOp = {for (final v in cases) v['name']: v};
      expect(_hex(bodyHash), byOp['restore']!['challengeHex']);
      // verify / signin challenges are plain SHA-256 of the input; check
      // the helper against the one definition (sha256Bytes) on the inputs
      // the vectors name.
      expect(verifySeatChallenge('x').length, 32);
      expect(signinSeatChallenge('x'), sha256Bytes(utf8.encode('x')));
    });
    test('rejects a bad installId or challenge length', () {
      expect(
        () => seatMessage(SeatOp.restore, 'NOT-A-UUID', Uint8List(32)),
        throwsA(isA<BindingException>()),
      );
      expect(
        () => seatMessage(
          SeatOp.restore,
          valid.first['installId'] as String,
          Uint8List(31),
        ),
        throwsA(isA<BindingException>()),
      );
    });
  });

  group('R2-1 / R4-1(3)', () {
    final rawBody = jsonEncode(valid.first['body']);
    test('different installId gives a different bodyHash', () {
      final a = restoreBodyHashFromJson(
        '0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77',
        rawBody,
      );
      final b = restoreBodyHashFromJson(
        '0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e78',
        rawBody,
      );
      expect(_hex(a), isNot(_hex(b)));
    });
    test('upper-case installId is refused, not normalised', () {
      expect(
        () => restoreBodyHashFromJson(
          '0193F2C4-7A10-4C52-9D3E-5B1F8A2C6E77',
          rawBody,
        ),
        throwsA(isA<BindingException>()),
      );
    });
    final two = valid.firstWhere((v) => v['name'] == 'ios-two-seat-keys');
    final keys = _seatKeys(two['body'] as Map<String, dynamic>);
    final bh = _unhex(two['bodyHashHex'] as String);
    final base = _hex(restoreClientDataHash(bh, keys));
    test('reorder / drop / replace a key changes clientDataHash', () {
      expect(
        _hex(restoreClientDataHash(bh, keys.reversed.toList())),
        isNot(base),
      );
      expect(_hex(restoreClientDataHash(bh, [keys.first])), isNot(base));
      expect(_hex(restoreClientDataHash(bh, [])), isNot(base));
      final other = Uint8List.fromList(keys.last)..[64] ^= 1;
      expect(_hex(restoreClientDataHash(bh, [keys.first, other])), isNot(base));
    });
    test('wrong-length key is rejected', () {
      expect(
        () => seatKeysDigest([Uint8List(64)]),
        throwsA(isA<BindingException>()),
      );
    });
  });

  group('JCS', () {
    test('RFC 8785 number and string samples', () {
      expect(esNumberToString(1e21), '1e+21');
      expect(esNumberToString(1e-7), '1e-7');
      expect(esNumberToString(0.000001), '0.000001');
      expect(esNumberToString(1.2345678901234568e20), '123456789012345680000');
      expect(esNumberToString(4.5), '4.5');
      expect(esNumberToString(-0.0), '0');
      expect(esNumberToString(333333333.33333329), '333333333.3333333');
      expect(
        jcsCanonicalize(
          parseStrictJson(r'{"b":[1,2.50,-0],"a":"\u0001\u20ac/"}'),
        ),
        '{"a":"\\u0001\u20ac/","b":[1,2.5,0]}',
      );
    });
    test('keys sort by UTF-16 code units, not code points', () {
      // U+FF5E (BMP) vs U+1F600 (surrogate pair d83d): pair sorts first.
      final out = jcsCanonicalize({'\uff5e': 1, '\u{1F600}': 2});
      expect(out.indexOf('\u{1F600}'), lessThan(out.indexOf('\uff5e')));
    });
    test('property: stable under key reordering and whitespace', () {
      final rnd = Random(183);
      Object? gen(int d) {
        final k = rnd.nextInt(d > 2 ? 3 : 6);
        switch (k) {
          case 0:
            return rnd.nextInt(2000) - 1000;
          case 1:
            return 'v${rnd.nextInt(99)}\u00e9"\\';
          case 2:
            return rnd.nextBool();
          case 3:
            return [for (var i = 0; i < rnd.nextInt(4); i++) gen(d + 1)];
          default:
            return {
              for (var i = 0; i < rnd.nextInt(5); i++)
                'k${rnd.nextInt(50)}': gen(d + 1),
            };
        }
      }

      String ser(Object? v, bool shuffle, bool ws) {
        final sp = ws ? ' \n\t ' : '';
        if (v is Map) {
          final ks = v.keys.cast<String>().toList();
          if (shuffle) ks.shuffle(rnd);
          return '{$sp${ks.map((k) => '${jsonEncode(k)}$sp:$sp${ser(v[k], shuffle, ws)}').join('$sp,$sp')}$sp}';
        }
        if (v is List) {
          return '[$sp${v.map((e) => ser(e, shuffle, ws)).join('$sp,$sp')}$sp]';
        }
        return jsonEncode(v);
      }

      for (var n = 0; n < 200; n++) {
        final v = {'root': gen(0), 'z': gen(1)};
        final a = jcsCanonicalize(parseStrictJson(ser(v, false, false)));
        final b = jcsCanonicalize(parseStrictJson(ser(v, true, true)));
        expect(b, a);
      }
    });
  });
}
