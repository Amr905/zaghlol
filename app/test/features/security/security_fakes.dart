import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/platform/device_api.g.dart';
import 'package:zaghlol/features/security/data/device_security_providers.dart';

/// A fake platform for DeviceSecurityHostApi: answers the three Pigeon
/// channels on the default messenger, so the real Dart class and codec run.
class FakeDevicePlatform {
  FakeDevicePlatform({this.rooted = false, this.secure = true});

  bool rooted;
  bool secure;
  bool throwOnSecureWindow = false;
  final List<bool> secureWindowCalls = [];

  static const _prefix = 'dev.flutter.pigeon.zaghlol.DeviceSecurityHostApi';

  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    void on(String method, Object? Function(List<Object?> args) f) {
      messenger.setMockDecodedMessageHandler<Object?>(
        BasicMessageChannel<Object?>(
          '$_prefix.$method',
          DeviceSecurityHostApi.pigeonChannelCodec,
        ),
        (message) async => <Object?>[f((message as List<Object?>?) ?? [])],
      );
    }

    on('isDeviceRooted', (_) => rooted);
    on('isDeviceSecure', (_) => secure);
    messenger.setMockDecodedMessageHandler<Object?>(
      BasicMessageChannel<Object?>(
        '$_prefix.setSecureWindow',
        DeviceSecurityHostApi.pigeonChannelCodec,
      ),
      (message) async {
        if (throwOnSecureWindow) {
          return <Object?>['NOT_AVAILABLE', null, null];
        }
        secureWindowCalls.add((message! as List<Object?>).first! as bool);
        return <Object?>[null];
      },
    );
    addTearDown(() {
      for (final m in ['isDeviceRooted', 'isDeviceSecure', 'setSecureWindow']) {
        messenger.setMockDecodedMessageHandler<Object?>(
          BasicMessageChannel<Object?>(
            '$_prefix.$m',
            DeviceSecurityHostApi.pigeonChannelCodec,
          ),
          null,
        );
      }
    });
  }
}

/// Scripted authenticator: pops one outcome per call, records the reasons.
class FakeAuthenticator implements AppAuthenticator {
  FakeAuthenticator([List<AuthOutcome>? script])
    : script = script ?? [AuthOutcome.success];

  final List<AuthOutcome> script;
  final List<String> reasons = [];

  @override
  Future<AuthOutcome> authenticate(String reason) async {
    reasons.add(reason);
    return script.length > 1 ? script.removeAt(0) : script.first;
  }
}
