// Dev-only backend reach: a private LAN http address and pinned dev keys, both
// refused for a release build (docs/workflow/run-backend-locally.md).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/backend_client.dart';
import 'package:zaghlol/core/backend/response_signature.dart';

ResponseSignatureVerifier _verifier() => ResponseSignatureVerifier(const []);

BackendConfig _cfg(String uri, {bool lan = false, bool localhost = false}) =>
    BackendConfig(
      baseUri: Uri.parse(uri),
      verifier: _verifier(),
      allowInsecureLocalhost: localhost,
      allowPrivateLan: lan,
    );

void main() {
  group('BackendConfig private LAN (dev builds only)', () {
    const lan = [
      'http://192.168.1.20:8080',
      'http://10.0.0.5:8080',
      'http://172.16.0.9:8080',
      'http://172.31.255.1:8080',
    ];
    for (final u in lan) {
      test('$u is accepted only with allowPrivateLan', () {
        expect(_cfg(u, lan: true).baseUri.host, isNotEmpty);
        expect(() => _cfg(u), throwsArgumentError);
        expect(() => _cfg(u, localhost: true), throwsArgumentError);
      });
    }

    const refused = [
      'http://172.32.0.1:8080',
      'http://172.15.0.1:8080',
      'http://192.169.1.1:8080',
      'http://11.0.0.1:8080',
      'http://8.8.8.8:8080',
      'http://192.168.1.256:8080',
      'http://192.168.1.20.example.com:8080',
      'http://lan.local:8080',
      'http://[fd00::1]:8080',
    ];
    for (final u in refused) {
      test('$u is refused even with allowPrivateLan', () {
        expect(() => _cfg(u, lan: true), throwsArgumentError);
      });
    }

    test('https is unchanged and loopback still needs its own flag', () {
      expect(_cfg('https://api.zaghlol.app').baseUri.scheme, 'https');
      expect(
        () => _cfg('http://localhost:8080', lan: true),
        throwsArgumentError,
      );
      expect(_cfg('http://10.0.2.2:8080', localhost: true).baseUri.port, 8080);
    });

    test('isPrivateLanIpv4 matches RFC 1918 only', () {
      expect(BackendConfig.isPrivateLanIpv4('192.168.0.1'), isTrue);
      expect(BackendConfig.isPrivateLanIpv4('169.254.1.1'), isFalse);
      // FU-228 B1: leading-zero octets can be octal to a resolver.
      expect(BackendConfig.isPrivateLanIpv4('010.0.0.1'), isFalse);
      expect(BackendConfig.isPrivateLanIpv4('192.168.00.1'), isFalse);
      expect(BackendConfig.isPrivateLanIpv4('10.0.0.1'), isTrue);
      expect(BackendConfig.isPrivateLanIpv4('192.168.0.1'), isTrue);
      expect(BackendConfig.isPrivateLanIpv4('127.0.0.1'), isFalse);
    });
  });

  group('parseDevBackendKeys', () {
    final jwks =
        (jsonDecode(
              File(
                '../backend/tests/Zaghlol.Contract.Tests/vectors/response-signature-v1.json',
              ).readAsStringSync(),
            ) as Map<String, Object?>)['jwks']!
            as Map<String, Object?>;
    final k = (jwks['keys']! as List<Object?>).first! as Map<String, Object?>;

    test('empty text gives no keys', () {
      expect(parseDevBackendKeys(''), isEmpty);
      expect(parseDevBackendKeys('  '), isEmpty);
    });

    test('parses a dev kid and refuses production-style kids and junk', () {
      final x = k['x']! as String;
      final y = k['y']! as String;
      final keys = parseDevBackendKeys('s0000d:$x:$y,e0000d:$x:$y');
      expect(keys.map((e) => e.kid), ['s0000d', 'e0000d']);
      expect(
        () => parseDevBackendKeys('s0000d:AAAA:BBBB'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('ZAGHLOL_DEV_KEYS'),
          ),
        ),
      );
      expect(() => parseDevBackendKeys('s2026a:$x:$y'), throwsArgumentError);
      expect(() => parseDevBackendKeys('s0000d:$x'), throwsArgumentError);
      expect(
        () => parseDevBackendKeys('s0000d:AAAA:BBBB'),
        throwsArgumentError,
      );
    });
  });
}
