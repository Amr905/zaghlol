// T-340 AC3 "cancellation aborts the request": the dart:io transport drops
// the connection when the request's AbortSignal fires, against a local
// server that never answers.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/backend/transport.dart';

void main() {
  test('abort while waiting for the answer: the call fails with cancelled '
      'at once', () async {
    // flutter_test swaps in a fake HttpClient; this test needs the real one.
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final held = <HttpRequest>[];
    // Never answers.
    server.listen(held.add);
    final t = IoBackendTransport();
    final abort = AbortSignal();
    final f = t.send(
      BackendRequest(
        method: 'POST',
        uri: Uri.parse('http://127.0.0.1:${server.port}/v1/ask/plan'),
        headers: {'content-type': 'application/json'},
        body: null,
        abort: abort,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    abort.abort();
    await expectLater(
      f,
      throwsA(
        isA<TransportException>().having(
          (e) => e.kind,
          'kind',
          TransportFailureKind.cancelled,
        ),
      ),
    );
    expect(held, hasLength(1));
    await server.close(force: true);
  });

  test('already aborted: nothing is opened', () async {
    final abort = AbortSignal()..abort();
    await expectLater(
      IoBackendTransport().send(
        BackendRequest(
          method: 'GET',
          uri: Uri.parse('http://127.0.0.1:9/never'),
          headers: const {},
          abort: abort,
        ),
      ),
      throwsA(
        isA<TransportException>().having(
          (e) => e.kind,
          'kind',
          TransportFailureKind.cancelled,
        ),
      ),
    );
  });
}
