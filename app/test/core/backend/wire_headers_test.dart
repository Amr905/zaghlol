// FU-208a: the BR-SYNC-03 header allow-list is checked on what the client
// hands to the transport; dart:io adds headers of its own below that. This
// test reads the headers a loopback server actually receives from the real
// transport. Synthetic values only.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/transport.dart';

import '../../privacy/support/br_sync_03.dart';

void main() {
  test(
    'the real transport adds only host and protocol framing headers',
    () async {
      // flutter_test swaps in a fake HttpClient; this test needs the real one.
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = <String>{};
      server.listen((req) async {
        req.headers.forEach((name, _) => seen.add(name.toLowerCase()));
        await req.drain<void>();
        req.response
          ..statusCode = 200
          ..write('{}');
        await req.response.close();
      });
      final transport = IoBackendTransport();
      await transport.send(
        BackendRequest(
          method: 'POST',
          uri: Uri.parse('http://127.0.0.1:${server.port}/v1/sync'),
          headers: {
            'zaghlol-app': 'android/1.0.0 (1)',
            'content-type': 'application/json',
          },
          body: Uint8List.fromList(utf8.encode('{}')),
        ),
      );
      // Framing and transport headers that carry nothing about the device.
      const framing = {'host', 'content-length', 'accept-encoding'};
      final extra = seen.difference(allowedHeaders).difference(framing);
      expect(extra, isEmpty);
      expect(seen, isNot(contains('user-agent')));
    },
  );
}
