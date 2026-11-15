// TEST-explorer: the tap-everything engine finds a dead button, a thrown
// exception and an overflow, follows a pushed screen and a dialog, and goes
// back after each tap.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/explorer.dart';

class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  bool on = false;
  int n = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home page')),
      body: ListView(
        children: [
          TextButton(onPressed: () {}, child: const Text('Dead button')),
          TextButton(
            onPressed: () => setState(() => n++),
            child: Text('Count $n'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const _Detail())),
            child: const Text('Open detail'),
          ),
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Sure?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
            child: const Text('Open dialog'),
          ),
          TextButton(
            onPressed: () => throw StateError('boom'),
            child: const Text('Throws'),
          ),
          Switch(value: on, onChanged: (v) => setState(() => on = v)),
          const SizedBox(
            width: 40,
            child: Row(children: [SizedBox(width: 80, height: 10)]),
          ),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detail page')),
    body: Center(
      child: ElevatedButton(onPressed: () {}, child: const Text('Detail dead')),
    ),
  );
}

void main() {
  testWidgets('finds dead taps, exceptions and overflows; walks screens', (
    t,
  ) async {
    await t.pumpWidget(const MaterialApp(home: _Home()));
    final shots = <String>[];
    final ex = Explorer(
      tester: t,
      shot: (n) async => shots.add(n),
      deadline: DateTime.now().add(const Duration(minutes: 2)),
      goHome: () async {},
      log: (_) {},
    )..install();
    await ex.exploreCurrent('Home');
    ex.uninstall();
    final md = ex.markdown();
    final issues = [for (final s in ex.screens) ...s.issues];
    expect(
      issues.where((i) => i.kind == 'dead-tap').map((i) => i.where),
      containsAll(['button "Dead button"', 'button "Detail dead"']),
    );
    expect(issues.where((i) => i.kind == 'exception'), isNotEmpty);
    expect(
      ex.screens.map((s) => s.title),
      containsAll(['Home', 'Detail page', 'Sure?']),
    );
    // Back on the first screen after everything.
    expect(find.text('Home page'), findsOneWidget);
    expect(find.text('Detail page'), findsNothing);
    expect(find.text('Sure?'), findsNothing);
    expect(shots.length, ex.screens.length);
    expect(md, contains('## Issues'));
  });
}
