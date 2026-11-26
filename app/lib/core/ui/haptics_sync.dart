import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/mascot/presentation/zaghlol_avatar.dart';
import '../settings/settings_providers.dart';
import 'z_haptics.dart';

/// Keeps [ZHaptics.enabled] and [ZHaptics.reduceMotion] in step with the
/// in-app settings (T-298). Watched once from the app root; it is the only
/// writer, so widgets never touch the statics.
final hapticsSyncProvider = Provider<void>((ref) {
  ZHaptics.enabled = ref.watch(hapticsEnabledProvider).value ?? true;
  ZHaptics.reduceMotion = ref.watch(reduceMotionProvider);
}, name: 'hapticsSyncProvider');
