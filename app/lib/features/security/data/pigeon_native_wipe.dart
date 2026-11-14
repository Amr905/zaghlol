// T-166: the native part of "Delete everything" over the capture host APIs
// (`wipeLocalData`, platform-channels §1.3). Errors carry a code only.

import '../../../core/platform/capture_api.g.dart';
import '../application/delete_everything.dart';

final class PigeonNativeWipe implements NativeWipe {
  PigeonNativeWipe({required this._ios, this._android, this._iosApi});

  final bool _ios;
  final AndroidCaptureHostApi? _android;
  final IosCaptureHostApi? _iosApi;

  @override
  Future<void> wipeLocalData() => _ios
      ? (_iosApi ?? IosCaptureHostApi()).wipeLocalData()
      : (_android ?? AndroidCaptureHostApi()).wipeLocalData();
}
