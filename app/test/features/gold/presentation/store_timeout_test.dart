import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/features/gold/presentation/gold_ui_ports.dart';

void main() {
  testWidgets('withStoreTimeout throws TimeoutException offline', (
    tester,
  ) async {
    final never = Completer<int>().future;
    Object? error;
    unawaited(
      withStoreTimeout(never).then((_) {}, onError: (Object e) => error = e),
    );
    await tester.pump(goldStoreTimeout + const Duration(seconds: 1));
    expect(error, isA<TimeoutException>());
  });
}
