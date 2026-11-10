import 'dart:async';

import 'package:flutter/services.dart' show BinaryMessenger;

import 'share_intake_api.g.dart';

export 'share_intake_api.g.dart'
    show ShareContent, ShareDescriptor, ShareKind, ShareRejectReason;

/// What the native share target (T-060) tells Dart. Contains no content.
sealed class ShareIntakeEvent {
  const ShareIntakeEvent();
}

/// A share was validated and stored encrypted; read it with
/// [ShareIntakeService.read].
final class ShareReceived extends ShareIntakeEvent {
  const ShareReceived(this.descriptor);

  final ShareDescriptor descriptor;
}

/// A share was refused natively (type, size or readability). Show a localized
/// message; there is nothing to clean up.
final class ShareRejected extends ShareIntakeEvent {
  const ShareRejected(this.reason);

  final ShareRejectReason reason;
}

/// Dart side of the Android share intake channel
/// (docs/03-technical/platform-channels.md, "Share intake").
///
/// Usage: listen to [events], call [attach], then [pollPending] at startup
/// and on every app resume (the native side also re-announces every pending
/// share on resume; ids are deduplicated here). For each [ShareReceived],
/// call [read] only after the app lock is open (T-103), run the
/// confirmation / OCR flow, and finally [discard]. Never log what [read]
/// returns. Wiring owners: see FU-067 in docs/implementation-status.md.
class ShareIntakeService implements ShareIntakeEventsApi {
  ShareIntakeService({ShareIntakeHostApi? host, BinaryMessenger? messenger})
    : _host = host ?? ShareIntakeHostApi(binaryMessenger: messenger),
      _messenger = messenger;

  final ShareIntakeHostApi _host;
  final BinaryMessenger? _messenger;
  final StreamController<ShareIntakeEvent> _events =
      StreamController<ShareIntakeEvent>.broadcast();
  final Set<String> _announced = <String>{};

  Stream<ShareIntakeEvent> get events => _events.stream;

  /// Starts receiving warm-start events from native.
  void attach() =>
      ShareIntakeEventsApi.setUp(this, binaryMessenger: _messenger);

  void detach() =>
      ShareIntakeEventsApi.setUp(null, binaryMessenger: _messenger);

  /// Startup and every resume: emits a refusal that happened while Dart was
  /// not listening and every stored share not yet announced.
  Future<void> pollPending() async {
    final ShareRejectReason? rejection = await _host.takePendingRejection();
    if (rejection != null) {
      _events.add(ShareRejected(rejection));
    }
    for (final ShareDescriptor d in await _host.listPendingShares()) {
      if (_announced.add(d.id)) {
        _events.add(ShareReceived(d));
      }
    }
  }

  /// Decrypted content, in memory only. Throws a `PlatformException` with
  /// code `IO_ERROR` (unknown id, or a transient failure: the share is kept
  /// and a later call may succeed) or `SPOOL_DECRYPT_FAILED` (tampered or
  /// unreadable with the current key: the share is already deleted).
  Future<ShareContent> read(String id) => _host.readShare(id);

  /// Call after the user confirmed or cancelled; deletes the encrypted files.
  Future<void> discard(String id) async {
    _announced.remove(id);
    await _host.discardShare(id);
  }

  Future<void> dispose() async {
    detach();
    await _events.close();
  }

  @override
  void onShareReceived(ShareDescriptor descriptor) {
    if (_announced.add(descriptor.id)) {
      _events.add(ShareReceived(descriptor));
    }
  }

  @override
  void onShareRejected(ShareRejectReason reason) {
    _events.add(ShareRejected(reason));
  }
}
