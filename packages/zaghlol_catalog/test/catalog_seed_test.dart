// T-030: strict seed codec and ES256 signature. Synthetic catalog data.

import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zaghlol_catalog/zaghlol_catalog.dart';

const _cat = SeedCategory(
  code: 'groceries',
  nameAr: 'بقالة',
  nameEn: 'Groceries',
  icon: 'cart',
  color: '#174C4F',
  bucket: 'needs',
  sort: 1,
);
const _merchant = SeedMerchant(
  id: 1,
  canonical: 'Carrefour',
  nameAr: 'كارفور',
  category: 'groceries',
);
const _alias = SeedAlias(merchantId: 1, alias: 'carrefour', match: 'prefix');
const _keyword = SeedKeyword(
  keyword: 'فاكهه',
  lang: 'ar',
  category: 'groceries',
  weight: 60,
);

Uint8List _bytes(Object json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

Map<String, Object?> _doc(List<Map<String, Object?>> ops) => {
  'version': 1,
  'ops': ops,
};

String? _codeOf(void Function() f) {
  try {
    f();
    return null;
  } on CatalogSeedException catch (e) {
    return e.code;
  }
}

void main() {
  group('codec', () {
    test('encode then decode round-trips, Arabic kept as UTF-8', () {
      final seed = CatalogSeed.validated(
        version: 3,
        ops: [_cat, _merchant, _alias, _keyword],
      );
      final bytes = seed.encode();
      expect(utf8.decode(bytes), contains('بقالة'));
      final back = CatalogSeed.decode(bytes);
      expect(back.version, 3);
      expect(back.encode(), bytes);
      expect(back.categories.single.nameAr, 'بقالة');
      expect(back.aliases.single.match, 'prefix');
    });

    test('members are written in a fixed order, without whitespace', () {
      final text = utf8.decode(
        CatalogSeed.validated(version: 1, ops: [_cat]).encode(),
      );
      expect(
        text,
        '{"version":1,"ops":[{"t":"category","op":"upsert","code":"groceries",'
        '"nameAr":"بقالة","nameEn":"Groceries","icon":"cart","color":"#174C4F",'
        '"bucket":"needs","sort":1}]}',
      );
    });

    final good = [
      _cat.toJson(),
      _merchant.toJson(),
      _alias.toJson(),
      _keyword.toJson(),
    ];

    test('the good document decodes', () {
      expect(() => CatalogSeed.decode(_bytes(_doc(good))), returnsNormally);
    });

    Map<String, Object?> with_(int index, String key, Object? value) {
      final ops = [for (final o in good) Map<String, Object?>.of(o)];
      if (value == #remove) {
        ops[index].remove(key);
      } else {
        ops[index][key] = value;
      }
      return _doc(ops);
    }

    final bad = <String, (Map<String, Object?>, String)>{
      'unknown op member': (
        with_(0, 'extra', 1),
        CatalogSeedException.unknownKey,
      ),
      'missing member': (
        with_(0, 'icon', #remove),
        CatalogSeedException.unknownKey,
      ),
      'tombstone': (with_(1, 'op', 'delete'), CatalogSeedException.badShape),
      'unknown entity': (with_(1, 't', 'logo'), CatalogSeedException.badShape),
      'string id': (with_(1, 'id', '1'), CatalogSeedException.badShape),
      'double id': (with_(1, 'id', 1.0), CatalogSeedException.badShape),
      'id zero': (with_(1, 'id', 0), CatalogSeedException.badValue),
      'bad colour': (with_(0, 'color', 'red'), CatalogSeedException.badValue),
      'bad bucket': (with_(0, 'bucket', 'misc'), CatalogSeedException.badValue),
      'bad code': (
        with_(0, 'code', 'Groceries'),
        CatalogSeedException.badValue,
      ),
      'control char in name': (
        with_(0, 'nameEn', 'a\u0007b'),
        CatalogSeedException.badValue,
      ),
      'alias with a capital': (
        with_(2, 'alias', 'Carrefour'),
        CatalogSeedException.badValue,
      ),
      'alias with a double space': (
        with_(2, 'alias', 'a  b'),
        CatalogSeedException.badValue,
      ),
      'alias too long': (
        with_(2, 'alias', 'a' * 65),
        CatalogSeedException.badValue,
      ),
      'alias match mode': (
        with_(2, 'match', 'fuzzy'),
        CatalogSeedException.badValue,
      ),
      'alias of a missing merchant': (
        with_(2, 'merchantId', 9),
        CatalogSeedException.danglingRef,
      ),
      'merchant in a missing category': (
        with_(1, 'category', 'nowhere'),
        CatalogSeedException.danglingRef,
      ),
      'keyword weight 101': (
        with_(3, 'weight', 101),
        CatalogSeedException.badValue,
      ),
      'keyword language': (
        with_(3, 'lang', 'arb'),
        CatalogSeedException.badValue,
      ),
    };
    bad.forEach((name, c) {
      test('rejects $name', () {
        final (doc, code) = c;
        expect(_codeOf(() => CatalogSeed.decode(_bytes(doc))), code);
      });
    });

    test('rejects a duplicate of each kind', () {
      for (final dup in [_cat, _merchant, _alias, _keyword]) {
        final ops = [_cat, _merchant, _alias, _keyword];
        final i = ops.indexOf(dup);
        ops.insert(i, dup);
        expect(
          _codeOf(() => CatalogSeed.validated(version: 1, ops: ops)),
          anyOf(CatalogSeedException.duplicate, CatalogSeedException.badOrder),
          reason: '${dup.runtimeType}',
        );
      }
      expect(
        _codeOf(
          () => CatalogSeed.validated(
            version: 1,
            ops: [_cat, _merchant, _alias, _alias],
          ),
        ),
        CatalogSeedException.duplicate,
      );
    });

    test('rejects children before their parents', () {
      expect(
        _codeOf(
          () => CatalogSeed.validated(
            version: 1,
            ops: [_cat, _merchant, _keyword, _alias],
          ),
        ),
        CatalogSeedException.badOrder,
      );
    });

    test('rejects non-JSON, wrong roots, extra root members, version 0', () {
      expect(
        _codeOf(() => CatalogSeed.decode(Uint8List.fromList([0xff, 0xfe]))),
        CatalogSeedException.notJson,
      );
      expect(
        _codeOf(() => CatalogSeed.decode(_bytes([1]))),
        CatalogSeedException.badShape,
      );
      expect(
        _codeOf(
          () => CatalogSeed.decode(
            _bytes({'version': 1, 'ops': <Object?>[], 'x': 1}),
          ),
        ),
        CatalogSeedException.unknownKey,
      );
      expect(
        _codeOf(
          () => CatalogSeed.decode(_bytes({'version': 0, 'ops': <Object?>[]})),
        ),
        CatalogSeedException.badValue,
      );
    });

    test('rejects an oversized document without parsing it', () {
      expect(
        _codeOf(() => CatalogSeed.decode(Uint8List(maxSeedJsonBytes + 1))),
        CatalogSeedException.tooLarge,
      );
    });

    test('an error prints its code only', () {
      final e = CatalogSeedException(CatalogSeedException.badValue);
      expect(e.toString(), 'SEED_BAD_VALUE');
    });
  });

  group('signature', () {
    // The dev key of tools/catalog_build/dev (public half is bundled).
    final signer = SeedSigner(
      kid: 's0000d',
      d: Uint8List.fromList(
        base64Url.decode(
          base64Url.normalize('Ugg7grDnVzLNiizJ9h2zFYluYtvmPmPDes7VQT0SKGY'),
        ),
      ),
    );
    final keys = bundledSeedKeys();
    final message = CatalogSeed.validated(version: 1, ops: [_cat]).encode();

    test('a signed seed verifies and names the kid', () {
      final header = signer.sign(message);
      expect(
        header,
        matches(RegExp(r'^kid=s0000d; alg=ES256; sig=[A-Za-z0-9_-]{86}$')),
      );
      expect(verifySeedSignature(message, header, keys), 's0000d');
    });

    test('signing is deterministic', () {
      expect(signer.sign(message), signer.sign(message));
    });

    test('a single flipped bit in the body is rejected', () {
      final header = signer.sign(message);
      for (final i in [0, message.length ~/ 2, message.length - 1]) {
        final tampered = Uint8List.fromList(message)..[i] ^= 0x01;
        expect(
          _codeOf(() => verifySeedSignature(tampered, header, keys)),
          CatalogSeedException.badSignature,
        );
      }
    });

    test('a flipped signature bit, truncation and extension are rejected', () {
      final header = signer.sign(message);
      final sig = header.substring(header.indexOf('sig=') + 4);
      final flipped = sig.replaceRange(0, 1, sig[0] == 'A' ? 'B' : 'A');
      for (final bad in [
        'kid=s0000d; alg=ES256; sig=$flipped',
        'kid=s0000d; alg=ES256; sig=${sig.substring(1)}',
        'kid=s0000d; alg=ES256; sig=${sig}A',
        '',
        'garbage',
        'kid=s0000d; alg=none; sig=$sig',
        'kid=s0000d; alg=ES256; sig=${'A' * 86}',
        'kid=s0000d; alg=ES256; sig=$sig; extra=1',
      ]) {
        expect(
          _codeOf(() => verifySeedSignature(message, bad, keys)),
          CatalogSeedException.badSignature,
          reason: bad.length > 40 ? bad.substring(0, 40) : bad,
        );
      }
    });

    test('an unknown kid and an empty key set are rejected', () {
      final header = signer.sign(message).replaceFirst('s0000d', 's9999z');
      expect(
        _codeOf(() => verifySeedSignature(message, header, keys)),
        CatalogSeedException.badSignature,
      );
      expect(
        _codeOf(
          () => verifySeedSignature(
            message,
            signer.sign(message),
            <SeedTrustedKey>[],
          ),
        ),
        CatalogSeedException.badSignature,
      );
    });

    test('a signature by another key is rejected under the same kid', () {
      final other = SeedSigner(kid: 's0000d', d: Uint8List(32)..[31] = 7);
      expect(
        _codeOf(() => verifySeedSignature(message, other.sign(message), keys)),
        CatalogSeedException.badSignature,
      );
    });

    test('a key that is not on the curve is refused', () {
      expect(
        () => SeedTrustedKey(kid: 's0001a', x: Uint8List(32), y: Uint8List(32)),
        throwsArgumentError,
      );
    });

    test('the bundled trusted set is exactly the dev key until release', () {
      expect([for (final k in keys) k.kid], ['s0000d']);
    });
  });
}
