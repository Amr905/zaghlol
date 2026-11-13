// T-141: the recording hook for privacy contract tests (security-model §2.4).
// Debug and test only: it refuses to exist in a release (product) build.

import '../transport.dart';

/// Wraps a transport and keeps every request it sends, so a test can assert
/// that each outgoing body matches the BR-SYNC-03 allow-list.
final class RecordingBackendTransport implements BackendTransport {
  RecordingBackendTransport(this._inner) {
    if (const bool.fromEnvironment('dart.vm.product')) {
      throw UnsupportedError('debug only');
    }
  }

  final BackendTransport _inner;
  final List<BackendRequest> requests = [];

  @override
  Future<BackendResponse> send(BackendRequest request) {
    requests.add(request);
    return _inner.send(request);
  }
}
