// FU-229b: opens this app's page in the system settings (Android
// ACTION_APPLICATION_DETAILS_SETTINGS, iOS openSettingsURLString), for the
// "Open settings" of a denied permission (microphone). Nothing else crosses
// this channel.

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const MethodChannel appSettingsChannel = MethodChannel('zaghlol/app_settings');

/// Opens the app details page. Default: the real channel; a missing host
/// (tests, headless engine) does nothing. Never throws.
final openAppSettingsProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    try {
      await appSettingsChannel.invokeMethod<void>('open');
    } on PlatformException {
      // Nothing to open.
    } on MissingPluginException {
      // No host on this platform.
    }
  },
  name: 'openAppSettingsProvider',
);
