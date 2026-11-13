// T-141: the HTTP port of BackendClient and its `dart:io` adapter.
//
// The client builds every request; the transport only moves bytes. It never
// logs, never follows redirects, and caps what it reads. Bodies arrive
// decompressed (`HttpClient.autoUncompress`), so the signature is checked over
// the bytes the server signed (backend-api §1).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Largest response body read (the backend's signing buffer is 1 MiB, T-123).
const int maxResponseBytes = 1 << 20;

final class BackendRequest {
  BackendRequest({
    required this.method,
    required this.uri,
    required Map<String, String> headers,
    this.body,
  }) : headers = Map.unmodifiable(headers);

  final String method;
  final Uri uri;

  /// Lower-case header names.
  final Map<String, String> headers;
  final Uint8List? body;

  /// Never prints headers or body (tokens, keys, purchase data).
  @override
  String toString() => 'BackendRequest($method ${uri.path})';
}

final class BackendResponse {
  BackendResponse({
    required this.status,
    required Map<String, List<String>> headers,
    required this.body,
  }) : headers = {
         for (final e in headers.entries)
           e.key.toLowerCase(): List.unmodifiable(e.value),
       };

  final int status;

  /// Lower-case header names, every received value.
  final Map<String, List<String>> headers;
  final Uint8List body;

  /// The value of a header sent exactly once; null when absent or repeated.
  String? single(String name) {
    final v = headers[name.toLowerCase()];
    return v != null && v.length == 1 ? v.single : null;
  }

  @override
  String toString() => 'BackendResponse($status)';
}

enum TransportFailureKind { offline, timeout, tooLarge, protocol }

/// A transport-level failure. Kind only; no OS message crosses over.
final class TransportException implements Exception {
  const TransportException(this.kind);
  final TransportFailureKind kind;
  @override
  String toString() => 'TransportException(${kind.name})';
}

abstract interface class BackendTransport {
  /// Sends [request]. Throws [TransportException] only.
  Future<BackendResponse> send(BackendRequest request);
}

/// The production transport over `dart:io` [HttpClient].
final class IoBackendTransport implements BackendTransport {
  IoBackendTransport({
    HttpClient? client,
    this.connectTimeout = const Duration(seconds: 10),
    this.totalTimeout = const Duration(seconds: 40),
  }) : _client = client ?? HttpClient() {
    _client
      ..connectionTimeout = connectTimeout
      ..autoUncompress = true;
  }

  final HttpClient _client;
  final Duration connectTimeout;
  final Duration totalTimeout;

  @override
  Future<BackendResponse> send(BackendRequest request) async {
    try {
      return await _send(request).timeout(totalTimeout);
    } on TransportException {
      rethrow;
    } on TimeoutException {
      throw const TransportException(TransportFailureKind.timeout);
    } on SocketException {
      throw const TransportException(TransportFailureKind.offline);
    } on HandshakeException {
      throw const TransportException(TransportFailureKind.protocol);
    } on Object {
      // HttpException, TlsException, ...: their messages are never read.
      throw const TransportException(TransportFailureKind.protocol);
    }
  }

  Future<BackendResponse> _send(BackendRequest request) async {
    final req = await _client.openUrl(request.method, request.uri);
    req.followRedirects = false;
    request.headers.forEach(req.headers.set);
    final body = request.body;
    if (body != null) {
      req.contentLength = body.length;
      req.add(body);
    }
    final res = await req.close();
    if (res.contentLength > maxResponseBytes) {
      await res.detachSocket().then((s) => s.destroy());
      throw const TransportException(TransportFailureKind.tooLarge);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res) {
      builder.add(chunk);
      if (builder.length > maxResponseBytes) {
        throw const TransportException(TransportFailureKind.tooLarge);
      }
    }
    final headers = <String, List<String>>{};
    res.headers.forEach((name, values) => headers[name] = values);
    return BackendResponse(
      status: res.statusCode,
      headers: headers,
      body: builder.takeBytes(),
    );
  }
}
