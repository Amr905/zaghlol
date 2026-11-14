// T-166: the in-process restart rebuilds the whole provider graph.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/app/app_restart.dart';

void main() {
  testWidgets('restart disposes the old scope, runs beforeStart, then builds '
      'a fresh one', (tester) async {
    final log = <String>[];
    var built = 0;
    final counter = Provider<int>((ref) {
      final n = ++built;
      log.add('create $n');
      ref.onDispose(() => log.add('dispose $n'));
      return n;
    });

    await tester.pumpWidget(
      AppRestartScope(
        beforeStart: () async => log.add('beforeStart'),
        builder: (context, restart) => ProviderScope(
          overrides: [appRestartProvider.overrideWithValue(restart)],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Consumer(
              builder: (context, ref, _) => GestureDetector(
                onTap: () => ref.read(appRestartProvider)(),
                child: Text('gen ${ref.watch(counter)}'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('gen 1'), findsOneWidget);

    await tester.tap(find.text('gen 1'));
    await tester.pumpAndSettle();

    expect(find.text('gen 2'), findsOneWidget);
    expect(log, ['create 1', 'dispose 1', 'beforeStart', 'create 2']);
  });
}
