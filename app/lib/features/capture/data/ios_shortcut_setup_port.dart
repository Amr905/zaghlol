// T-064: the Shortcuts setup check's native input (per-intent last-run
// times) behind a small port, so the checker is testable with a fake. Errors
// are code-only; the times carry no content.

import 'package:flutter/services.dart';
import 'package:zaghlol_domain/zaghlol_domain.dart';

import '../../../core/platform/capture_api.g.dart';
import 'capture_host_port.dart' show CaptureHostException;

abstract interface class ShortcutSetupPort {
  Future<ShortcutSetupStatus> status();
}

final class IosShortcutSetupPort implements ShortcutSetupPort {
  IosShortcutSetupPort([IosCaptureHostApi? api])
    : _api = api ?? IosCaptureHostApi();

  final IosCaptureHostApi _api;

  @override
  Future<ShortcutSetupStatus> status() async {
    try {
      return await _api.getShortcutSetupStatus();
    } on PlatformException catch (e) {
      throw CaptureHostException(PlatformFailure.fromChannel(e.code));
    } on Exception {
      throw CaptureHostException(PlatformFailure.fromChannel(null));
    }
  }
}
