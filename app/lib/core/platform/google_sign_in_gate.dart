import 'package:flutter_riverpod/flutter_riverpod.dart';

// google_sign_in 7.x keeps one global configuration (including the nonce), so
// the sign-in flow and the Drive authorizer must not interleave their
// initialize/authenticate pairs (FU-189b).

/// Serializes Google plugin sessions and counts the nonce configurations.
final class GoogleSignInGate {
  GoogleSignInGate();

  Future<void> _tail = Future<void>.value();
  int _epoch = 0;

  /// Bumped by every session that configured the plugin with a nonce; a
  /// holder of a no-nonce configuration must initialize again when it moved.
  int get epoch => _epoch;

  /// Runs [body] after every earlier session finished. [setsNonce] marks a
  /// session that re-initializes the plugin with its own nonce.
  Future<T> run<T>(Future<T> Function() body, {bool setsNonce = false}) {
    final result = _tail.then((_) {
      if (setsNonce) _epoch++;
      return body();
    });
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

/// The one gate shared by sign-in, Drive auth and delete-everything.
final googleSignInGateProvider = Provider<GoogleSignInGate>(
  (ref) => GoogleSignInGate(),
  name: 'googleSignInGateProvider',
);
