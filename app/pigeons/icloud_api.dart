// Pigeon contract: icloud (T-004). Names only; methods, data classes and
// error handling are added by the owner task of each API, following
// docs/03-technical/platform-channels.md. Regenerate with
// app/tool/generate_pigeon.sh; CI fails when the generated files are stale.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/icloud_api.g.dart',
    dartPackageName: 'zaghlol',
    kotlinOut: 'android/app/src/main/kotlin/app/zaghlol/platform/icloud/IcloudApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'app.zaghlol.platform.icloud',
      errorClassName: 'IcloudApiError',
    ),
    swiftOut: 'ios/Runner/Platform/IcloudApi.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'IcloudApiError'),
  ),
)
@HostApi()
abstract class ICloudBackupHostApi {}
