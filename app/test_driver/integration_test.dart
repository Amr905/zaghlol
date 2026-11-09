// T-007: host-side driver for `flutter drive` runs of
// integration_test/db_platform_test.dart on real devices
// (docs/05-reviews/T-007-device.md).
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
