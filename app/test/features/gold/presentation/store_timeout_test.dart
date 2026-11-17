import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
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

  testWidgets('goldOffersProvider ends in the error state when the store '
      'never answers (prices failed)', (tester) async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        goldProductQueryProvider.overrideWithValue(
          (_) => Completer<ProductDetailsResponse>().future,
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(goldOffersProvider, (_, _) {});
    addTearDown(sub.close);
    expect(container.read(goldOffersProvider).isLoading, isTrue);
    await tester.pump(goldStoreTimeout + const Duration(seconds: 1));
    final state = container.read(goldOffersProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<TimeoutException>());
  });
}
